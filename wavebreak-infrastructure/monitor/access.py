"""Whitelist of Telegram users allowed to use the bot.

The owner (TELEGRAM_OWNER_ID) is always allowed, cannot be removed, and is
the only one who can add or remove other admins. Everyone else is kept in a
small JSON file so the list survives restarts and is editable from the bot.
"""
import json
import os
import threading
import time


class AccessList:
    def __init__(self, path, owner_id):
        self.path = path
        self.owner_id = int(owner_id)
        self._lock = threading.Lock()
        self._admins = self._load()

    def _load(self):
        try:
            with open(self.path, encoding="utf-8") as f:
                data = json.load(f)
            return {int(a["id"]): a for a in data.get("admins", [])}
        except FileNotFoundError:
            return {}

    def _save(self, admins):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"admins": list(admins.values())}, f, ensure_ascii=False, indent=2)
        os.chmod(tmp, 0o600)
        os.replace(tmp, self.path)

    def is_owner(self, user_id):
        return int(user_id) == self.owner_id

    def is_allowed(self, user_id):
        try:
            uid = int(user_id)
        except (TypeError, ValueError):
            return False
        return uid == self.owner_id or uid in self._admins

    def ids(self):
        return [self.owner_id] + [i for i in self._admins if i != self.owner_id]

    def admins(self):
        return sorted(self._admins.values(), key=lambda a: a.get("added_at", 0))

    def add(self, user_id, name, added_by):
        uid = int(user_id)
        if uid == self.owner_id:
            return False
        with self._lock:
            if uid in self._admins:
                return False
            updated = dict(self._admins)
            updated[uid] = {"id": uid, "name": name or "", "added_by": int(added_by), "added_at": int(time.time())}
            self._save(updated)  # persist first: memory never runs ahead of disk
            self._admins = updated
        return True

    def remove(self, user_id):
        uid = int(user_id)
        with self._lock:
            if uid not in self._admins:
                return False
            updated = {k: v for k, v in self._admins.items() if k != uid}
            self._save(updated)
            self._admins = updated
        return True
