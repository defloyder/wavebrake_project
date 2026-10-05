"""Offline tests for the ops bot: fake Telegram + fake Core + stubbed host probes.
Run: python -m unittest test_bot  (from this directory)"""
import os
import tempfile
import time
import unittest
from datetime import datetime, timezone

import bot as botmod
import monitor as mon
from access import AccessList
from core import CoreError
from tg import html_to_text

OWNER = 475953677
COLLEAGUE = 111222333
STRANGER = 999
USER_ID = "7b0e2c1a-1111-4222-8333-944455556666"
SUB_ID = "5c1d2e3f-aaaa-4bbb-8ccc-dddddddddddd"


class FakeTG:
    def __init__(self):
        self.sent, self.edits, self.answers, self.commands, self.deleted = [], [], [], {}, []

    def send(self, chat_id, html, keyboard=None, silent=False):
        self.sent.append((chat_id, html, keyboard))

    def edit(self, chat_id, message_id, html, keyboard=None):
        self.edits.append((chat_id, message_id, html, keyboard))

    def answer(self, cid, text=None, alert=False):
        self.answers.append(text)

    def set_commands(self, commands, chat_id=None):
        self.commands[chat_id] = [c for c, _ in commands]

    def delete_commands(self, chat_id=None):
        self.deleted.append(chat_id)


class FakeCore:
    def __init__(self, sub=True, access=True, status="active", expires="2026-10-27T00:00:00Z"):
        self.calls = []
        self.sub, self.access_on, self.status, self.expires = sub, access, status, expires

    def dashboard(self):
        return {"users": 3, "active_users": 2, "subscriptions": 2, "active_subscriptions": 1,
                "nodes": 1, "nodes_online": 1, "access_grants": 1, "bytes_total": 5 * 1024 ** 3}

    def users(self):
        return [{"id": USER_ID, "email": "user@example.com", "username": "neo", "status": "active",
                 "created_at": "2026-09-20T10:00:00Z",
                 "subscription": {"id": SUB_ID, "plan_name": "Plus", "status": self.status, "current_period_end": self.expires}},
                {"id": "other", "email": "<b>evil</b>@x.io", "status": "disabled", "created_at": "2026-09-01T00:00:00Z"}]

    def user(self, uid):
        if uid != USER_ID:
            raise CoreError("User not found.", 404)
        d = {"user": {"id": USER_ID, "email": "user@example.com", "role": "user", "status": "active",
                      "created_at": "2026-09-20T10:00:00Z", "last_login_at": None},
             "subscription": None, "access": {"active_grants": 0, "grants": []}, "traffic": None,
             "devices": {"registered": 1, "limit": 3, "items": [
                 {"id": "dev-1", "name": "Pixel 9", "platform": "android", "revoked_at": None, "last_seen_at": None}]}}
        if self.sub:
            d["subscription"] = {"id": SUB_ID, "status": self.status, "plan": {"name": "Plus"}, "expires_at": self.expires}
            d["traffic"] = {"bytes_total": 2 * 1024 ** 3, "limit_bytes": 100 * 1024 ** 3, "used_percent": 2}
        if self.access_on:
            d["access"] = {"active_grants": 1, "subscription_url": "https://cdn.example/sub/abc", "grants": []}
        return d

    def plans(self):
        return [{"id": "plan-1", "name": "Plus", "interval": "month", "is_active": True},
                {"id": "plan-2", "name": "Old", "is_active": False}]

    def subscriptions(self):
        return [{"id": SUB_ID, "user_id": USER_ID, "plan_id": "plan-1", "status": self.status, "current_period_end": self.expires}]

    def grants(self):
        return [{"id": "g1", "user_id": USER_ID, "node_id": "n1", "protocol": "vless", "status": "active", "expires_at": self.expires}]

    def nodes(self):
        return [{"id": "n1", "code": "TR-PILOT-01", "region": "TR", "status": "online",
                 "applied_revision": 5, "desired_revision": 5, "last_heartbeat_at": "2026-09-28T08:00:00Z"}]

    def audit(self):
        return [{"action": "user.disabled", "target_type": "user", "target_id": USER_ID,
                 "actor_user_id": USER_ID, "created_at": "2026-09-27T09:15:00Z"}]

    def __getattr__(self, name):  # every action method records its call
        def rec(*args):
            self.calls.append((name, args))
            return {}
        return rec


