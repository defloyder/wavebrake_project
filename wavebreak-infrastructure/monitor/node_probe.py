"""Per-node reachability and latency probes.

Measures TCP connect time from this host to each public node endpoint once a
minute and keeps the samples in monitor.db. Alerts when a node stops
accepting connections, or when its latency rises well above its own recent
median (so a node that is normally far away is not flagged for that).
"""
import socket
import statistics
import time

import monitor as mon

PROBES = [
    ("Турция, Стамбул", "45.15.41.3", 443),
    ("Россия, Москва", "135.106.227.90", 443),
    ("Россия, Yandex", "158.160.44.116", 443),
]
INTERVAL_SEC = 60
BASELINE_WINDOW_SEC = 3600
MIN_BASELINE_SAMPLES = 10
RISE_FACTOR = 2.5
RISE_MIN_MS = 150
CONSECUTIVE = 3
KEEP_SEC = 7 * 24 * 3600

_state = {}


def _db():
    conn = mon.db()
    conn.execute("CREATE TABLE IF NOT EXISTS node_probes(ts INTEGER, node TEXT, ok INTEGER, ms REAL)")
    conn.execute("CREATE INDEX IF NOT EXISTS node_probes_node_ts ON node_probes(node, ts)")
    return conn


def probe(host, port, timeout=3.0):
    start = time.monotonic()
    try:
        with socket.create_connection((host, port), timeout=timeout):
            pass
        return True, (time.monotonic() - start) * 1000.0
    except OSError:
        return False, None


def _baseline(conn, node, now):
    rows = conn.execute(
        "SELECT ms FROM node_probes WHERE node=? AND ok=1 AND ts>=? ORDER BY ts",
        (node, now - BASELINE_WINDOW_SEC),
    ).fetchall()
    values = [r[0] for r in rows]
    return statistics.median(values) if len(values) >= MIN_BASELINE_SAMPLES else None


def summary():
    """Latest state and 1h median per node, for the bot."""
    now = int(time.time())
    conn = _db()
    out = []
    for name, host, port in PROBES:
        last = conn.execute(
            "SELECT ts, ok, ms FROM node_probes WHERE node=? ORDER BY ts DESC LIMIT 1", (name,)
        ).fetchone()
        out.append({
            "node": name,
            "endpoint": f"{host}:{port}",
            "last_ts": last[0] if last else None,
            "ok": bool(last[1]) if last else None,
            "ms": last[2] if last else None,
            "median_1h": _baseline(conn, name, now),
        })
    conn.close()
    return out


def _check(conn, name, host, port, alert, now):
    ok, ms = probe(host, port)
    conn.execute("INSERT INTO node_probes VALUES (?,?,?,?)", (now, name, int(ok), ms))
    st = _state.setdefault(name, {"down": 0, "high": 0, "was_down": False})
    if not ok:
        st["down"] += 1
        st["high"] = 0
        if st["down"] == CONSECUTIVE:
            st["was_down"] = True
            alert("crit", f"{name}: нода не отвечает ({host}:{port}), {CONSECUTIVE} проверки подряд",
                  key=f"node_down_{name}", cooldown=900)
            mon.log_event(f"ALERT node_down node={name}")
        return
    if st["was_down"]:
        st["was_down"] = False
        alert("ok", f"{name}: нода снова отвечает", key=f"node_up_{name}", cooldown=60)
        mon.log_event(f"INFO node_up node={name}")
    st["down"] = 0
    med = _baseline(conn, name, now)
    if med is not None and ms > max(RISE_MIN_MS, RISE_FACTOR * med):
        st["high"] += 1
        if st["high"] == CONSECUTIVE:
            alert("warn", f"{name}: задержка выросла до {ms:.0f} мс (обычно {med:.0f} мс), {CONSECUTIVE} замера подряд",
                  key=f"node_lag_{name}", cooldown=1800)
            mon.log_event(f"ALERT node_lag node={name} ms={ms:.0f} median={med:.0f}")
    else:
        if st["high"] >= CONSECUTIVE:
            alert("ok", f"{name}: задержка снова в норме ({ms:.0f} мс)", key=f"node_lag_ok_{name}", cooldown=60)
        st["high"] = 0


def loop(alert):
    while True:
        try:
            now = int(time.time())
            conn = _db()
            for name, host, port in PROBES:
                _check(conn, name, host, port, alert, now)
            conn.execute("DELETE FROM node_probes WHERE ts < ?", (now - KEEP_SEC,))
            conn.commit()
            conn.close()
        except Exception as e:
            mon.log_event(f"ERROR node_probe loop: {e}")
        time.sleep(INTERVAL_SEC)
