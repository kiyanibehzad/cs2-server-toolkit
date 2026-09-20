const fs = require('fs');
const path = require('path');
const http = require('http');
const crypto = require('crypto');
const os = require('os');
const { spawn, execFile } = require('child_process');
const express = require('express');
const { WebSocketServer } = require('ws');
const { executeRcon } = require('./rcon');

// ---------- CONFIGURATION LOADING ----------
function loadEnvFile() {
  const possiblePaths = [
    process.env.CONF_PATH,
    path.join(process.env.HOME || '', 'cs2-ds', '.update.env'),
    path.join(__dirname, '..', '.update.env'),
    path.join(__dirname, '.update.env')
  ].filter(Boolean);

  const env = {};
  for (const p of possiblePaths) {
    if (fs.existsSync(p)) {
      try {
        const content = fs.readFileSync(p, 'utf8');
        for (const line of content.split('\n')) {
          const trimmed = line.trim();
          if (!trimmed || trimmed.startsWith('#')) continue;
          const eqIdx = trimmed.indexOf('=');
          if (eqIdx !== -1) {
            const key = trimmed.slice(0, eqIdx).trim();
            let val = trimmed.slice(eqIdx + 1).trim();
            // strip surrounding quotes
            if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
              val = val.slice(1, -1);
            }
            env[key] = val;
          }
        }
        console.log(`[Config] Loaded environment from: ${p}`);
        break;
      } catch (e) {
        console.warn(`[Config] Failed reading ${p}: ${e.message}`);
      }
    }
  }
  return env;
}

const fileEnv = loadEnvFile();

const CONFIG = {
  WEB_PORT: parseInt(process.env.WEB_PORT || fileEnv.WEB_PORT || 3000, 10),
  WEB_ADMIN_USER: process.env.WEB_ADMIN_USER || fileEnv.WEB_ADMIN_USER || 'admin',
  WEB_ADMIN_PASS: process.env.WEB_ADMIN_PASS || fileEnv.WEB_ADMIN_PASS || fileEnv.RCON_PASS || 'admin123',
  RCON_HOST: process.env.HOST_IP || fileEnv.HOST_IP || '127.0.0.1',
  RCON_PORT: parseInt(process.env.PORT || fileEnv.PORT || 27015, 10),
  RCON_PASS: process.env.RCON_PASS || fileEnv.RCON_PASS || 'ChangeMe123!',
  SERVER_NAME: process.env.SERVER_NAME || fileEnv.SERVER_NAME || 'Counter-Strike 2 Server',
  SERVICE_NAME: (process.env.SERVICE_NAME || fileEnv.SERVICE_NAME || 'cs2-ds').replace(/[^a-zA-Z0-9_\-\.]/g, '')
};

// Check for insecure default credentials
const isDefaultPass = ['admin123', 'ChangeMe123!', '123456', 'password'].includes(CONFIG.WEB_ADMIN_PASS);
if (isDefaultPass) {
  console.warn('\n⚠️ [SECURITY WARNING] Default/weak admin password detected!');
  console.warn('⚠️ Please change WEB_ADMIN_PASS in your .update.env file to protect your server.\n');
}

// ---------- SECURITY HELPERS ----------

/**
 * Constant-time string comparison using SHA-256 hashes to prevent timing attacks.
 */
function timingSafeCompare(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const hashA = crypto.createHash('sha256').update(a).digest();
  const hashB = crypto.createHash('sha256').update(b).digest();
  return crypto.timingSafeEqual(hashA, hashB);
}

/**
 * Sanitize RCON command to prevent control character injection and buffer overflows.
 */
function sanitizeRconCommand(cmd) {
  if (!cmd || typeof cmd !== 'string') return '';
  // Max command length limit to avoid buffer attacks
  const trimmed = cmd.trim().slice(0, 512);
  // Strip null bytes and non-printable control characters
  return trimmed.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '');
}

/**
 * Brute force and rate limit tracking per IP
 */
const loginRateLimiter = new Map(); // ip -> { failedCount, lockedUntil }
const MAX_FAILED_ATTEMPTS = 5;
const LOCKOUT_DURATION_MS = 15 * 60 * 1000; // 15 minutes lockout

function getClientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (forwarded) {
    return forwarded.split(',')[0].trim();
  }
  return req.socket.remoteAddress || '127.0.0.1';
}

