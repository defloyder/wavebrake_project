"""Disk-cleanup scan/run (owner, 15.10): what's safe to remove on any
WaveBreak VPN host, and the action that actually removes it. Stdlib-only,
dependency-free (same reasoning as remote_metrics.py's own docstring) --
this exact module runs both locally (bot.py, for Istanbul) and remotely
(remote_metrics.py's /cleanup endpoints, for every other server), so one
definition of "safe to delete" applies everywhere instead of two
implementations drifting apart.

Every action here only ever removes things nothing currently uses: unused
Docker images/build cache (docker system prune -a, which by definition
never touches an image backing a running container, found live freeing
~10GB on Istanbul), archived systemd journals older than 7 days, the apt
download cache, and (release-mirror hosts only) stale/superseded
release-pipeline artifacts (an incoming-* staging dir release.sh's own
success path never got to clean up, and every .bak-before-* generation
of a file except the newest -- see tools/release/release.sh's own comment
on why that one copy is kept at all: a manual rollback safety net, not an
archive). Nothing here ever touches a running container, a volume, or a
file still referenced by anything.

scan() never deletes anything -- it's the dry-run estimate shown to a
human before they confirm. run(ids) performs exactly the requested ids
and reports bytes actually freed (shutil.disk_usage before/after, not the
scan estimate -- the two can legitimately differ a little, e.g. docker's
own human-readable rounding, and the real number is what matters).
"""
import json
import os
import re
import shutil
import subprocess
import time

RELEASE_MIRROR_DIR = "/var/www/dl/downloads"
# A completed release's own incoming-* is removed automatically by
# release.sh on its success path (see that script's publish step). One
# still present this long after is from an attempt that never finished.
INCOMING_STALE_AFTER_SEC = 24 * 3600

_UNIT = {"B": 1, "KB": 1024, "KIB": 1024, "MB": 1024**2, "MIB": 1024**2,
         "GB": 1024**3, "GIB": 1024**3, "TB": 1024**4, "TIB": 1024**4}


def _parse_size(s):
    m = re.match(r"([\d.]+)\s*([A-Za-z]+)", (s or "").strip())
    if not m:
        return 0
    return int(float(m.group(1)) * _UNIT.get(m.group(2).upper(), 1))


def _run(cmd, timeout=60):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except Exception:
        return None


def _disk_used_bytes():
    return shutil.disk_usage("/").used


def _docker_reclaimable_bytes():
    p = _run(["docker", "system", "df", "--format", "{{json .}}"], timeout=30)
    if not p or p.returncode != 0:
        return 0
    total = 0
    for line in p.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except Exception:
            continue
        total += _parse_size(row.get("Reclaimable", ""))
    return total


def _journal_archived_bytes():
    p = _run(["journalctl", "--disk-usage"], timeout=15)
    if not p or p.returncode != 0:
        return 0
    m = re.search(r"([\d.]+\s*[KMGT]?i?B)", p.stdout)
    return _parse_size(m.group(1)) if m else 0


def _dir_bytes(path):
    p = _run(["du", "-sb", path], timeout=30)
    if not p or p.returncode != 0:
        return 0
    try:
        return int(p.stdout.split()[0])
    except Exception:
        return 0


def _release_mirror_junk():
    """(total_bytes, [(action, path, bytes), ...]) -- stale incoming-*
    staging dirs and every .bak-before-* generation of a file except the
    newest. Empty on any host that doesn't serve the release mirror."""
    if not os.path.isdir(RELEASE_MIRROR_DIR):
        return 0, []
    total = 0
    detail = []
    now = time.time()
    try:
        names = os.listdir(RELEASE_MIRROR_DIR)
    except Exception:
        return 0, []

    for name in names:
        full = os.path.join(RELEASE_MIRROR_DIR, name)
        if name.startswith("incoming-") and os.path.isdir(full):
            try:
                stale = now - os.path.getmtime(full) > INCOMING_STALE_AFTER_SEC
            except OSError:
                continue
            if stale:
                size = _dir_bytes(full)
                total += size
                detail.append(("rmtree", full, size))

    groups = {}
    for name in names:
        m = re.match(r"(.+)\.bak-before-[\d-]+$", name)
        if m:
            groups.setdefault(m.group(1), []).append(name)
    for base, gen_names in groups.items():
        def mtime(n):
            try:
                return os.path.getmtime(os.path.join(RELEASE_MIRROR_DIR, n))
            except OSError:
                return 0
        gen_names.sort(key=mtime, reverse=True)
        for stale_name in gen_names[1:]:  # keep only the newest generation
            full = os.path.join(RELEASE_MIRROR_DIR, stale_name)
            try:
                size = os.path.getsize(full)
            except OSError:
                continue
            total += size
            detail.append(("remove", full, size))
    return total, detail


def scan():
    """[{"id", "label", "bytes"}, ...] for whatever applies on this host --
    a dry-run estimate only, nothing here deletes anything."""
    items = [
        {"id": "docker", "label": "Docker: неиспользуемые образы и build-кэш",
         "bytes": _docker_reclaimable_bytes()},
        {"id": "journal", "label": "Архивные журналы systemd (>7 дней)",
         "bytes": _journal_archived_bytes()},
        {"id": "apt", "label": "Кэш apt", "bytes": _dir_bytes("/var/cache/apt")},
    ]
    mirror_bytes, _ = _release_mirror_junk()
    if os.path.isdir(RELEASE_MIRROR_DIR):
        items.append({"id": "release_mirror",
                       "label": "Архив релизов: заброшенные incoming / старые бэкапы",
                       "bytes": mirror_bytes})
    return items


def run(ids):
    """Performs exactly the requested ids (by scan()'s "id" field).
    Returns {"freed_bytes", "ran": [...], "errors": [...]}."""
    ids = set(ids)
    ran, errors = [], []
    before = _disk_used_bytes()

    if "docker" in ids:
        p = _run(["docker", "system", "prune", "-a", "-f"], timeout=180)
        if p and p.returncode == 0:
            ran.append("docker")
        else:
            errors.append(f"docker: {(p.stderr if p else 'timeout')[:200]}")

    if "journal" in ids:
        p = _run(["journalctl", "--vacuum-time=7d"], timeout=60)
        if p and p.returncode == 0:
            ran.append("journal")
        else:
            errors.append(f"journal: {(p.stderr if p else 'timeout')[:200]}")

    if "apt" in ids:
        p = _run(["apt-get", "clean"], timeout=30)
        if p and p.returncode == 0:
            ran.append("apt")
        else:
            errors.append(f"apt: {(p.stderr if p else 'timeout')[:200]}")

    if "release_mirror" in ids:
        # Re-scanned fresh rather than trusting a value from an earlier
        # scan() call -- real files, could've changed since (a new
        # release ran, someone else cleaned up already).
        _, detail = _release_mirror_junk()
        for action, path, _size in detail:
            try:
                if action == "rmtree":
                    shutil.rmtree(path)
                else:
                    os.remove(path)
            except Exception as e:
                errors.append(f"release_mirror {path}: {e}")
        ran.append("release_mirror")

    after = _disk_used_bytes()
    return {"freed_bytes": max(0, before - after), "ran": ran, "errors": errors}
