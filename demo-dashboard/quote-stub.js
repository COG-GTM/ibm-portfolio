// Deterministic stock-quote stub.
// Both portfolio instances (DB2 and Postgres) point STOCK_QUOTE_URL here so
// prices are pinned and identical, making side-by-side responses comparable.
'use strict';

const http = require('http');

const PORT = process.env.PORT || 9999;
const DATE = '2026-07-12';

const PRICES = {
  IBM: 285.5,
  AAPL: 212.25,
  MSFT: 448.1,
  GOOG: 189.75,
  KD: 34.6,
};

const server = http.createServer((req, res) => {
  const symbol = decodeURIComponent(req.url.replace(/^\//, '').split('?')[0]);
  res.setHeader('Content-Type', 'application/json');
  if (symbol === '') {
    const all = Object.entries(PRICES).map(([s, p]) => quote(s, p));
    res.end(JSON.stringify(all));
    return;
  }
  const price = PRICES[symbol.toUpperCase()] ?? 123.45; // any unknown symbol gets a pinned fallback price
  res.end(JSON.stringify(quote(symbol.toUpperCase(), price)));
});

function quote(symbol, price) {
  return { symbol, price, date: DATE, time: 0 };
}

server.listen(PORT, () => console.log(`quote-stub listening on :${PORT} (pinned quotes, date=${DATE})`));
