"""Smarter DPI-probe autoban: tells a real client apart from active probing
by connection SHAPE, not just connection COUNT.

Background: the first version of this (2026-10-02) banned any source IP
opening 20+ new TCP connections to :443 within 60s. That's also exactly
what a carrier-NAT pool full of real customers looks like (Beeline/
Rostelecom-style mobile ISPs put many unrelated subscribers behind one
public IP) — it was banning real paying customers, not probes. Confirmed
live: the top "attacker" IPs were plain residential/mobile ASNs.

The actual distinguishing signal is session SHAPE: a real client completes
a VLESS/REALITY handshake and holds the connection open for a real session
(seconds to hours). An active prober (RKN-style fingerprinting) opens a
connection, inspects it, and closes it almost immediately — repeatedly,
fast. A NAT pool with many simultaneous real users produces a high
connection COUNT but each individual session's duration is normal; a
prober produces a high count AND short durations. This module keys the
ban on both together.

Reads nginx's stream-level session log (DPI-SESSION <ip> <session_time>,
see pilot-public-http.conf's `dpi_session` log_format — source IP and
duration only, nothing about destination or content) via `docker logs -f`
on the edge container, same tailing pattern as monitor.tail_container.
Bans by adding to the `dpi_probe_ban` ipset (created by the
ipset-dpi-probe systemd unit; UFW's before.rules drops/logs anything
matching it), which self-expires after its configured timeout — this
module never has to un-ban anything itself.

2026-10: repeat offenders escalate to a much longer ban. An IP that
re-triggers the short-session-flood rule REPEAT_BAN_THRESHOLD times within
REPEAT_BAN_WINDOW_SEC is a bot that keeps coming back every time its 5-minute
ban expires — a real person behind carrier-NAT essentially never reproduces
the bot-shaped traffic pattern (15+ connections, 80%+ under 2s) even once,
let alone three separate times in a day. Escalation goes into a SEPARATE
ipset (`dpi_probe_ban_repeat`) with its own long-but-not-infinite timeout
(REPEAT_BAN_TIMEOUT_SEC) rather than a truly permanent block — carriers
reassign public IPs across subscribers (CGNAT), so even a confirmed-bot IP
should eventually free up for whoever gets it next rather than staying
blocked forever. Escalation state is in-memory only (lost on a monitor
restart) — acceptable, since restarts are rare and a bot that keeps probing
just re-accumulates offenses.
"""
import collections
import re
import subprocess
import time

EDGE_CONTAINER = "wavebreak-pilot-public-http"
IPSET_NAME = "dpi_probe_ban"
BAN_TIMEOUT_SEC = 300

REPEAT_IPSET_NAME = "dpi_probe_ban_repeat"
REPEAT_BAN_TIMEOUT_SEC = 7 * 24 * 3600   # 7 days — long, but self-heals for CGNAT reassignment
REPEAT_BAN_WINDOW_SEC = 24 * 3600        # offenses counted within this span
REPEAT_BAN_THRESHOLD = 3                 # this many short-bans in the window -> escalate

WINDOW_SEC = 60          # how far back we look per source IP
MIN_CONNECTIONS = 15     # below this, even all-short sessions could be noise
SHORT_SESSION_SEC = 2.0  # a session shorter than this looks like a probe, not real use
SHORT_FRACTION = 0.8     # this fraction of recent sessions must be short to ban
PRUNE_INTERVAL_SEC = 300 # forget IPs with no recent activity, bound memory

LINE_RE = re.compile(r"DPI-SESSION (\d+\.\d+\.\d+\.\d+) (\d+\.\d+)")

# Our own relays: Istanbul sees every client behind them as one source IP, so
# reconnect storms look like probing. Never banned by this guard.
ALLOWLIST = {"158.160.44.116"}

# An IP that held a real session this long recently is a person, not a probe:
# a prober never keeps a session open. Its short-burst pattern (app retries
# after drops) alone must not ban it.
PROVEN_SESSION_SEC = 60
PROVEN_WINDOW_SEC = 3600


