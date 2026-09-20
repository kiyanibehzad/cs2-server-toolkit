/**
 * CS2 Web Admin Panel - Client Application Logic
 */

let authToken = localStorage.getItem('cs2_panel_token') || '';
let ws = null;
let wsReconnectTimer = null;
let statusInterval = null;

// Command History for Terminal
const cmdHistory = [];
let historyIndex = -1;

// Elements
const loginModal = document.getElementById('login-modal');
const loginForm = document.getElementById('login-form');
const loginError = document.getElementById('login-error');
const appContainer = document.getElementById('app');
const logoutBtn = document.getElementById('logout-btn');

const terminalOutput = document.getElementById('terminal-output');
const rconForm = document.getElementById('rcon-form');
const rconInput = document.getElementById('rcon-input');
const clearConsoleBtn = document.getElementById('clear-console-btn');
const quickStatusBtn = document.getElementById('quick-status-btn');

const logsOutput = document.getElementById('logs-output');
const logsFilter = document.getElementById('logs-filter');
const autoScrollLogs = document.getElementById('auto-scroll-logs');
const clearLogsBtn = document.getElementById('clear-logs-btn');

const serviceBadge = document.getElementById('service-badge');
const serviceText = document.getElementById('service-text');
const navHostPort = document.getElementById('nav-host-port');
const navServerName = document.getElementById('nav-server-name');
const navUsername = document.getElementById('nav-username');

// ---------- TOAST NOTIFICATIONS ----------
function showToast(message, type = 'info', duration = 3500) {
  const container = document.getElementById('toast-container');
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  toast.textContent = message;
  container.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(15px)';
    toast.style.transition = 'all 0.3s ease';
    setTimeout(() => toast.remove(), 300);
  }, duration);
}

// ---------- TABS MANAGEMENT ----------
document.querySelectorAll('.tab-btn').forEach(button => {
  button.addEventListener('click', () => {
    document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
    document.querySelectorAll('.tab-pane').forEach(pane => pane.classList.remove('active'));

    button.classList.add('active');
    const targetTab = button.getAttribute('data-tab');
    const pane = document.getElementById(targetTab);
    if (pane) pane.classList.add('active');

    // Subscribe to logs if logs tab is selected
    if (targetTab === 'tab-logs') {
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: 'subscribe_logs' }));
      }
    }
  });
});

// ---------- AUTHENTICATION ----------
async function checkAuth() {
  if (!authToken) {
    showLoginModal();
    return;
  }

  try {
    const res = await fetch('/api/me', {
      headers: { 'Authorization': `Bearer ${authToken}` }
    });
    if (res.ok) {
      const data = await res.json();
      setupApp(data);
    } else {
      logout();
    }
  } catch (err) {
    console.error('Auth verification error:', err);
    showLoginModal();
  }
}

function showLoginModal() {
  loginModal.classList.remove('hidden');
  appContainer.classList.add('hidden');
  if (statusInterval) clearInterval(statusInterval);
  if (ws) ws.close();
}

function setupApp(userData) {
  loginModal.classList.add('hidden');
  appContainer.classList.remove('hidden');

  navUsername.textContent = userData.username;
  navServerName.textContent = userData.serverName;
  navHostPort.textContent = `${userData.host}:${userData.port}`;

  const secAlert = document.getElementById('security-alert');
  if (secAlert) {
    if (userData.defaultPasswordInUse) {
      secAlert.classList.remove('hidden');
    } else {
      secAlert.classList.add('hidden');
    }
  }

  initWebSocket();
  fetchStatus();
  statusInterval = setInterval(fetchStatus, 5000);
}

loginForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  loginError.classList.add('hidden');
  const user = document.getElementById('username').value.trim();
  const pass = document.getElementById('password').value;

  try {
    const res = await fetch('/api/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: user, password: pass })
    });

    const data = await res.json();
    if (res.ok && data.token) {
      authToken = data.token;
      localStorage.setItem('cs2_panel_token', authToken);
      setupApp(data);
      showToast('با موفقیت وارد شدید', 'success');
    } else {
      loginError.textContent = data.error || 'خطا در ورود به پنل';
      loginError.classList.remove('hidden');
    }
  } catch (err) {
    loginError.textContent = 'ارتباط با سرور برقرار نشد.';
    loginError.classList.remove('hidden');
  }
});

