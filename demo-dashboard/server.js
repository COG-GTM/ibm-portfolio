// Migration Parity Dashboard — tiny proxy + static file server (zero dependencies).
//
// Serves static/ and exposes:
//   POST /api/call    {method, path}  → runs the same request against BOTH portfolio
//                                       instances (DB2 + Postgres) and returns
//                                       {db2:{status,ms,body}, postgres:{status,ms,body}}
//   GET  /api/rows?owner=X            → raw rows from each database (docker exec db2 CLI / psql)
//
// Config via env: DB2_APP_URL (default http://localhost:9081), PG_APP_URL (default
// http://localhost:9082), APP_USER/APP_PASSWORD (default stock/trader), PORT (8090).
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');

const PORT = process.env.PORT || 8090;
const DB2_APP_URL = process.env.DB2_APP_URL || 'http://localhost:9081';
const PG_APP_URL = process.env.PG_APP_URL || 'http://localhost:9082';
const AUTH = 'Basic ' + Buffer.from(`${process.env.APP_USER || 'stock'}:${process.env.APP_PASSWORD || 'trader'}`).toString('base64');
const STATIC_DIR = path.join(__dirname, 'static');

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml' };

function callInstance(baseUrl, method, apiPath) {
  return new Promise((resolve) => {
    const started = process.hrtime.bigint();
    const req = http.request(baseUrl + apiPath, { method, headers: { Authorization: AUTH } }, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        const ms = Number(process.hrtime.bigint() - started) / 1e6;
        let body = null;
        try { body = data ? JSON.parse(data) : null; } catch { body = data; }
        resolve({ status: res.statusCode, ms: Math.round(ms * 10) / 10, body });
      });
    });
    req.on('error', (err) => resolve({ status: 0, ms: 0, body: { error: err.message } }));
    req.end();
  });
}

function dockerExec(args) {
  return new Promise((resolve) => {
    execFile('docker', args, { timeout: 30000 }, (err, stdout, stderr) => {
      resolve(err && !stdout ? `ERROR: ${stderr || err.message}` : stdout || '(0 rows)\n');
    });
  });
}

async function dbRows(owner) {
  const sql = `SELECT owner, total, accountID FROM Portfolio WHERE owner='${owner}'`;
  const sqlStock = `SELECT owner, symbol, shares, price, total, dateQuoted FROM Stock WHERE owner='${owner}'`;
  const [pgP, pgS, db2P, db2S] = await Promise.all([
    dockerExec(['exec', 'stocktrader-postgres', 'psql', '-U', 'db2inst1', '-d', 'trader', '-c', sql]),
    dockerExec(['exec', 'stocktrader-postgres', 'psql', '-U', 'db2inst1', '-d', 'trader', '-c', sqlStock]),
    dockerExec(['exec', 'stocktrader-db2', 'su', '-', 'db2inst1', '-c', `db2 connect to trader > /dev/null && db2 -x "${sql}" || true`]),
    dockerExec(['exec', 'stocktrader-db2', 'su', '-', 'db2inst1', '-c', `db2 connect to trader > /dev/null && db2 -x "${sqlStock}" || true`]),
  ]);
  return { db2: { portfolio: db2P, stock: db2S }, postgres: { portfolio: pgP, stock: pgS } };
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  try {
    if (req.method === 'POST' && url.pathname === '/api/call') {
      let raw = '';
      req.on('data', (c) => (raw += c));
      req.on('end', async () => {
        const { method, path: apiPath } = JSON.parse(raw);
        const [db2, postgres] = await Promise.all([
          callInstance(DB2_APP_URL, method, apiPath),
          callInstance(PG_APP_URL, method, apiPath),
        ]);
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify({ db2, postgres }));
      });
      return;
    }
    if (url.pathname === '/api/rows') {
      const owner = (url.searchParams.get('owner') || 'DemoTrader').replace(/[^A-Za-z0-9_]/g, '');
      const rows = await dbRows(owner);
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify(rows));
      return;
    }
    // static files
    let file = url.pathname === '/' ? '/index.html' : url.pathname;
    const full = path.join(STATIC_DIR, path.normalize(file));
    if (!full.startsWith(STATIC_DIR) || !fs.existsSync(full)) {
      res.statusCode = 404;
      res.end('not found');
      return;
    }
    res.setHeader('Content-Type', MIME[path.extname(full)] || 'text/plain');
    res.end(fs.readFileSync(full));
  } catch (err) {
    res.statusCode = 500;
    res.end(JSON.stringify({ error: err.message }));
  }
});

server.listen(PORT, () => {
  console.log(`Migration Parity Dashboard on http://localhost:${PORT}`);
  console.log(`  DB2 instance:      ${DB2_APP_URL}`);
  console.log(`  Postgres instance: ${PG_APP_URL}`);
});
