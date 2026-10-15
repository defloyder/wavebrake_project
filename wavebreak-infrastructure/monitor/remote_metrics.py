"""Tiny stats + disk-cleanup server for a node the Istanbul monitor can't
reach by SSH on purpose — giving the monitor host SSH keys to every VPN
server would mean one compromised box pivots into all of them. Instead
this binds to the private tunnel address only (never 0.0.0.0); nothing it
serves needs auth because the tunnel itself is the access control, same
trust model as the existing ops WireGuard admin panel.

GET /metrics is read-only, as it always was. GET /cleanup/scan and POST
/cleanup/run (owner, 15.10) are the one deliberate exception to "read-
only" this file makes: still tunnel-bound only, but now able to act. That
stays safe under the same trust model (the tunnel is the access control)
because the action set is small and fixed — cleanup.py's scan()/run(),
never an arbitrary shell command — triggered only by the bot's own
explicit-confirmation flow (a human taps "✅ Подтвердить" in Telegram),
not automatically.

Deliberately dependency-free (stdlib only) and self-contained — it does not
import monitor.py (bot.py's /cleanup screen calls cleanup.py directly
instead, for the local/Istanbul case), so a change to the full monitor
package can never break this one unrelated service, and vice versa.
cleanup.py itself is imported since it's equally dependency-free.

Usage: remote_metrics.py <bind-ip> [port]
"""
import json
import os
import re
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

import cleanup


def run(cmd, timeout=5):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT, timeout=timeout)
    except Exception as e:
        return f"ERROR: {e}"


def load_snapshot():
    load = (run(["cat", "/proc/loadavg"]).split() + ["?"] * 3)[:3]
    cpus = os.cpu_count() or 1
    mem = {}
    for line in run(["cat", "/proc/meminfo"]).splitlines():
        k, _, v = line.partition(":")
        if v.strip().endswith("kB"):
            mem[k] = int(v.split()[0]) * 1024
    disk = run(["df", "-B1", "/"]).splitlines()
    d = re.split(r"\s+", disk[1]) if len(disk) > 1 else []
    uptime = float((run(["cat", "/proc/uptime"]).split() or ["0"])[0] or 0)
    return {
        "hostname": run(["hostname"]).strip(),
        "load": load, "cpus": cpus,
        "mem_total": mem.get("MemTotal", 0), "mem_avail": mem.get("MemAvailable", 0),
        "disk_total": int(d[1]) if len(d) > 3 else 0, "disk_used": int(d[2]) if len(d) > 3 else 0,
        "uptime": uptime,
    }


class Handler(BaseHTTPRequestHandler):
    def _json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/metrics":
            return self._json(200, load_snapshot())
        if self.path == "/cleanup/scan":
            return self._json(200, {"items": cleanup.scan()})
        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        if self.path != "/cleanup/run":
            self.send_response(404)
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            ids = json.loads(raw).get("ids") or []
        except Exception:
            return self._json(400, {"error": "bad request body"})
        self._json(200, cleanup.run(ids))

    def log_message(self, fmt, *args):
        pass  # the tunnel is the access log that matters; this would just be noise


if __name__ == "__main__":
    bind_ip = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8787
    HTTPServer((bind_ip, port), Handler).serve_forever()
