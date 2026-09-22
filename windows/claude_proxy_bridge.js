#!/usr/bin/env node
/**
 * claude_proxy_bridge.js - Cross-platform Proxy Bridge for Claude Code (Windows / Node.js)
 * SOCKS5 upstream, Destination Bypass, Traffic Audit Logging & Fail-Closed security.
 * Part of Claude Code Proxy Toolkit
 *
 * Usage:
 *   node claude_proxy_bridge.js [SOCKS5_URL] [PORT]
 */

const http = require('http');
const net = require('net');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { URL } = require('url');

// Environment & paths
const HOME = os.homedir();
const CONFIG_DIR = path.join(HOME, '.config', 'claude-proxy');
const PROGRAMDATA_DIR = process.env.ProgramData ? path.join(process.env.ProgramData, 'claude-proxy') : 'C:\\ProgramData\\claude-proxy';
const CONFIG_CANDIDATES = [
    path.join(CONFIG_DIR, 'proxy.env'),
    path.join(PROGRAMDATA_DIR, 'proxy.env'),
    path.join(__dirname, 'proxy.env'),
    path.join(__dirname, '..', 'proxy.env')
];
const BYPASS_FILE = path.join(CONFIG_DIR, 'bypass.conf');
const LOCAL_BYPASS_FILE = path.join(__dirname, 'bypass.conf');
const PROGRAMDATA_BYPASS_FILE = path.join(PROGRAMDATA_DIR, 'bypass.conf');
const LOG_FILE = path.join(CONFIG_DIR, 'traffic.jsonl');

let PROXY_PORT = 19000;
let SOCKS5_URL = '';
let PROXY_MODE = 'anthropic_only';