function logout() {
  if (authToken) {
    fetch('/api/logout', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${authToken}` }
    }).catch(() => {});
  }
  authToken = '';
  localStorage.removeItem('cs2_panel_token');
  showLoginModal();
}

logoutBtn.addEventListener('click', logout);

// ---------- WEBSOCKET & REALTIME STREAMING ----------
function initWebSocket() {
  if (!authToken) return;
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) return;

  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const wsUrl = `${protocol}//${window.location.host}/ws?token=${encodeURIComponent(authToken)}`;

  ws = new WebSocket(wsUrl);

  ws.onopen = () => {
    appendTerminalEntry('[System] کانکشن زنده با سرور برقرار شد.', 'system');
    // If on logs tab, subscribe
    const activeTab = document.querySelector('.tab-btn.active');
    if (activeTab && activeTab.getAttribute('data-tab') === 'tab-logs') {
      ws.send(JSON.stringify({ type: 'subscribe_logs' }));
    }
  };

  ws.onmessage = (event) => {
    try {
      const msg = JSON.parse(event.data);

      if (msg.type === 'rcon_output') {
        if (msg.isError) {
          appendTerminalEntry(msg.output, 'error');
        } else {
          appendTerminalEntry(msg.output, 'cmd-out');
        }
      } else if (msg.type === 'log_line') {
        appendLogEntry(msg.line, msg.isError);
      } else if (msg.type === 'connected') {
        // Welcome message
      }
    } catch (e) {
      console.error('WS Parse Error:', e);
    }
  };

  ws.onclose = () => {
    clearTimeout(wsReconnectTimer);
    wsReconnectTimer = setTimeout(() => {
      if (authToken) initWebSocket();
    }, 3000);
  };

  ws.onerror = (err) => {
    console.warn('WS Error:', err);
  };
}

// ---------- RCON TERMINAL LOGIC ----------
function appendTerminalEntry(text, type = 'cmd-out') {
  const entry = document.createElement('div');
  entry.className = `log-entry ${type}`;
  entry.textContent = text;
  terminalOutput.appendChild(entry);
  terminalOutput.scrollTop = terminalOutput.scrollHeight;
}

function sendRconCommand(cmd) {
  if (!cmd || !cmd.trim()) return;
  const cleanCmd = cmd.trim();

  // Save to history
  if (cmdHistory[cmdHistory.length - 1] !== cleanCmd) {
    cmdHistory.push(cleanCmd);
  }
  historyIndex = cmdHistory.length;

  appendTerminalEntry(`> ${cleanCmd}`, 'cmd-in');

  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'rcon', command: cleanCmd }));
  } else {
    // Fallback to HTTP POST
    fetch('/api/rcon', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${authToken}`
      },
      body: JSON.stringify({ command: cleanCmd })
    })
      .then(res => res.json())
      .then(data => {
        if (data.success) {
          appendTerminalEntry(data.output, 'cmd-out');
        } else {
          appendTerminalEntry(`[Error]: ${data.error}`, 'error');
        }
      })
      .catch(err => {
        appendTerminalEntry(`[Network Error]: ${err.message}`, 'error');
      });
  }
}

rconForm.addEventListener('submit', (e) => {
  e.preventDefault();
  const cmd = rconInput.value;
  rconInput.value = '';
  sendRconCommand(cmd);
});

// Arrow Up / Down history navigation
rconInput.addEventListener('keydown', (e) => {
  if (e.key === 'ArrowUp') {
    e.preventDefault();
    if (historyIndex > 0) {
      historyIndex--;
      rconInput.value = cmdHistory[historyIndex] || '';
    }
  } else if (e.key === 'ArrowDown') {
    e.preventDefault();
    if (historyIndex < cmdHistory.length - 1) {
      historyIndex++;
      rconInput.value = cmdHistory[historyIndex] || '';
    } else {
      historyIndex = cmdHistory.length;
      rconInput.value = '';
    }
  }
});

clearConsoleBtn.addEventListener('click', () => {
  terminalOutput.innerHTML = '';
  appendTerminalEntry('[System] کنسول پاکسازی شد.', 'system');
});

quickStatusBtn.addEventListener('click', () => {
  sendRconCommand('status');
});

// ---------- LIVE LOGS LOGIC ----------
function appendLogEntry(line, isError = false) {
  const filterText = logsFilter.value.trim().toLowerCase();
  const entry = document.createElement('div');
  entry.className = `log-entry ${isError ? 'error' : 'cmd-out'}`;
  entry.textContent = line;

  if (filterText && !line.toLowerCase().includes(filterText)) {
    entry.style.display = 'none';
  }

  logsOutput.appendChild(entry);

  // Keep max 500 lines in DOM to avoid memory leak
  if (logsOutput.children.length > 500) {
    logsOutput.removeChild(logsOutput.firstChild);
  }

  if (autoScrollLogs.checked) {
    logsOutput.scrollTop = logsOutput.scrollHeight;
  }
}

logsFilter.addEventListener('input', () => {
  const filterText = logsFilter.value.trim().toLowerCase();
  Array.from(logsOutput.children).forEach(child => {
    if (!filterText || child.textContent.toLowerCase().includes(filterText)) {
      child.style.display = '';
    } else {
      child.style.display = 'none';
    }
  });
});

clearLogsBtn.addEventListener('click', () => {
  logsOutput.innerHTML = '';
  appendLogEntry('[System] صفحه لاگ‌ها پاکسازی شد.');
});

// ---------- QUICK ACTIONS & MAPS DELEGATION ----------
document.addEventListener('click', (e) => {
  const rconBtn = e.target.closest('[data-rcon]');
  if (rconBtn) {
    const cmd = rconBtn.getAttribute('data-rcon');
    sendRconCommand(cmd);
    showToast(`دستور ارسال شد: ${cmd}`, 'info', 2000);
    return;
  }

  const serviceBtn = e.target.closest('[data-service]');
  if (serviceBtn) {
    const action = serviceBtn.getAttribute('data-service');
    executeServiceAction(action);
  }
});

// ---------- SERVICE CONTROLS & STATUS ----------
async function executeServiceAction(action) {
  try {
    showToast(`در حال ${action} کردن سرویس...`, 'info', 2500);
    const res = await fetch(`/api/service/${action}`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${authToken}` }
    });
    const data = await res.json();
    if (res.ok && data.success) {
      showToast(data.message, 'success');
      setTimeout(fetchStatus, 1500);
    } else {
      showToast(data.error || 'خطا در عملیات سرویس', 'error');
    }
  } catch (err) {
    showToast(`خطای شبکه: ${err.message}`, 'error');
  }
}

