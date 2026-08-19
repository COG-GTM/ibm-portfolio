#!/usr/bin/env python3
"""Deterministic stand-in for the stock-quote microservice.

Both the DB2-backed and the PostgreSQL-backed portfolio instances call this stub, so any
difference the parity dashboard reports comes from the database layer and not from a
fluctuating market price.
"""

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PRICES = {
    "IBM": 500.0,
    "AAPL": 150.0,
    "MSFT": 400.0,
    "GOOG": 100.0,
    "AMZN": 200.0,
    "NVDA": 1000.0,
    "T": 20.0,
}
DEFAULT_PRICE = 250.0
QUOTE_DATE = "2026-01-02"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        symbol = self.path.strip("/").split("?")[0].upper()
        if symbol:
            body = {
                "symbol": symbol,
                "price": PRICES.get(symbol, DEFAULT_PRICE),
                "date": QUOTE_DATE,
                "time": 0,
            }
        else:
            body = [
                {"symbol": s, "price": p, "date": QUOTE_DATE, "time": 0}
                for s, p in sorted(PRICES.items())
            ]

        payload = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        print("stock-quote-stub " + fmt % args, flush=True)


if __name__ == "__main__":
    ThreadingHTTPServer(("", 9080), Handler).serve_forever()
