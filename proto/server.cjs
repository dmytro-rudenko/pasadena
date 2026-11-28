#!/usr/bin/env node
// Prototype server for the penny skill: serves a directory of HTML
// over loopback, records which option the user clicked, and reloads the tab
// when we write a new screen.
//
// Configuration is entirely by environment (start.sh sets it):
//   SDD_CONTENT_DIR  directory to serve            (required)
//   SDD_STATE_DIR    pid/log/key/port/events       (required)
//   SDD_HOST         bind address                  (default 127.0.0.1)
//   SDD_PORT         fixed port                    (default: reuse, else random)
//   SDD_IDLE_MS      shut down after this idle     (default 4h)
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const CONTENT_DIR = path.resolve(required('SDD_CONTENT_DIR'));
const STATE_DIR = path.resolve(required('SDD_STATE_DIR'));
const HOST = process.env.SDD_HOST || '127.0.0.1';
const IDLE_MS = Number(process.env.SDD_IDLE_MS || 4 * 60 * 60 * 1000);
const ASSET_DIR = __dirname;

function required(name) {
  const value = process.env[name];
  if (!value) {
    process.stdout.write(JSON.stringify({ error: `${name} is not set` }) + '\n');
    process.exit(1);
  }
  return value;
}

fs.mkdirSync(CONTENT_DIR, { recursive: true });
fs.mkdirSync(STATE_DIR, { recursive: true });

// ---------- session key ----------
// The prototype is reachable by any process that can open a loopback socket.
// The key is what separates the user's browser from everything else on the
// box; it rides the URL as ?key= and is mirrored into a cookie so that
// stylesheets, scripts and fetches carry it without us rewriting any HTML.
// Persisted so a restart keeps an already-open tab valid.
const NONCE_FILE = path.join(STATE_DIR, 'key');
const PORT_FILE = path.join(STATE_DIR, 'port');
const EVENTS_FILE = path.join(STATE_DIR, 'events');

const NONCE = readOrCreate(NONCE_FILE, () => crypto.randomBytes(18).toString('hex'));

function readOrCreate(file, make) {
  try {
    const value = fs.readFileSync(file, 'utf8').trim();
    if (value) return value;
  } catch { /* first run */ }
  const value = make();
  fs.writeFileSync(file, value + '\n', { mode: 0o600 });
  return value;
}

function preferredPort() {
  if (process.env.SDD_PORT) return Number(process.env.SDD_PORT);
  try {
    const port = Number(fs.readFileSync(PORT_FILE, 'utf8').trim());
    if (port >= 1024 && port <= 65535) return port;
  } catch { /* no previous run */ }
  return 0; // let the OS pick, then remember it
}

// timingSafeEqual throws on a length mismatch, which itself leaks length —
// hash both sides first so the comparison is always over 32 equal bytes.
function sameSecret(left, right) {
  if (typeof left !== 'string' || typeof right !== 'string') return false;
  const leftHash = crypto.createHash('sha256').update(left).digest();
  const rightHash = crypto.createHash('sha256').update(right).digest();
  return crypto.timingSafeEqual(leftHash, rightHash);
}

function cookieKey(header) {
  for (const part of (header || '').split(';')) {
    const [name, ...rest] = part.trim().split('=');
    if (name === 'sdd_key') return decodeURIComponent(rest.join('='));
  }
  return null;
}

// ---------- content ----------
const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.woff2': 'font/woff2',
  '.ico': 'image/x-icon',
};

// Bounded so a stray node_modules inside the content dir cannot stall a poll.
function walk(dir, out = [], budget = { n: 2000 }) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const entry of entries) {
    if (budget.n-- <= 0) return out;
    if (entry.name.startsWith('.')) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out, budget);
    else if (entry.isFile()) out.push(full);
  }
  return out;
}

function contentStamp() {
  let newest = 0;
  for (const file of walk(CONTENT_DIR)) {
    const modified = fs.statSync(file).mtimeMs;
    if (modified > newest) newest = modified;
  }
  return Math.round(newest);
}

// `/` is always the newest screen. That is what lets us write a new file and
// have the user's open tab land on it — the poll sees the stamp move, the tab
// reloads `/`, and `/` is now the new screen. An explicit path is never
// redirected: a live prototype the user is clicking through must stay put.
function newestHtml() {
  let best = null;
  let bestTime = -1;
  for (const file of walk(CONTENT_DIR)) {
    if (path.extname(file) !== '.html') continue;
    const modified = fs.statSync(file).mtimeMs;
    if (modified > bestTime) { bestTime = modified; best = file; }
  }
  return best;
}

function resolveInContent(urlPath) {
  const rel = decodeURIComponent(urlPath).replace(/^\/+/, '');
  const full = path.resolve(CONTENT_DIR, rel);
  if (full !== CONTENT_DIR && !full.startsWith(CONTENT_DIR + path.sep)) return null;
  try {
    if (fs.statSync(full).isDirectory()) {
      const index = path.join(full, 'index.html');
      return fs.existsSync(index) ? index : null;
    }
    return full;
  } catch {
    return null;
  }
}

