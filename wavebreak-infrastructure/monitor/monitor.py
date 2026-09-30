"""Host-side monitoring: xray/hysteria log tailing, health checks, per-client
traffic sampling from Xray's StatsService. Collectors return plain data; the
bot decides how to render it. Behaviour carried over from the original
single-file monitor (same thresholds, same SQLite history)."""
import collections
import json
import os
import re
import sqlite3
import subprocess
import threading
import time

EVENTS_LOG = "/var/log/wavebreak-monitor/events.log"
DB_FILE = "/var/lib/wavebreak-monitor/monitor.db"

XRAY_CONTAINER = "wavebreak-pilot-xray"
HY_CONTAINER = "wavebreak-pilot-hysteria"
# Hysteria2 is not published to users (2026-09-30), so it is not watched
# either: no health alerts, no log tailing, not on the status screens.
# MONITOR_HYSTERIA=1 in telegram.env brings all of it back.
HY_ENABLED = os.environ.get("MONITOR_HYSTERIA", "0") == "1"
STATS_API = "127.0.0.1:19999"

RECONNECT_THRESHOLD = 6
RECONNECT_WINDOW_SEC = 600
HEALTH_CHECK_INTERVAL_SEC = 30
TRAFFIC_SAMPLE_INTERVAL_SEC = 300

ACCEPT_RE = re.compile(r"accepted (tcp|udp).*email:\s*([\w-]+)")
# Hysteria logs one "client connected" per real QUIC session; Xray (VLESS
# over WS, no mux) logs one "accepted" per proxied flow, so only Hysteria
# lines are real reconnects. Counting Xray flows produced false alerts.
HY_CONNECT_RE = re.compile(r'client connected.*"id":\s*"([0-9a-fA-F]{8})')
CLOSE_RE = re.compile(r"connection ends|EOF|connection reset|failed to process", re.I)
UUID_RE = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

_lock = threading.Lock()
_client_events = collections.defaultdict(list)
started_at = time.time()


def log_event(msg):
    os.makedirs(os.path.dirname(EVENTS_LOG), exist_ok=True)
    with open(EVENTS_LOG, "a", encoding="utf-8") as f:
        f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} {msg}\n")


def run(cmd, timeout=15):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT, timeout=timeout)
    except Exception as e:
        return f"ERROR: {e}"


def mask_secrets(text):
    return UUID_RE.sub("****-****-****", text)


def db():
    os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)
    conn = sqlite3.connect(DB_FILE)
    conn.execute("CREATE TABLE IF NOT EXISTS traffic_deltas(ts INTEGER, client TEXT, up_delta INTEGER, down_delta INTEGER)")
    conn.execute("CREATE TABLE IF NOT EXISTS last_cumulative(client TEXT PRIMARY KEY, up INTEGER, down INTEGER)")
    return conn


# ---------- background loops ----------