// 1. Load config from proxy.env
function loadConfig() {
    for (const confPath of CONFIG_CANDIDATES) {
        if (fs.existsSync(confPath)) {
            try {
                const content = fs.readFileSync(confPath, 'utf8');
                for (let line of content.split('\n')) {
                    line = line.trim();
                    if (!line || line.startsWith('#') || !line.includes('=')) continue;
                    const eq = line.indexOf('=');
                    const k = line.substring(0, eq).trim();
                    const v = line.substring(eq + 1).trim().replace(/^["']|["']$/g, '');
                    if (k === 'PROXY_PORT') PROXY_PORT = parseInt(v, 10) || 19000;
                    else if (k === 'SOCKS5_URL') SOCKS5_URL = v;
                    else if (k === 'PROXY_MODE') PROXY_MODE = v;
                }
                if (SOCKS5_URL) break; // Successfully loaded SOCKS5_URL
            } catch (err) {
                console.error('[bridge] Warning reading config:', confPath, err.message);
            }
        }
    }
}

loadConfig();

// Command line overrides
if (process.argv[2] && !process.argv[2].startsWith('--')) {
    SOCKS5_URL = process.argv[2];
}
if (process.argv[3] && !isNaN(parseInt(process.argv[3], 10))) {
    PROXY_PORT = parseInt(process.argv[3], 10);
}

if (!SOCKS5_URL) {
    console.error('[bridge] Error: SOCKS5_URL is not set in config or command line arguments.');
    console.error('Usage: node claude_proxy_bridge.js "socks5://user:pass@host:port" [port]');
    process.exit(1);
}

// Parse SOCKS5 URL
let parsedSocks;
try {
    let urlStr = SOCKS5_URL;
    if (!urlStr.includes('://')) urlStr = 'socks5://' + urlStr;
    parsedSocks = new URL(urlStr);
} catch (e) {
    console.error('[bridge] Invalid SOCKS5 URL:', SOCKS5_URL);
    process.exit(1);
}

const SOCKS_HOST = parsedSocks.hostname;
const SOCKS_PORT = parseInt(parsedSocks.port, 10) || 1080;
const SOCKS_USER = decodeURIComponent(parsedSocks.username || '');
const SOCKS_PASS = decodeURIComponent(parsedSocks.password || '');

// 2. Load Bypass rules
let bypassRules = new Set();

function loadBypassRules() {
    const rules = new Set();
    const filesToRead = [LOCAL_BYPASS_FILE, BYPASS_FILE, PROGRAMDATA_BYPASS_FILE];
    for (const f of filesToRead) {
        if (fs.existsSync(f)) {
            try {
                const lines = fs.readFileSync(f, 'utf8').split('\n');
                for (let line of lines) {
                    line = line.trim().toLowerCase();
                    if (line && !line.startsWith('#')) {
                        rules.add(line);
                    }
                }
            } catch {}
        }
    }
    if (rules.size === 0) {
        [
            'localhost', '127.0.0.1', '::1', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16',
            'github.com', '*.github.com', 'raw.githubusercontent.com', 'objects.githubusercontent.com',
            'gitlab.com', '*.gitlab.com', 'bitbucket.org', '*.bitbucket.org',
            'npmjs.org', '*.npmjs.org', 'registry.npmjs.org', 'yarnpkg.com', '*.yarnpkg.com',
            'pypi.org', '*.pypi.org', 'pythonhosted.org', '*.pythonhosted.org',
            'crates.io', '*.crates.io', 'pkg.go.dev', 'proxy.golang.org',
            'docker.io', '*.docker.io', 'docker.com', '*.docker.com',
            '*.ru', '*.рф', '*.su'
        ].forEach(r => rules.add(r.toLowerCase()));
    }
    bypassRules = rules;
}

loadBypassRules();
setInterval(loadBypassRules, 15000); // Reload bypass rules every 15s

function isBypassed(host) {
    if (!host) return false;
    const target = host.toLowerCase().split(':')[0];

    for (const rule of bypassRules) {
        if (rule === target) return true;
        if (rule.startsWith('*.')) {
            const suffix = rule.substring(1); // e.g. .github.com
            if (target.endsWith(suffix) || target === rule.substring(2)) return true;
        } else if (rule.startsWith('.')) {
            if (target.endsWith(rule) || target === rule.substring(1)) return true;
        } else if (target.endsWith('.' + rule)) {
            return true;
        }
    }
    return false;
}

// 3. Traffic Logging
if (!fs.existsSync(CONFIG_DIR)) {
    try { fs.mkdirSync(CONFIG_DIR, { recursive: true }); } catch {}
}

function logTraffic(entry) {
    const line = JSON.stringify({
        ts: new Date().toISOString(),
        client_ip: entry.clientIp || '127.0.0.1',
        client_port: entry.clientPort || 0,
        app: entry.app || 'claude',
        method: entry.method || 'CONNECT',
        host: entry.host,
        port: entry.port,
        route: entry.route,
        status: entry.status,
        bytes_up: entry.bytesUp || 0,
        bytes_down: entry.bytesDown || 0,
        latency_ms: entry.latencyMs || 0
    }) + '\n';

    fs.appendFile(LOG_FILE, line, (err) => {
        if (err && err.code !== 'ENOENT') {
            // Ignore logging errors silently
        }
    });
}

// 4. SOCKS5 Connect Function
function connectSocks5(targetHost, targetPort, callback) {
    const socket = net.connect(SOCKS_PORT, SOCKS_HOST);
    let stage = 0; // 0: init, 1: auth, 2: connect
    let handshakeFinished = false;

    socket.setTimeout(15000, () => {
        socket.destroy(new Error('SOCKS5 connection timeout'));
    });

    socket.on('connect', () => {
        // Step 1: Greeting
        if (SOCKS_USER && SOCKS_PASS) {
            socket.write(Buffer.from([0x05, 0x02, 0x00, 0x02])); // Support NO_AUTH and USER/PASS
        } else {
            socket.write(Buffer.from([0x05, 0x01, 0x00])); // Support NO_AUTH
        }
    });

    socket.on('data', (chunk) => {
        if (handshakeFinished) return;

        if (stage === 0) {
            // Greeting response
            if (chunk.length < 2 || chunk[0] !== 0x05) {
                socket.destroy(new Error('Invalid SOCKS5 version in greeting response'));
                return;
            }
            const authMethod = chunk[1];
            if (authMethod === 0x00) {
                // No auth required, proceed to connect
                sendConnectRequest();
            } else if (authMethod === 0x02) {
                // Username/Password authentication
                stage = 1;
                const uBuf = Buffer.from(SOCKS_USER);
                const pBuf = Buffer.from(SOCKS_PASS);
                const authPacket = Buffer.concat([
                    Buffer.from([0x01, uBuf.length]),
                    uBuf,
                    Buffer.from([pBuf.length]),
                    pBuf
                ]);
                socket.write(authPacket);
            } else {
                socket.destroy(new Error(`Unsupported SOCKS5 auth method: ${authMethod}`));
            }
        } else if (stage === 1) {
            // Auth response
            if (chunk.length < 2 || chunk[1] !== 0x00) {
                socket.destroy(new Error('SOCKS5 authentication failed'));
                return;
            }
            sendConnectRequest();
        } else if (stage === 2) {
            // Connect response
            if (chunk.length < 4 || chunk[1] !== 0x00) {
                const repCode = chunk.length >= 2 ? chunk[1] : -1;
                socket.destroy(new Error(`SOCKS5 connect rejected, rep=${repCode}`));
                return;
            }
            // SOCKS5 tunnel established!
            handshakeFinished = true;
            socket.setTimeout(0);
            callback(null, socket);
        }
    });

    function sendConnectRequest() {
        stage = 2;
        const hostBuf = Buffer.from(targetHost);
        const portBuf = Buffer.alloc(2);
        portBuf.writeUInt16BE(targetPort, 0);

        // Address type 0x03 (Domain Name) -> DNS is resolved by the remote SOCKS5 proxy!
        const reqPacket = Buffer.concat([
            Buffer.from([0x05, 0x01, 0x00, 0x03, hostBuf.length]),
            hostBuf,
            portBuf
        ]);
        socket.write(reqPacket);
    }

    socket.on('error', (err) => {
        if (!handshakeFinished) {
            callback(err);
        }
    });
}

// 5. Create HTTP Server (handles CONNECT tunneling, regular HTTP and PAC serving)
const server = http.createServer((req, res) => {
    // Serve PAC (Proxy Auto-Configuration) file for Windows & Claude Desktop GUI
    if (req.url === '/proxy.pac' || req.url === '/pac') {
        res.writeHead(200, {
            'Content-Type': 'application/x-ns-proxy-autoconfig',
            'Cache-Control': 'no-cache'
        });
        const pac = `function FindProxyForURL(url, host) {
    // Only Anthropic and Claude domains route through local SOCKS5 bridge
    if (shExpMatch(host, "*.anthropic.com") ||
        shExpMatch(host, "anthropic.com") ||
        shExpMatch(host, "*.claude.ai") ||
        shExpMatch(host, "claude.ai") ||
        shExpMatch(host, "*.usefathom.com") ||
        shExpMatch(host, "*.statsig.com") ||
        shExpMatch(host, "*.growthbook.io") ||
        shExpMatch(host, "*.datadoghq.com")) {
        return "PROXY 127.0.0.1:${PROXY_PORT}; DIRECT";
    }
    // Everything else connects directly (no proxy overhead or interference)
    return "DIRECT";
}
`;
        res.end(pac);
        return;
    }

    // Plain HTTP proxy request
    const startTime = Date.now();
    let host = req.headers.host || '';
    let port = 80;
    if (host.includes(':')) {
        const parts = host.split(':');
        host = parts[0];
        port = parseInt(parts[1], 10) || 80;
    }

    const bypassed = isBypassed(host);
    const route = bypassed ? 'DIRECT' : 'SOCKS5';

    if (bypassed) {
        const proxyReq = http.request({
            host: host,
            port: port,
            path: req.url,
            method: req.method,
            headers: req.headers
        }, (proxyRes) => {
            res.writeHead(proxyRes.statusCode, proxyRes.headers);
            proxyRes.pipe(res);
            logTraffic({
                clientIp: req.socket.remoteAddress,
                clientPort: req.socket.remotePort,
                app: 'claude',
                method: req.method,
                host: host,
                port: port,
                route: route,
                status: proxyRes.statusCode,
                latencyMs: Date.now() - startTime
            });
        });

        proxyReq.on('error', (err) => {
            res.writeHead(502);
            res.end('Bad Gateway');
            logTraffic({
                clientIp: req.socket.remoteAddress,
                clientPort: req.socket.remotePort,
                app: 'claude',
                method: req.method,
                host: host,
                port: port,
                route: route,
                status: 502,
                latencyMs: Date.now() - startTime
            });
        });

        req.pipe(proxyReq);
    } else {
        // Forward HTTP via SOCKS5
        connectSocks5(host, port, (err, socksSocket) => {
            if (err) {
                res.writeHead(502);
                res.end('Bad Gateway: ' + err.message);
                logTraffic({
                    clientIp: req.socket.remoteAddress,
                    clientPort: req.socket.remotePort,
                    app: 'claude',
                    method: req.method,
                    host: host,
                    port: port,
                    route: route,
                    status: 502,
                    latencyMs: Date.now() - startTime
                });
                return;
            }

            // Write raw HTTP request to SOCKS5 socket
            socksSocket.write(`${req.method} ${req.url} HTTP/1.1\r\n`);
            for (const [key, val] of Object.entries(req.headers)) {
                socksSocket.write(`${key}: ${val}\r\n`);
            }
            socksSocket.write('\r\n');

            req.pipe(socksSocket);
            socksSocket.pipe(res.socket);
        });
    }
});

// Handle HTTPS CONNECT tunneling
server.on('connect', (req, clientSocket, head) => {
    const startTime = Date.now();
    const [targetHost, targetPortStr] = req.url.split(':');
    const targetPort = parseInt(targetPortStr, 10) || 443;

    const bypassed = isBypassed(targetHost);
    const route = bypassed ? 'DIRECT' : 'SOCKS5';

    let bytesUp = 0;
    let bytesDown = 0;
    let finished = false;

    function finishLog(status) {
        if (finished) return;
        finished = true;
        logTraffic({
            clientIp: clientSocket.remoteAddress,
            clientPort: clientSocket.remotePort,
            app: 'claude',
            method: 'CONNECT',
            host: targetHost,
            port: targetPort,
            route: route,
            status: status,
            bytesUp: bytesUp,
            bytesDown: bytesDown,
            latencyMs: Date.now() - startTime
        });
    }

    clientSocket.on('data', (d) => { bytesUp += d.length; });

    if (bypassed) {
        // Direct connection
        const upstreamSocket = net.connect(targetPort, targetHost, () => {
            clientSocket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
            if (head && head.length > 0) upstreamSocket.write(head);
            upstreamSocket.pipe(clientSocket);
            clientSocket.pipe(upstreamSocket);
            finishLog(200);
        });

        upstreamSocket.on('data', (d) => { bytesDown += d.length; });

        upstreamSocket.on('error', (err) => {
            if (!clientSocket.destroyed) {
                clientSocket.write('HTTP/1.1 502 Bad Gateway\r\n\r\n');
                clientSocket.end();
            }
            finishLog(502);
        });

        clientSocket.on('error', () => { upstreamSocket.destroy(); });
    } else {
        // Connect via SOCKS5
        connectSocks5(targetHost, targetPort, (err, socksSocket) => {
            if (err) {
                if (!clientSocket.destroyed) {
                    clientSocket.write('HTTP/1.1 502 Bad Gateway\r\n\r\n');
                    clientSocket.end();
                }
                finishLog(502);
                return;
            }

            clientSocket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
            if (head && head.length > 0) socksSocket.write(head);

            socksSocket.on('data', (d) => { bytesDown += d.length; });

            socksSocket.pipe(clientSocket);
            clientSocket.pipe(socksSocket);

            finishLog(200);

            socksSocket.on('error', () => { clientSocket.destroy(); });
            clientSocket.on('error', () => { socksSocket.destroy(); });
        });
    }
});

server.listen(PROXY_PORT, '127.0.0.1', () => {
    console.log(`[bridge] Claude Code Proxy Bridge running on http://127.0.0.1:${PROXY_PORT}`);
    console.log(`[bridge] Upstream SOCKS5: socks5://${SOCKS_HOST}:${SOCKS_PORT} (User: ${SOCKS_USER ? SOCKS_USER : 'none'})`);
    console.log(`[bridge] Active bypass rules: ${bypassRules.size} entries`);
    console.log(`[bridge] Audit log: ${LOG_FILE}`);
});

server.on('error', (err) => {
    console.error(`[bridge] Fatal server error:`, err.message);
    process.exit(1);
});