function checkRateLimit(ip) {
  const record = loginRateLimiter.get(ip);
  if (!record) return { allowed: true };

  if (record.lockedUntil && Date.now() < record.lockedUntil) {
    const remainingSec = Math.ceil((record.lockedUntil - Date.now()) / 1000);
    return { allowed: false, remainingSec };
  }

  if (record.lockedUntil && Date.now() >= record.lockedUntil) {
    loginRateLimiter.delete(ip);
    return { allowed: true };
  }

  return { allowed: true };
}

function recordFailedLogin(ip) {
  const record = loginRateLimiter.get(ip) || { failedCount: 0, lockedUntil: 0 };
  record.failedCount += 1;
  if (record.failedCount >= MAX_FAILED_ATTEMPTS) {
    record.lockedUntil = Date.now() + LOCKOUT_DURATION_MS;
    console.warn(`[Security] IP ${ip} locked out for 15 minutes due to repeated failed login attempts.`);
  }
  loginRateLimiter.set(ip, record);
}

function resetRateLimit(ip) {
  loginRateLimiter.delete(ip);
}

// Clean up stale rate limit entries every 30 minutes
setInterval(() => {
  const now = Date.now();
  for (const [ip, record] of loginRateLimiter.entries()) {
    if (record.lockedUntil && now > record.lockedUntil) {
      loginRateLimiter.delete(ip);
    }
  }
}, 1800000);

// ---------- IN-MEMORY SESSION STORE ----------
const activeSessions = new Map(); // token -> { username, expiresAt, ip }
const SESSION_TTL = 24 * 60 * 60 * 1000; // 24 hours

function generateToken(username, ip) {
  const token = crypto.randomBytes(32).toString('hex');
  activeSessions.set(token, {
    username,
    ip,
    expiresAt: Date.now() + SESSION_TTL
  });
  return token;
}

function validateToken(token) {
  if (!token) return false;
  const session = activeSessions.get(token);
  if (!session) return false;
  if (Date.now() > session.expiresAt) {
    activeSessions.delete(token);
    return false;
  }
  return session;
}

// Clean up expired sessions every hour
setInterval(() => {
  const now = Date.now();
  for (const [token, session] of activeSessions.entries()) {
    if (now > session.expiresAt) {
      activeSessions.delete(token);
    }
  }
}, 3600000);

// ---------- EXPRESS APP SETUP ----------
const app = express();

// Disable information disclosure headers
app.disable('x-powered-by');

// Security HTTP Headers (Helmet style)
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-XSS-Protection', '1; mode=block');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader(
    'Content-Security-Policy',
    "default-src 'self'; script-src 'self'; style-src 'self' https://fonts.googleapis.com 'unsafe-inline'; font-src 'self' https://fonts.gstatic.com; connect-src 'self' ws: wss:; img-src 'self' data:;"
  );
  next();
});

// JSON body parser with size limit to prevent body-flooding
app.use(express.json({ limit: '64kb' }));
app.use(express.static(path.join(__dirname, 'public')));

// Auth middleware
function requireAuth(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.startsWith('Bearer ') ? authHeader.slice(7) : req.query.token;
  const session = validateToken(token);
  if (!session) {
    return res.status(401).json({ error: 'نشست شما منقضی شده یا نامعتبر است. لطفاً مجدداً وارد شوید.' });
  }
  req.user = session;
  next();
}

// ---------- API ROUTES ----------

// Login with Brute Force Protection & Timing Safe Comparison
app.post('/api/login', (req, res) => {
  const clientIp = getClientIp(req);

  // Check rate limit
  const rateLimitStatus = checkRateLimit(clientIp);
  if (!rateLimitStatus.allowed) {
    return res.status(429).json({
      error: `تعداد تلاش‌های ناموفق بیش از حد مجاز بود. لطفاً ${rateLimitStatus.remainingSec} ثانیه دیگر دوباره تلاش کنید.`
    });
  }

  const { username, password } = req.body;
  if (!username || !password || typeof username !== 'string' || typeof password !== 'string') {
    return res.status(400).json({ error: 'نام کاربری و رمز عبور الزامی است.' });
  }

  const isUserMatch = timingSafeCompare(username, CONFIG.WEB_ADMIN_USER);
  const isPassMatch = timingSafeCompare(password, CONFIG.WEB_ADMIN_PASS);

  if (isUserMatch && isPassMatch) {
    resetRateLimit(clientIp);
    const token = generateToken(username, clientIp);
    return res.json({
      success: true,
      token,
      username,
      serverName: CONFIG.SERVER_NAME,
      host: CONFIG.RCON_HOST,
      port: CONFIG.RCON_PORT,
      defaultPasswordInUse: isDefaultPass
    });
  }

  recordFailedLogin(clientIp);
  return res.status(401).json({ error: 'نام کاربری یا رمز عبور اشتباه است.' });
});