// ---------- responses ----------
function headers(type, extra = {}) {
  return {
    'content-type': type,
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    // The prototype is ours and loopback-only; framing it elsewhere is a
    // clickjacking surface for zero benefit.
    'x-frame-options': 'DENY',
    ...extra,
  };
}

function send(response, code, type, body, extra) {
  response.writeHead(code, headers(type, extra));
  response.end(body);
}

function sendFile(response, file, extra) {
  const type = TYPES[path.extname(file)] || 'application/octet-stream';
  let body;
  try {
    body = fs.readFileSync(file);
  } catch {
    return send(response, 404, 'text/plain; charset=utf-8', 'not found');
  }
  // Every served page gets the client: click capture and the reload poll.
  if (type.startsWith('text/html')) {
    body = body.toString('utf8').replace(
      /<\/body>/i,
      '<script src="/_sdd/client.js"></script></body>'
    );
    if (!body.includes('/_sdd/client.js')) body += '\n<script src="/_sdd/client.js"></script>\n';
  }
  send(response, 200, type, body, extra);
}

// ---------- request handling ----------
let lastActivity = Date.now();

const server = http.createServer((request, response) => {
  lastActivity = Date.now();
  const url = new URL(request.url, 'http://localhost');
  const viaQuery = url.searchParams.get('key');
  const authorized = sameSecret(viaQuery, NONCE) || sameSecret(cookieKey(request.headers.cookie), NONCE);

  if (!authorized) return send(response, 403, 'text/plain; charset=utf-8', 'forbidden');

  // Hand the key to the browser once so subresources and fetches carry it.
  const setCookie = viaQuery
    ? { 'set-cookie': `sdd_key=${encodeURIComponent(NONCE)}; Path=/; SameSite=Strict; HttpOnly` }
    : {};

  if (url.pathname === '/_sdd/poll') {
    return send(response, 200, TYPES['.json'], JSON.stringify({ stamp: contentStamp() }), setCookie);
  }

  if (url.pathname === '/_sdd/event') {
    if (request.method !== 'POST') return send(response, 405, 'text/plain; charset=utf-8', 'POST only');
    let body = '';
    request.on('data', (chunk) => {
      body += chunk;
      if (body.length > 8192) request.destroy(); // a click record is never this big
    });
    request.on('end', () => {
      let payload;
      try {
        payload = JSON.parse(body);
      } catch {
        return send(response, 400, 'text/plain; charset=utf-8', 'bad json');
      }
      const line = JSON.stringify({ ...payload, ts: new Date().toISOString() });
      fs.appendFileSync(EVENTS_FILE, line + '\n');
      send(response, 200, TYPES['.json'], '{"ok":true}', setCookie);
    });
    return;
  }

  if (url.pathname === '/_sdd/client.js' || url.pathname === '/_sdd/frame.css') {
    return sendFile(response, path.join(ASSET_DIR, path.basename(url.pathname)), setCookie);
  }

  const file = url.pathname === '/' ? newestHtml() : resolveInContent(url.pathname);
  if (!file && url.pathname === '/favicon.ico') {
    // Otherwise every screen logs a 404, and the console is where we read the
    // prototype's own errors from.
    response.writeHead(204, headers('image/x-icon', setCookie));
    return response.end();
  }
  if (!file) {
    return send(
      response,
      404,
      'text/plain; charset=utf-8',
      url.pathname === '/' ? 'no screen written yet' : 'not found',
      setCookie
    );
  }
  sendFile(response, file, setCookie);
});

setInterval(() => {
  if (Date.now() - lastActivity > IDLE_MS) process.exit(0);
}, 60_000).unref();

// 'listening' rather than a listen() callback: the EADDRINUSE path below
// re-listens, and a callback passed to the first listen() would not fire again.
server.on('listening', () => {
  const { port } = server.address();
  fs.writeFileSync(PORT_FILE, port + '\n');
  process.stdout.write(
    JSON.stringify({
      type: 'server-started',
      url: `http://${HOST}:${port}/?key=${NONCE}`,
      port,
      content_dir: CONTENT_DIR,
      state_dir: STATE_DIR,
      events: EVENTS_FILE,
    }) + '\n'
  );
});

server.listen(preferredPort(), HOST);

server.on('error', (error) => {
  // A stale port file points at a port someone else took; forget it and retry.
  if (error.code === 'EADDRINUSE' && !process.env.SDD_PORT) {
    try { fs.unlinkSync(PORT_FILE); } catch { /* already gone */ }
    server.listen(0, HOST);
    return;
  }
  process.stdout.write(JSON.stringify({ error: String(error.message || error) }) + '\n');
  process.exit(1);
});