def stub_monitor():
    mon.status_snapshot = lambda: {"cores": [{"name": "xray", "up": True, "restarts": "0", "started": "x"},
                                             {"name": "hysteria", "up": True, "restarts": "0", "started": "x"}],
                                   "tcp443": True, "udp443": True, "udp51820": True, "xray_version": "Xray 25"}
    mon.services_snapshot = lambda: [{"name": "wavebreak-api", "ok": True, "status": "Up 1h (healthy)"}]
    mon.load_snapshot = lambda: {"load": ["0.1", "0.2", "0.3"], "cpus": 4, "mem_total": 8 * 1024 ** 3,
                                 "mem_avail": 6 * 1024 ** 3, "swap_total": 0, "swap_free": 0,
                                 "disk_total": 100 * 1024 ** 3, "disk_used": 40 * 1024 ** 3,
                                 "connections": 42, "uptime": 90000}
    mon.online_count = lambda: 2
    mon.log_event = lambda msg: None
    mon.dpi_blocked_snapshot = lambda window_hours=24: {"ips": 0, "hits": 0, "window_hours": window_hours, "top": []}


def msg(uid, text, chat_type="private", **extra):
    return {"message": dict({"from": {"id": uid}, "chat": {"id": uid, "type": chat_type}, "text": text}, **extra)}


def cb(uid, data):
    return {"callback_query": {"id": "cq", "from": {"id": uid}, "data": data,
                               "message": {"message_id": 10, "chat": {"id": uid, "type": "private"}}}}


def all_buttons(kb):
    return [b for row in (kb or []) for b in row]


