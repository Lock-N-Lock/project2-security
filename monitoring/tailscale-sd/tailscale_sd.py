#!/usr/bin/env python3
# Tailscale API에서 노드를 찾아 Prometheus http_sd JSON으로 반환
#   /app-targets : tag:app 기기 (App ASG — 동적)
#   /db-targets  : hostname=lb-db 기기 (DB — 동적)
import os, json, urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

TS_API_KEY = os.environ["TS_API_KEY"]
TS_TAILNET = os.environ.get("TS_TAILNET", "-")
APP_TAG    = os.environ.get("APP_TAG", "tag:app")
APP_PORTS  = [p.strip() for p in os.environ.get("EXPORTER_PORTS", "9100,9113,8080").split(",")]
DB_HOST    = os.environ.get("DB_HOST", "lb-db")
DB_PORTS   = [p.strip() for p in os.environ.get("DB_PORTS", "9100,9187").split(",")]

def _devices():
    url = f"https://api.tailscale.com/api/v2/tailnet/{TS_TAILNET}/devices"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {TS_API_KEY}"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r).get("devices", [])

def _ipv4(d):
    return next((a for a in d.get("addresses", []) if ":" not in a), None)

def _targets(match, ports):
    out = []
    for d in _devices():
        if not match(d):
            continue
        ip = _ipv4(d)
        if not ip:
            continue
        out.append({
            "targets": [f"{ip}:{p}" for p in ports],
            "labels":  {"__meta_ts_hostname": d.get("hostname", "")},
        })
    return out

def app_targets():
    return _targets(lambda d: APP_TAG in (d.get("tags") or []), APP_PORTS)

def db_targets():
    return _targets(
        lambda d: d.get("hostname", "") == DB_HOST
                  or d.get("hostname", "").startswith(DB_HOST + "-"),
        DB_PORTS)

ROUTES = {"/app-targets": app_targets, "/db-targets": db_targets}

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        fn = ROUTES.get(self.path.rstrip("/"))
        if not fn:
            self.send_response(404); self.end_headers(); return
        try:
            body = json.dumps(fn()).encode()
            self.send_response(200); self.send_header("Content-Type", "application/json")
            self.end_headers(); self.wfile.write(body)
        except Exception as e:
            self.send_response(500); self.end_headers(); self.wfile.write(str(e).encode())
    def log_message(self, *a): pass

if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 9999), H).serve_forever()
