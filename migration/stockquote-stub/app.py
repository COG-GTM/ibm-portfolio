"""Deterministic stock-quote stub used for the DB2/PostgreSQL parity verification.

Serves the same API shape as the real stock-quote microservice: GET /{symbol} returns
{"symbol", "price", "date", "time"}.  Prices and dates are fixed so both portfolio
instances see identical quotes and their responses can be diffed byte-for-byte.
"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

PRICES = {
    "IBM": 150.0,
    "MSFT": 400.0,
    "AAPL": 250.0,
    "NVDA": 3000.0,
}
DATE = "2026-07-13"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        symbol = self.path.strip("/").split("/")[-1].upper()
        quote = {
            "symbol": symbol,
            "price": PRICES.get(symbol, 100.0),
            "date": DATE,
            "time": 0,
        }
        body = json.dumps(quote).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
