#!/usr/bin/env python3
"""Tiny mock of the stock-quote microservice so the Portfolio app can price trades.

Serves GET /stock-quote/{symbol} with a slowly drifting pseudo-random price per symbol.
Run on the Docker network with the container name `stock-quote-service` (the hostname
the app's jvm.options points at):
  docker run -d --name stock-quote-service --network migration-net -v $PWD:/app \
      python:3.12-alpine python /app/mock_stock_quote.py
"""

import json
import random
import time
from datetime import date
from http.server import BaseHTTPRequestHandler, HTTPServer

BASE = {"IBM": 245.0, "AAPL": 210.0, "MSFT": 420.0, "GOOG": 175.0, "AMZN": 185.0,
        "NVDA": 950.0, "TSLA": 250.0, "META": 500.0, "ORCL": 140.0, "CRM": 270.0}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        symbol = self.path.rstrip("/").split("/")[-1].upper()
        base = BASE.get(symbol, 100.0)
        price = round(base * (1 + random.uniform(-0.02, 0.02)), 2)
        body = json.dumps({"symbol": symbol, "price": price,
                           "date": date.today().isoformat(),
                           "time": int(time.time() * 1000)}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 9080), Handler).serve_forever()