async function fetchStatus() {
  if (!authToken) return;

  try {
    const res = await fetch('/api/status', {
      headers: { 'Authorization': `Bearer ${authToken}` }
    });
    if (!res.ok) return;

    const data = await res.json();

    // Update Service status badge
    const isActive = data.service === 'active';
    serviceBadge.className = `status-indicator ${isActive ? 'online' : 'offline'}`;
    serviceText.textContent = isActive ? 'سرویس فعال (Online)' : `سرویس ${data.service}`;

    const statService = document.getElementById('stat-service-status');
    if (statService) {
      statService.textContent = data.service;
      statService.style.color = isActive ? 'var(--green)' : 'var(--red)';
    }

    // Update RAM
    const statRam = document.getElementById('stat-ram-usage');
    const ramProg = document.getElementById('ram-progress');
    if (statRam && data.memory) {
      statRam.textContent = `${data.memory.usedGB} / ${data.memory.totalGB} GB (${data.memory.percent}%)`;
      if (ramProg) ramProg.style.width = `${data.memory.percent}%`;
    }

    // Host & Port
    const statHostPort = document.getElementById('stat-host-port');
    if (statHostPort) {
      statHostPort.textContent = `${data.host}:${data.port}`;
    }

    // Uptime
    const statUptime = document.getElementById('stat-uptime');
    const statOs = document.getElementById('stat-os');
    if (statUptime && data.uptimeSec) {
      const hours = Math.floor(data.uptimeSec / 3600);
      const mins = Math.floor((data.uptimeSec % 3600) / 60);
      statUptime.textContent = `${hours} ساعت و ${mins} دقیقه`;
    }
    if (statOs && data.os) {
      statOs.textContent = data.os;
    }

  } catch (e) {
    console.error('Status fetch error:', e);
  }
}

// Check auth on load
checkAuth();