// Logout
app.post('/api/logout', requireAuth, (req, res) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.startsWith('Bearer ') ? authHeader.slice(7) : req.query.token;
  if (token) activeSessions.delete(token);
  res.json({ success: true });
});

// Current User & Server details
app.get('/api/me', requireAuth, (req, res) => {
  res.json({
    username: req.user.username,
    serverName: CONFIG.SERVER_NAME,
    host: CONFIG.RCON_HOST,
    port: CONFIG.RCON_PORT,
    serviceName: CONFIG.SERVICE_NAME,
    defaultPasswordInUse: isDefaultPass
  });
});

// System & Service Status (Safe exec without shell injection)
app.get('/api/status', requireAuth, async (req, res) => {
  const getServiceStatus = () => {
    return new Promise((resolve) => {
      execFile('systemctl', ['--user', 'is-active', CONFIG.SERVICE_NAME], (error, stdout) => {
        if (error) {
          return resolve(stdout ? stdout.trim() : 'inactive');
        }
        resolve(stdout.trim());
      });
    });
  };

  let serviceStatus = 'unknown';
  try {
    serviceStatus = await getServiceStatus();
  } catch {
    serviceStatus = 'unknown';
  }

  // Memory calculation
  const totalMem = (os.totalmem() / (1024 * 1024 * 1024)).toFixed(1);
  const freeMem = (os.freemem() / (1024 * 1024 * 1024)).toFixed(1);
  const usedMem = (totalMem - freeMem).toFixed(1);

  res.json({
    serverName: CONFIG.SERVER_NAME,
    host: CONFIG.RCON_HOST,
    port: CONFIG.RCON_PORT,
    service: serviceStatus,
    os: `${os.type()} ${os.release()}`,
    uptimeSec: os.uptime(),
    loadAvg: os.loadavg(),
    defaultPasswordInUse: isDefaultPass,
    memory: {
      totalGB: totalMem,
      freeGB: freeMem,
      usedGB: usedMem,
      percent: Math.round(((totalMem - freeMem) / totalMem) * 100)
    }
  });
});

// RCON execute endpoint with sanitized inputs
app.post('/api/rcon', requireAuth, async (req, res) => {
  const cleanCmd = sanitizeRconCommand(req.body.command);
  if (!cleanCmd) {
    return res.status(400).json({ error: 'دستور RCON معتبر وارد کنید.' });
  }

  try {
    const output = await executeRcon(CONFIG.RCON_HOST, CONFIG.RCON_PORT, CONFIG.RCON_PASS, cleanCmd);
    return res.json({
      success: true,
      command: cleanCmd,
      output: output || '(دستور ارسال شد، پاسخی بازگردانده نشد)'
    });
  } catch (err) {
    return res.status(500).json({
      success: false,
      command: cleanCmd,
      error: err.message || 'خطای اجرای RCON'
    });
  }
});

// Service control endpoint with whitelist validation & execFile
app.post('/api/service/:action', requireAuth, (req, res) => {
  const { action } = req.params;
  const ALLOWED_ACTIONS = ['start', 'stop', 'restart'];
  if (!ALLOWED_ACTIONS.includes(action)) {
    return res.status(400).json({ error: 'عملیات نامعتبر است. فقط start, stop یا restart مجاز است.' });
  }

  execFile('systemctl', ['--user', action, CONFIG.SERVICE_NAME], (error, stdout, stderr) => {
    if (error) {
      return res.status(500).json({
        success: false,
        error: stderr ? stderr.trim() : error.message
      });
    }
    res.json({
      success: true,
      message: `سرویس ${CONFIG.SERVICE_NAME} با موفقیت ${action} شد.`
    });
  });
});

// ---------- CREATE HTTP & WEBSOCKET SERVER ----------
const server = http.createServer(app);
const wss = new WebSocketServer({ noServer: true });

// WebSocket Upgrade with Origin Verification (CSWSH Protection) & Token Validation
server.on('upgrade', (request, socket, head) => {
  // 1. Cross-Site WebSocket Hijacking (CSWSH) Defense: Origin Verification
  const origin = request.headers['origin'];
  const host = request.headers['host'];
  if (origin && host) {
    try {
      const originUrl = new URL(origin);
      if (originUrl.host !== host) {
        console.warn(`[Security] Rejected WebSocket upgrade with mismatched origin: ${origin} !== ${host}`);
        socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
        socket.destroy();
        return;
      }
    } catch {
      socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
      socket.destroy();
      return;
    }
  }

  const parsedUrl = new URL(request.url, `http://${request.headers.host || 'localhost'}`);
  if (parsedUrl.pathname === '/ws') {
    const token = parsedUrl.searchParams.get('token');
    const session = validateToken(token);
    if (!session) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }

    wss.handleUpgrade(request, socket, head, (ws) => {
      ws.user = session;
      wss.emit('connection', ws, request);
    });
  } else {
    socket.destroy();
  }
});

