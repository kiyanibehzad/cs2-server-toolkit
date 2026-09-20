const net = require('net');
const { execFile } = require('child_process');

const SERVERDATA_AUTH = 3;
const SERVERDATA_AUTH_RESPONSE = 2;
const SERVERDATA_EXECCOMMAND = 2;
const SERVERDATA_RESPONSE_VALUE = 0;

/**
 * Creates a Source RCON packet buffer.
 */
function createPacket(id, type, body) {
  const bodyBuf = Buffer.from(body, 'utf8');
  const size = 4 + 4 + bodyBuf.length + 2; // id (4) + type (4) + body + 2 null bytes
  const buf = Buffer.alloc(4 + size);
  
  buf.writeInt32LE(size, 0);
  buf.writeInt32LE(id, 4);
  buf.writeInt32LE(type, 8);
  bodyBuf.copy(buf, 12);
  buf.writeUInt8(0, 12 + bodyBuf.length);
  buf.writeUInt8(0, 13 + bodyBuf.length);
  return buf;
}

/**
 * Executes an RCON command using pure TCP Source RCON protocol.
 */
function executeRconNative(host, port, password, command, timeoutMs = 4000) {
  return new Promise((resolve, reject) => {
    let resolved = false;
    let authed = false;
    let responseText = '';
    const socket = new net.Socket();

    const cleanup = () => {
      socket.removeAllListeners();
      socket.destroy();
    };

    const timer = setTimeout(() => {
      if (!resolved) {
        resolved = true;
        cleanup();
        if (authed && responseText.length > 0) {
          resolve(responseText.trim());
        } else {
          reject(new Error(`RCON connection timed out after ${timeoutMs}ms`));
        }
      }
    }, timeoutMs);

    socket.connect(Number(port), host, () => {
      // Step 1: Send Auth packet
      const authPacket = createPacket(101, SERVERDATA_AUTH, password);
      socket.write(authPacket);
    });

    let buffer = Buffer.alloc(0);

    socket.on('data', (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);

      while (buffer.length >= 4) {
        const packetSize = buffer.readInt32LE(0);
        if (buffer.length < 4 + packetSize) {
          break; // wait for remaining packet
        }

        const id = buffer.readInt32LE(4);
        const type = buffer.readInt32LE(8);
        const bodyBuf = buffer.subarray(12, 4 + packetSize - 2);
        const body = bodyBuf.toString('utf8');

        buffer = buffer.subarray(4 + packetSize);

        if (type === SERVERDATA_AUTH_RESPONSE) {
          if (id === -1) {
            resolved = true;
            clearTimeout(timer);
            cleanup();
            return reject(new Error('RCON Authentication Failed (Invalid password)'));
          }
          authed = true;
          // Step 2: Send actual command
          const cmdPacket = createPacket(102, SERVERDATA_EXECCOMMAND, command);
          socket.write(cmdPacket);

          // In Source RCON, to know when response ends, we send an empty ping packet
          const pingPacket = createPacket(103, SERVERDATA_RESPONSE_VALUE, '');
          socket.write(pingPacket);
        } else if (authed) {
          if (id === 103) {
            // End of output signal
            resolved = true;
            clearTimeout(timer);
            cleanup();
            return resolve(responseText.trim());
          }
          if (id === 102 && type === SERVERDATA_RESPONSE_VALUE) {
            responseText += body;
          }
        }
      }
    });

    socket.on('error', (err) => {
      if (!resolved) {
        resolved = true;
        clearTimeout(timer);
        cleanup();
        reject(err);
      }
    });

    socket.on('close', () => {
      if (!resolved) {
        resolved = true;
        clearTimeout(timer);
        cleanup();
        if (authed) {
          resolve(responseText.trim());
        } else {
          reject(new Error('RCON Socket closed unexpectedly'));
        }
      }
    });
  });
}

/**
 * Fallback to mcrcon CLI if native fails or server requires mcrcon flags.
 */
function executeMcrcon(host, port, password, command) {
  return new Promise((resolve, reject) => {
    execFile('mcrcon', ['-H', host, '-P', String(port), '-p', password, command], (error, stdout, stderr) => {
      if (error) {
        return reject(new Error(stderr || error.message));
      }
      resolve((stdout || '').trim());
    });
  });
}

/**
 * Main execute function: tries native TCP first, falls back to mcrcon.
 */
async function executeRcon(host, port, password, command) {
  try {
    return await executeRconNative(host, port, password, command);
  } catch (err) {
    // If native TCP fails, try mcrcon CLI if available
    try {
      return await executeMcrcon(host, port, password, command);
    } catch {
      throw err; // throw original native error if mcrcon also fails
    }
  }
}

module.exports = {
  executeRcon
};
