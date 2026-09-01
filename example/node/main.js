// example/node/main.js
//
// Bundled into `rawfile/node/` and run by the embedded Node.js runtime inside
// the HarmonyOS app.  It serves a tiny JSON API on 127.0.0.1:3000 — the WebView
// reaches it with `fetch('http://127.0.0.1:3000/...')`.
//
// Files under the same directory are available via `require()` and `fs`, since
// the runtime unpacks `rawfile/node/**` into the app's writable filesDir.

const http = require('http');

const PORT = 3000;

const server = http.createServer((req, res) => {
  res.setHeader('Content-Type', 'application/json');
  if (req.url === '/api/hello') {
    res.end(JSON.stringify({ ok: true, platform: 'harmony', node: process.version, time: Date.now() }));
    return;
  }
  res.statusCode = 404;
  res.end(JSON.stringify({ error: 'not found' }));
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[demo] node backend listening on http://127.0.0.1:${PORT}`);
});