wss.on('connection', (ws) => {
  let logProcess = null;
  let commandCount = 0;
  let lastCommandTime = Date.now();

  const send = (obj) => {
    if (ws.readyState === ws.OPEN) {
      ws.send(JSON.stringify(obj));
    }
  };

  send({ type: 'connected', message: 'اتصال ایمن زنده به سرور برقرار شد.' });

  ws.on('message', async (message) => {
    try {
      // WebSocket rate limiting: max 10 messages per second
      const now = Date.now();
      if (now - lastCommandTime < 1000) {
        commandCount++;
        if (commandCount > 10) {
          return send({
            type: 'rcon_output',
            output: '[Security Rate Limit] نرخ ارسال دستورات بیش از حد مجاز است. لطفاً کمی صبر کنید.',
            isError: true
          });
        }
      } else {
        commandCount = 1;
        lastCommandTime = now;
      }

      const data = JSON.parse(message);

      // Handle RCON command
      if (data.type === 'rcon') {
        const cmd = sanitizeRconCommand(data.command);
        if (!cmd) return;

        try {
          const output = await executeRcon(CONFIG.RCON_HOST, CONFIG.RCON_PORT, CONFIG.RCON_PASS, cmd);
          send({
            type: 'rcon_output',
            command: cmd,
            output: output || '(دستور ارسال شد، پاسخی بازگردانده نشد)'
          });
        } catch (err) {
          send({
            type: 'rcon_output',
            command: cmd,
            output: `[خطا]: ${err.message}`,
            isError: true
          });
        }
      }

      // Handle Live Logs stream with safe spawn arguments
      if (data.type === 'subscribe_logs') {
        if (logProcess) {
          try { logProcess.kill(); } catch {}
          logProcess = null;
        }

        execFile('which', ['journalctl'], (err) => {
          if (err) {
            send({
              type: 'log_line',
              line: '[System] ابزار journalctl در این سیستم‌عامل در دسترس نیست (محیط غیر لینوکسی یا بدون systemd).'
            });
            return;
          }

          logProcess = spawn('journalctl', ['--user', '-u', CONFIG.SERVICE_NAME, '-f', '-n', '50', '--no-tail']);

          logProcess.stdout.on('data', (chunk) => {
            const lines = chunk.toString('utf8').split('\n');
            for (const line of lines) {
              if (line.trim()) {
                send({ type: 'log_line', line });
              }
            }
          });

          logProcess.stderr.on('data', (chunk) => {
            const lines = chunk.toString('utf8').split('\n');
            for (const line of lines) {
              if (line.trim()) {
                send({ type: 'log_line', line: `[stderr] ${line}`, isError: true });
              }
            }
          });

          logProcess.on('close', () => {
            send({ type: 'log_line', line: '[System] جریان زنده لاگ متوقف شد.' });
          });
        });
      }

      // Unsubscribe logs
      if (data.type === 'unsubscribe_logs') {
        if (logProcess) {
          try { logProcess.kill(); } catch {}
          logProcess = null;
        }
      }

    } catch (e) {
      send({ type: 'error', message: 'پیام نامعتبر دریافت شد.' });
    }
  });

  ws.on('close', () => {
    if (logProcess) {
      try { logProcess.kill(); } catch {}
      logProcess = null;
    }
  });
});

// Start Server
server.listen(CONFIG.WEB_PORT, '0.0.0.0', () => {
  console.log(`====================================================`);
  console.log(`🛡️  CS2 Secure Web Admin Panel is running!`);
  console.log(`🌐 Local URL:   http://localhost:${CONFIG.WEB_PORT}`);
  console.log(`🌐 Server URL:  http://${CONFIG.RCON_HOST}:${CONFIG.WEB_PORT}`);
  console.log(`🔑 Admin User:  ${CONFIG.WEB_ADMIN_USER}`);
  console.log(`🎯 RCON Target: ${CONFIG.RCON_HOST}:${CONFIG.RCON_PORT}`);
  console.log(`====================================================`);
});