class BotTest(unittest.TestCase):
    def setUp(self):
        stub_monitor()
        self.tmp = tempfile.TemporaryDirectory()
        self.tg = FakeTG()
        self.core = FakeCore()
        self.access = AccessList(os.path.join(self.tmp.name, "admins.json"), OWNER)
        self.bot = botmod.Bot(self.tg, self.core, self.access, log=lambda m: None)

    def tearDown(self):
        self.tmp.cleanup()

    def last_screen(self):
        if self.tg.edits:
            _, _, html, kb = self.tg.edits[-1]
        else:
            _, html, kb = self.tg.sent[-1]
        return html, kb

    def press(self, uid, label_part):
        _, kb = self.last_screen()
        b = next(b for b in all_buttons(kb) if label_part in b["text"])
        self.bot.handle_update(cb(uid, b["callback_data"]))

    # --- access control ---

    def test_status_hides_hysteria_when_not_monitored(self):
        mon.status_snapshot = lambda: {"cores": [{"name": "xray", "up": True, "restarts": "0", "started": "x"}],
                                       "tcp443": True, "udp443": None, "udp51820": True, "xray_version": "Xray 26"}
        html, _ = self.bot.status_screen()
        self.assertNotIn("Hysteria", html)
        self.assertNotIn("udp/443", html)
        self.assertIn("tcp/443", html)
        home, _ = self.bot.home(OWNER)
        self.assertNotIn("udp/443", home)

    def test_status_shows_active_bans_first_and_history_second(self):
        mon.dpi_blocked_snapshot = lambda window_hours=24: {
            "ips": 3, "hits": 57, "window_hours": 24, "top": [("1.2.3.4", 40), ("5.6.7.8", 17)]}
        mon.active_bans_snapshot = lambda: [{"ip": "9.9.9.9", "left_sec": 240, "kind": "5 мин"}]
        html, _ = self.bot.status_screen()
        self.assertIn("Антипробинг", html)
        self.assertIn("в бане: 1", html)
        self.assertIn("9.9.9.9", html)
        self.assertIn("История за 24 ч: 3 адресов, 57 дропов", html)

    def test_status_dpi_quiet_when_nothing_blocked(self):
        mon.dpi_blocked_snapshot = lambda window_hours=24: {"ips": 0, "hits": 0, "window_hours": 24, "top": []}
        mon.active_bans_snapshot = lambda: []
        html, _ = self.bot.status_screen()
        self.assertIn("никто не забанен", html)

    def test_strangers_and_groups_get_silence(self):
        self.bot.handle_update(msg(STRANGER, "/start"))
        self.bot.handle_update(msg(OWNER, "/start", chat_type="group"))
        self.bot.handle_update(cb(STRANGER, "m"))
        self.assertEqual(self.tg.sent, [])
        self.assertEqual(self.tg.edits, [])

    def test_menu_hidden_by_default_and_shown_per_chat(self):
        self.bot.sync_commands()
        self.assertIn(None, self.tg.deleted)
        self.assertIn("admins", self.tg.commands[OWNER])

    def test_owner_adds_and_removes_colleague(self):
        self.bot.handle_update(msg(OWNER, f"/admins add {COLLEAGUE} Коллега"))
        self.assertTrue(self.access.is_allowed(COLLEAGUE))
        self.assertNotIn("admins", self.tg.commands[COLLEAGUE])  # non-owners don't get /admins
        # persisted
        self.assertTrue(AccessList(self.access.path, OWNER).is_allowed(COLLEAGUE))
        # colleague can use the bot but not manage access
        self.bot.handle_update(msg(COLLEAGUE, "/admins"))
        self.assertIn("только владелец", self.tg.sent[-1][1])
        self.bot.handle_update(cb(COLLEAGUE, "ad"))
        self.assertEqual(self.tg.answers[-1], "Только для владельца")
        # owner removes via confirm flow
        self.bot.handle_update(cb(OWNER, "ad"))
        self.press(OWNER, "Убрать")
        self.press(OWNER, "Да, выполнить")
        self.assertFalse(self.access.is_allowed(COLLEAGUE))
        self.assertIn(COLLEAGUE, self.tg.deleted)

    def test_add_admin_by_forwarded_message(self):
        self.bot.handle_update(cb(OWNER, "adadd"))
        self.bot.handle_update(msg(OWNER, "hi", forward_origin={"type": "user", "sender_user": {"id": COLLEAGUE, "first_name": "Ann"}}))
        self.assertTrue(self.access.is_allowed(COLLEAGUE))
        self.assertIn("Ann", self.tg.sent[-1][1])

    def test_bad_admin_id_rejected(self):
        self.bot.handle_update(msg(OWNER, "/admins add abc"))
        self.assertFalse(self.access.admins())
        self.assertIn("числовой", self.tg.sent[-1][1])

    # --- screens ---

    def test_home_is_rich_and_escaped(self):
        self.bot.handle_update(msg(OWNER, "/start"))
        html, kb = self.last_screen()
        self.assertIn("Центр управления", html)
        self.assertIn("Все системы в норме", html)
        self.assertTrue(any(b["callback_data"] == "ad" for b in all_buttons(kb)))

    def test_every_screen_renders_and_callbacks_fit_64_bytes(self):
        for data in ("m", "mon", "ul:0", "sl:0", "kl:0", "n", "a", "h", "ad", f"u:{USER_ID}"):
            self.bot.handle_update(cb(OWNER, data))
            html, kb = self.last_screen()
            self.assertNotIn("Ошибка", html, data)
            for b in all_buttons(kb):
                if "callback_data" in b:
                    self.assertLessEqual(len(b["callback_data"].encode()), 64, b)

    def test_user_list_escapes_hostile_email(self):
        self.bot.handle_update(cb(OWNER, "ul:0"))
        html, _ = self.last_screen()
        self.assertIn("&lt;b&gt;evil&lt;/b&gt;", html)
        self.assertNotIn("<b>evil</b>", html)

    def test_plain_text_is_search_and_single_hit_opens_card(self):
        self.bot.handle_update(msg(OWNER, "user@EXAMPLE"))
        html, kb = self.last_screen()
        self.assertIn("👤 user@example.com", html)
        self.assertTrue(any(b.get("copy_text") for b in all_buttons(kb)))

    def test_unknown_user_shows_core_error(self):
        self.bot.handle_update(cb(OWNER, "u:nope"))
        self.assertIn("User not found.", self.last_screen()[0])

    # --- actions ---

    def test_no_subscription_offers_plan_then_issues(self):
        self.core.sub, self.core.access_on = False, False
        self.bot.handle_update(cb(OWNER, f"u:{USER_ID}"))
        self.press(OWNER, "Выдать тариф")
        _, kb = self.last_screen()
        self.assertEqual([b["text"] for b in all_buttons(kb) if "🎁" in b["text"]], ["🎁 Plus · месяц"])
        self.press(OWNER, "Plus")
        self.assertEqual(self.core.calls, [])  # nothing happens before confirm
        self.press(OWNER, "Да, выполнить")
        self.assertEqual(self.core.calls, [("issue_subscription", (USER_ID, "plan-1"))])
        self.assertIn("Выдан тариф", self.last_screen()[0])

    def test_subscription_without_key_offers_issue_access(self):
        self.core.access_on = False
        self.bot.handle_update(cb(OWNER, f"u:{USER_ID}"))
        self.press(OWNER, "Выдать ключ")
        self.press(OWNER, "Да, выполнить")
        self.assertEqual(self.core.calls, [("issue_access", (USER_ID,))])

    def test_cancel_does_nothing(self):
        self.bot.handle_update(cb(OWNER, f"u:{USER_ID}"))
        self.press(OWNER, "Заблокировать")
        self.press(OWNER, "Отмена")
        self.assertEqual(self.core.calls, [])

    def test_extend_adds_to_current_expiry(self):
        future = datetime.fromtimestamp(time.time() + 10 * 86400, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.core.expires = future
        self.bot.handle_update(cb(OWNER, f"u:{USER_ID}"))
        self.press(OWNER, "Продлить")
        self.press(OWNER, "+30")
        self.press(OWNER, "Да, выполнить")
        name, (sid, iso, status) = self.core.calls[0]
        self.assertEqual((name, sid, status), ("set_expiry", SUB_ID, None))
        got = datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()
        self.assertAlmostEqual(got, time.time() + 40 * 86400, delta=120)

    def test_extend_expired_restarts_from_now_and_reactivates(self):
        self.core.status, self.core.expires = "expired", "2020-01-01T00:00:00Z"
        self.bot.handle_update(cb(OWNER, f"u:{USER_ID}"))
        self.press(OWNER, "Продлить")
        self.press(OWNER, "+7")
        self.press(OWNER, "Да, выполнить")
        _, (_, iso, status) = self.core.calls[0]
        self.assertEqual(status, "active")
        got = datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()
        self.assertAlmostEqual(got, time.time() + 7 * 86400, delta=120)

    def test_confirm_token_is_single_use(self):
        self.bot.handle_update(cb(OWNER, f"u:{USER_ID}"))
        self.press(OWNER, "Сбросить трафик")
        _, kb = self.last_screen()
        yes = next(b for b in all_buttons(kb) if "Да" in b["text"])["callback_data"]
        self.bot.handle_update(cb(OWNER, yes))
        self.bot.handle_update(cb(OWNER, yes))
        self.assertEqual(self.core.calls, [("reset_usage", (SUB_ID,))])
        self.assertIn("устарела", self.tg.answers[-1])

    def test_core_failure_is_reported_on_card(self):
        def boom(*a):
            raise CoreError("could not reissue subscription link", 400)
        self.core.reissue = boom
        self.bot.handle_update(cb(OWNER, f"u:{USER_ID}"))
        self.press(OWNER, "Перевыпустить")
        self.press(OWNER, "Да, выполнить")
        self.assertIn("Не получилось: could not reissue", self.last_screen()[0])

    def test_revoke_device(self):
        self.bot.handle_update(cb(OWNER, f"u:{USER_ID}"))
        self.press(OWNER, "Отозвать устройство")
        self.press(OWNER, "Pixel 9")
        self.press(OWNER, "Да, выполнить")
        self.assertEqual(self.core.calls, [("revoke_device", ("dev-1",))])

    def test_without_core_monitoring_still_works(self):
        b = botmod.Bot(self.tg, None, self.access, core_error="нет учётки", log=lambda m: None)
        b.handle_update(msg(OWNER, "/start"))
        self.assertIn("нет учётки", self.tg.sent[-1][1])
        b.handle_update(msg(OWNER, "/users"))
        self.assertIn("Связь с Core не настроена", self.tg.sent[-1][1])

    # --- alerts ---

    def test_alert_goes_to_every_admin_with_cooldown(self):
        self.access.add(COLLEAGUE, "c", OWNER)
        self.bot.alert("crit", "xray упал", key="x", cooldown=300)
        self.bot.alert("crit", "xray упал", key="x", cooldown=300)
        self.assertEqual(sorted(c for c, _, _ in self.tg.sent), sorted([OWNER, COLLEAGUE]))

    def test_plain_fallback_text(self):
        self.assertEqual(html_to_text("<h3>Hi</h3><table><tr><td>a</td><td>b &amp; c</td></tr></table>"), "Hi\na | b & c |")


if __name__ == "__main__":
    unittest.main()