def tail_container(name, transport, alert):
    while True:
        try:
            proc = subprocess.Popen(["docker", "logs", "-f", "--since", "0m", name],
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for line in proc.stdout:
                handle_line(transport, line.strip(), alert)
        except Exception as e:
            log_event(f"ERROR tail {name} crashed: {e}")
        log_event(f"WARN tail {name} exited, restarting in 5s")
        time.sleep(5)


def handle_line(transport, line, alert):
    m = ACCEPT_RE.search(line)
    if m:
        log_event(f"CONNECT client={m.group(2)} transport={transport} proto={m.group(1)}")
        return
    m = HY_CONNECT_RE.search(line)
    if m:
        client = "WVB-" + m.group(1).upper()
        log_event(f"SESSION client={client} transport={transport}")
        with _lock:
            now = time.time()
            events = _client_events[client]
            events.append(now)
            while events and events[0] < now - RECONNECT_WINDOW_SEC:
                events.pop(0)
            count = len(events)
        if count >= RECONNECT_THRESHOLD:
            alert("warn", f"Клиент {client}: {count} переподключений за {RECONNECT_WINDOW_SEC // 60} мин ({transport})",
                  key=f"reconnect_{client}")
        return
    if CLOSE_RE.search(line):
        log_event(f"DISCONNECT transport={transport} raw=\"{line[:200]}\"")


def container_running(name):
    try:
        out = subprocess.check_output(["docker", "inspect", "--format", "{{.State.Running}}", name],
                                      text=True, stderr=subprocess.DEVNULL).strip()
        return out == "true"
    except Exception:
        return False


def port_listening(port, proto="tcp"):
    try:
        out = subprocess.check_output(["ss", "-t" if proto == "tcp" else "-u", "-ln"], text=True)
        return f":{port} " in out or f":{port}\n" in out
    except Exception:
        return False


def health_check_loop(alert):
    checks = [
        ("xray", lambda: container_running(XRAY_CONTAINER), "Контейнер xray упал", "xray снова работает"),
        ("port443", lambda: port_listening(443, "tcp"), "Никто не слушает tcp/443 — REALITY/TLS недоступны", "tcp/443 снова слушается"),
    ]
    if HY_ENABLED:
        checks.insert(1, ("hysteria", lambda: container_running(HY_CONTAINER), "Контейнер hysteria упал", "hysteria снова работает"))
    last = {key: True for key, *_ in checks}
    while True:
        try:
            state = {}
            for key, probe, down_msg, up_msg in checks:
                ok = probe()
                state[key] = ok
                if not ok and last[key]:
                    alert("crit", down_msg, key=f"{key}_down", cooldown=300)
                    log_event(f"ALERT {key}_down")
                if ok and not last[key]:
                    alert("ok", up_msg, key=f"{key}_up", cooldown=60)
                    log_event(f"INFO {key}_recovered")
                last[key] = ok
            log_event("HEALTH " + " ".join(f"{k}={v}" for k, v in state.items())
                      + (f" udp443={port_listening(443, 'udp')}" if HY_ENABLED else ""))
        except Exception as e:
            log_event(f"ERROR health_check_loop: {e}")
        time.sleep(HEALTH_CHECK_INTERVAL_SEC)


def query_stats():
    out = run(["docker", "exec", XRAY_CONTAINER, "xray", "api", "statsquery", f"--server={STATS_API}", "-pattern", ""], timeout=10)
    try:
        data = json.loads(out)
    except Exception:
        return {}
    result = collections.defaultdict(lambda: {"up": 0, "down": 0})
    for stat in data.get("stat", []):
        m = re.match(r"user>>>(.+)>>>traffic>>>(uplink|downlink)", stat["name"])
        if m:
            result[m.group(1)]["up" if m.group(2) == "uplink" else "down"] = stat["value"]
    return result


def traffic_sample_loop():
    time.sleep(20)  # let the stats API warm up after service start
    while True:
        try:
            samples = query_stats()
            conn = db()
            now = int(time.time())
            for client, vals in samples.items():
                row = conn.execute("SELECT up, down FROM last_cumulative WHERE client=?", (client,)).fetchone()
                if row is None:
                    up_d, down_d = 0, 0
                else:
                    up_d = vals["up"] - row[0] if vals["up"] >= row[0] else vals["up"]
                    down_d = vals["down"] - row[1] if vals["down"] >= row[1] else vals["down"]
                conn.execute("INSERT INTO traffic_deltas VALUES (?,?,?,?)", (now, client, up_d, down_d))
                conn.execute("INSERT OR REPLACE INTO last_cumulative VALUES (?,?,?)", (client, vals["up"], vals["down"]))
            conn.commit()
            conn.close()
        except Exception as e:
            log_event(f"ERROR traffic_sample_loop: {e}")
        time.sleep(TRAFFIC_SAMPLE_INTERVAL_SEC)


# ---------- snapshots for the bot ----------

def _inspect(name, fmt):
    return run(["docker", "inspect", "--format", fmt, name], timeout=5).strip()


def status_snapshot():
    cores = []
    watched = [("xray", XRAY_CONTAINER)] + ([("hysteria", HY_CONTAINER)] if HY_ENABLED else [])
    for label, name in watched:
        up = container_running(name)
        cores.append({
            "name": label, "up": up,
            "restarts": _inspect(name, "{{.RestartCount}}") if up else "—",
            "started": _inspect(name, "{{.State.StartedAt}}")[:19].replace("T", " ") if up else "—",
        })
    version = "n/a"
    if cores[0]["up"]:
        version = (run(["docker", "exec", XRAY_CONTAINER, "xray", "version"]).splitlines() or ["n/a"])[0][:40]
    return {"cores": cores, "tcp443": port_listening(443, "tcp"),
            "udp443": port_listening(443, "udp") if HY_ENABLED else None,
            "udp51820": port_listening(51820, "udp"), "xray_version": version}


def services_snapshot():
    out = run(["docker", "ps", "-a", "--format", "{{.Names}}\t{{.Status}}"], timeout=10)
    rows = []
    for line in out.splitlines():
        if "\t" not in line:
            continue
        name, status = line.split("\t", 1)
        if not name.startswith(("wavebreak", "wavebreak_pilot")) or "migrate" in name:
            continue
        short = name.replace("wavebreak_pilot-", "").replace("wavebreak-pilot-", "").removesuffix("-1")
        healthy = status.startswith("Up") and "unhealthy" not in status
        rows.append({"name": short, "ok": healthy, "status": status})
    return sorted(rows, key=lambda r: (r["ok"], r["name"]))


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
    est = run(["ss", "-tn", "state", "established"]).strip().splitlines()
    uptime = float((run(["cat", "/proc/uptime"]).split() or ["0"])[0] or 0)
    return {
        "load": load, "cpus": cpus,
        "mem_total": mem.get("MemTotal", 0), "mem_avail": mem.get("MemAvailable", 0),
        "swap_total": mem.get("SwapTotal", 0), "swap_free": mem.get("SwapFree", 0),
        "disk_total": int(d[1]) if len(d) > 3 else 0, "disk_used": int(d[2]) if len(d) > 3 else 0,
        "connections": max(0, len(est) - 1), "uptime": uptime,
    }


def xray_clients():
    out = run(["docker", "exec", XRAY_CONTAINER, "cat", "/etc/xray/config.json"], timeout=10)
    try:
        cfg = json.loads(out)
    except Exception:
        return []
    emails = set()
    for inbound in cfg.get("inbounds", []):
        for c in (inbound.get("settings", {}) or {}).get("clients", []) or []:
            if c.get("email"):
                emails.add(c["email"])
    return sorted(emails)


def traffic_snapshot():
    conn = db()
    now = int(time.time())
    rows = []
    for client in xray_clients():
        row = {"client": client}
        for wname, wsec in (("day", 86400), ("week", 7 * 86400), ("month", 30 * 86400)):
            up, down = conn.execute(
                "SELECT COALESCE(SUM(up_delta),0), COALESCE(SUM(down_delta),0) FROM traffic_deltas WHERE client=? AND ts>=?",
                (client, now - wsec)).fetchone()
            row[wname] = (up, down)
        rows.append(row)
    first_ts = conn.execute("SELECT MIN(ts) FROM traffic_deltas").fetchone()[0]
    conn.close()
    rows.sort(key=lambda r: -(r["day"][0] + r["day"][1]))
    return {"rows": rows, "history_hours": (now - first_ts) / 3600 if first_ts else 0}


def _read_events():
    try:
        with open(EVENTS_LOG, encoding="utf-8", errors="replace") as f:
            return f.readlines()
    except FileNotFoundError:
        return []


def _line_ts(line):
    try:
        return time.mktime(time.strptime(line.split(" ")[0], "%Y-%m-%dT%H:%M:%S"))
    except Exception:
        return None


def clients_snapshot():
    now = time.time()
    lines = [l for l in _read_events() if " CONNECT client=" in l]
    rows = []
    for client in xray_clients():
        mine = [l for l in lines if f"CONNECT client={client} " in l]
        last = _line_ts(mine[-1]) if mine else None
        with _lock:
            events = list(_client_events.get(client, []))
        if events and (last is None or events[-1] > last):
            last = events[-1]
        rows.append({
            "client": client,
            # Heuristic: any xray flow or hysteria session in the last ~10 min.
            "online": bool(last and now - last < TRAFFIC_SAMPLE_INTERVAL_SEC * 2),
            "last": last,
            "reconnects_1h": sum(1 for t in events if now - t <= 3600),
            "flows_24h": sum(1 for l in mine if (_line_ts(l) or 0) >= now - 86400),
        })
    rows.sort(key=lambda r: (not r["online"], -(r["last"] or 0)))
    return rows


def online_count():
    return sum(1 for r in clients_snapshot() if r["online"])


def reconnect_events(client=None, limit=20):
    out = []
    for l in _read_events():
        if "CONNECT" in l and "DISCONNECT" not in l and (client is None or f"client={client} " in l):
            out.append(l.strip())
    return out[-limit:]


def error_groups(since="60m", limit=25):
    text = run(["docker", "logs", "--since", since, XRAY_CONTAINER])
    if HY_ENABLED:
        text += run(["docker", "logs", "--since", since, HY_CONTAINER])
    groups = collections.Counter()
    for l in text.splitlines():
        if re.search(r"error|warn|fail", l, re.I):
            groups[re.sub(r"[0-9a-fA-F.:]{6,}", "<addr>", l)[:90]] += 1
    return [(n, mask_secrets(p)) for p, n in groups.most_common(limit)]


def xray_logs(n=30):
    return mask_secrets(run(["docker", "logs", "--tail", str(n), XRAY_CONTAINER]))