def log_event(msg):
    # Deferred import avoids a hard dependency for anything that only wants
    # the parsing/decision logic (e.g. tests) without the rest of monitor.
    import monitor
    monitor.log_event(f"DPI_GUARD {msg}")


def ban(ip):
    subprocess.run(
        ["ipset", "add", IPSET_NAME, ip, "timeout", str(BAN_TIMEOUT_SEC), "-exist"],
        check=False, capture_output=True,
    )
    log_event(f"BANNED ip={ip} reason=short_session_flood")


def escalate(ip):
    subprocess.run(
        ["ipset", "add", REPEAT_IPSET_NAME, ip, "timeout", str(REPEAT_BAN_TIMEOUT_SEC), "-exist"],
        check=False, capture_output=True,
    )
    log_event(f"ESCALATED ip={ip} reason=repeat_offender timeout={REPEAT_BAN_TIMEOUT_SEC}")


class Guard:
    """Holds the sliding per-IP window; a plain class (not module globals)
    so tests can create independent instances instead of fighting shared state."""

    def __init__(self, now_fn=time.time, ban_fn=ban, escalate_fn=escalate):
        self._events = collections.defaultdict(collections.deque)  # ip -> deque[(ts, duration)]
        self._ban_history = collections.defaultdict(collections.deque)  # ip -> deque[ban_ts]
        self._now = now_fn
        self._ban = ban_fn
        self._escalate = escalate_fn
        self._proven = {}  # ip -> last time it held a real, long session
        self._last_prune = self._now()

    def observe(self, ip, duration):
        if ip in ALLOWLIST:
            return
        now = self._now()
        if duration >= PROVEN_SESSION_SEC:
            self._proven[ip] = now
        events = self._events[ip]
        events.append((now, duration))
        cutoff = now - WINDOW_SEC
        while events and events[0][0] < cutoff:
            events.popleft()

        if len(events) >= MIN_CONNECTIONS:
            short = sum(1 for _, d in events if d < SHORT_SESSION_SEC)
            if short / len(events) >= SHORT_FRACTION:
                proven = self._proven.get(ip)
                if proven is not None and now - proven < PROVEN_WINDOW_SEC:
                    events.clear()  # real user who also retried a lot: not a probe
                    if now - self._last_prune >= PRUNE_INTERVAL_SEC:
                        self._prune(now)
                    return
                self._ban(ip)
                self._record_offense(ip, now)
                events.clear()  # don't re-trigger every subsequent connection during the ban

        if now - self._last_prune >= PRUNE_INTERVAL_SEC:
            self._prune(now)

    def _record_offense(self, ip, now):
        history = self._ban_history[ip]
        history.append(now)
        cutoff = now - REPEAT_BAN_WINDOW_SEC
        while history and history[0] < cutoff:
            history.popleft()
        if len(history) >= REPEAT_BAN_THRESHOLD:
            self._escalate(ip)
            history.clear()  # one escalation per threshold crossing, not every ban after

    def _prune(self, now):
        cutoff = now - WINDOW_SEC
        stale = [ip for ip, events in self._events.items() if not events or events[-1][0] < cutoff]
        for ip in stale:
            del self._events[ip]
        history_cutoff = now - REPEAT_BAN_WINDOW_SEC
        stale_history = [ip for ip, h in self._ban_history.items() if not h or h[-1] < history_cutoff]
        for ip in stale_history:
            del self._ban_history[ip]
        self._last_prune = now


def run_loop():
    guard = Guard()
    while True:
        try:
            proc = subprocess.Popen(
                ["docker", "logs", "-f", "--since", "0m", EDGE_CONTAINER],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            )
            for line in proc.stdout:
                m = LINE_RE.search(line)
                if m:
                    guard.observe(m.group(1), float(m.group(2)))
        except Exception as e:
            log_event(f"ERROR run_loop crashed: {e}")
        log_event("WARN tail exited, restarting in 5s")
        time.sleep(5)
