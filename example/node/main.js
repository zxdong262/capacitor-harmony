// example/node/main.js
//
// Bundled into `rawfile/node/` and run by the embedded Node.js runtime inside
// the HarmonyOS app. It serves a tiny JSON API on 127.0.0.1:3000.
//
// IMPORTANT: the WebView cannot reach 127.0.0.1 directly — the web layer must
// use `Node.callApi` (native proxy), not `fetch('http://127.0.0.1:3000/...')`.
//
// Files under the same directory are available via `require()` and `fs`, since
// the runtime unpacks `rawfile/node/**` into the app's writable filesDir.

const http = require('http');

const PORT = Number(process.env.PORT || 3000);

function setCors(res, req) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') {
    res.statusCode = 204;
    res.end();
    return true;
  }
  return false;
}

function createServer() {
  const server = http.createServer((req, res) => {
    if (setCors(res, req)) return;
    res.setHeader('Content-Type', 'application/json');
    if (req.url === '/api/hello') {
      res.end(JSON.stringify({ ok: true, platform: 'harmony', node: process.version, time: Date.now() }));
      return;
    }
    res.statusCode = 404;
    res.end(JSON.stringify({ error: 'not found' }));
  });
  server.on('error', (err) => {
    console.error(`[demo] server error: ${err && err.code ? err.code : ''} ${err && err.message ? err.message : String(err)}`);
  });
  return server;
}

const HOSTS = ['127.0.0.1', 'localhost', '::1'];

function listen(index) {
  if (index >= HOSTS.length) {
    console.error(`[demo] could not bind any of ${HOSTS.join(', ')} on port ${PORT} — giving up`);
    return;
  }
  const host = HOSTS[index];
  const server = createServer();
  server.once('error', (err) => {
    console.error(`[demo] listen ${host}:${PORT} failed: ${err && err.code ? err.code : ''} ${err && err.message ? err.message : String(err)}`);
    try {
      server.close();
    } catch (e) {
      /* not listening */
    }
    setImmediate(() => listen(index + 1));
  });
  server.listen(PORT, host, () => {
    console.log(`[demo] node backend listening on http://${host}:${PORT}`);
  });
}

listen(0);
