"""WaveBreak ops bot: one full-width "control panel" message that is edited
in place as you navigate, plus slash commands for direct jumps.

Access: private chats only, Telegram user id must be on the whitelist
(access.AccessList). Every state-changing action goes through an explicit
confirm step and is executed as the bot's own Core account, so it shows up
in Core's audit log.
"""
import html as _html
import secrets
import time
from datetime import datetime, timezone

import monitor as mon
import node_probe
from core import CoreError
from tg import button as B

PAGE = 8
PENDING_TTL = 900
INPUT_TTL = 300

AUDIT_ACTIONS = {
    "user.created": "Создан пользователь", "user.updated": "Изменён пользователь",
    "user.role_updated": "Изменена роль", "user.disabled": "Пользователь заблокирован",
    "user.enabled": "Пользователь разблокирован", "user.delete_requested": "Пользователь удалён",
    "plan.created": "Создан тариф", "plan.updated": "Изменён тариф", "plan.deleted": "Удалён тариф",
    "subscription.created": "Создана подписка", "subscription.created_manual": "Создана подписка вручную",
    "subscription.edited": "Изменена подписка", "subscription.status_updated": "Изменён статус подписки",
    "subscription.usage_reset": "Сброшен трафик", "subscription.link_reissued": "Перевыпущена ссылка",
    "subscription.deleted": "Подписка отменена", "subscription_issued": "Выдана подписка",
    "access_created": "Выдан доступ", "access_grant.revoked": "Отозван ключ доступа",
    "device.revoked": "Отозвано устройство", "password_reset_requested": "Запрошен сброс пароля",
    "password_reset_completed": "Пароль изменён по ссылке", "admin.created": "Создан администратор",
}
SUB_STATUS = {
    "active": ("Активна", "🟢"), "trialing": ("Пробная", "🔵"), "past_due": ("Ожидает оплаты", "🟡"),
    "pending": ("Ожидает", "🟡"), "suspended": ("Приостановлена", "🟠"),
    "cancelled": ("Отменена", "🔴"), "expired": ("Истекла", "🔴"),
}
NODE_STATUS = {"online": "🟢", "offline": "🔴", "pending": "🟡", "draining": "🟠"}

COMMANDS = [
    ("start", "🌊 Центр управления"),
    ("status", "📊 Состояние системы"),
    ("users", "👥 Пользователи · /users email — поиск"),
    ("user", "👤 Карточка · /user email"),
    ("subs", "💳 Подписки"),
    ("keys", "🔑 Ключи доступа"),
    ("nodes", "🖥 Ноды"),
    ("clients", "📡 Клиенты онлайн"),
    ("errors", "⚠️ Ошибки за час"),
    ("logs", "📜 Логи xray · /logs 50"),
    ("audit", "🗂 Журнал действий"),
    ("help", "❔ Справка"),
]
OWNER_COMMANDS = COMMANDS[:-1] + [("admins", "🛡 Доступ к боту"), COMMANDS[-1]]


# ---------- formatting ----------

def esc(s):
    return _html.escape("" if s is None else str(s), quote=True)


def table(headers, rows, caption=None):
    out = ["<table bordered striped compact>"]
    if caption:
        out.append(f"<caption>{esc(caption)}</caption>")
    if headers:
        out.append("<tr>" + "".join(f"<th>{esc(h)}</th>" for h in headers) + "</tr>")
    for r in rows:
        out.append("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>")
    out.append("</table>")
    return "".join(out)


def gb(n):
    if n is None:
        return "∞"
    n = float(n)
    for unit in ("Б", "КБ", "МБ", "ГБ", "ТБ"):
        if abs(n) < 1024:
            return f"{n:.0f} {unit}" if unit in ("Б", "КБ") else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} ПБ"


def bar(pct, width=10):
    if pct is None:
        return ""
    pct = max(0.0, min(100.0, float(pct)))
    filled = round(pct / 100 * width)
    return "▰" * filled + "▱" * (width - filled) + f" {pct:.0f}%"


def parse_ts(value):
    if not value:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def fmt_dt(value, with_time=True):
    ts = parse_ts(value)
    if ts is None:
        return "—"
    return time.strftime("%d.%m.%Y %H:%M" if with_time else "%d.%m.%Y", time.localtime(ts))


def ago(value):
    ts = parse_ts(value)
    if ts is None:
        return "никогда"
    d = time.time() - ts
    if d < 60:
        return "только что"
    if d < 3600:
        return f"{int(d // 60)} мин назад"
    if d < 86400:
        return f"{int(d // 3600)} ч назад"
    return f"{int(d // 86400)} дн назад"


def days_left(value):
    ts = parse_ts(value)
    return None if ts is None else int((ts - time.time()) // 86400)


def sub_badge(status):
    label, dot = SUB_STATUS.get(status or "", (status or "—", "⚪"))
    return f"{dot} {esc(label)}"


def footer():
    return f"<footer>Обновлено {time.strftime('%d.%m %H:%M:%S')}</footer>"


def rfc3339(ts):
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------- the bot ----------

class Bot:
    def __init__(self, tg, core, access, core_error=None, log=mon.log_event):
        self.tg = tg
        self.core = core
        self.core_error = core_error  # why Core is not configured, if it isn't
        self.access = access
        self.log = log
        self.pending = {}   # token -> action spec
        self.awaiting = {}  # user id -> (kind, since)
        self._last_cmd = {}
        self._commands_set = set()
        self._alert_sent = {}

    # ----- plumbing -----

    def token(self, spec):
        now = time.time()
        for k in [k for k, v in self.pending.items() if now - v["at"] > PENDING_TTL]:
            del self.pending[k]
        t = secrets.token_urlsafe(6)
        spec["at"] = now
        self.pending[t] = spec
        return t

    def sync_commands(self):
        """Hide the menu from everyone, then show it to whitelisted chats only."""
        try:
            self.tg.delete_commands()
        except Exception as e:
            self.log(f"WARN deleteMyCommands default: {e}")
        for uid in self.access.ids():
            self.ensure_commands(uid)

    def ensure_commands(self, uid):
        if uid in self._commands_set:
            return
        try:
            self.tg.set_commands(OWNER_COMMANDS if self.access.is_owner(uid) else COMMANDS, chat_id=uid)
            self._commands_set.add(uid)
        except Exception as e:
            # "chat not found" until that person has pressed Start once.
            self.log(f"WARN setMyCommands for {uid}: {e}")

    def handle_update(self, update):
        if "callback_query" in update:
            return self.on_callback(update["callback_query"])
        msg = update.get("message")
        if msg:
            return self.on_message(msg)

    def _authorized(self, user, chat):
        uid = (user or {}).get("id")
        if (chat or {}).get("type") != "private" or not self.access.is_allowed(uid):
            self.log(f"WARN bot: ignored update from user_id={uid} chat_type={(chat or {}).get('type')}")
            return False
        return True

    # ----- messages -----

    def on_message(self, msg):
        user, chat = msg.get("from") or {}, msg.get("chat") or {}
        if not self._authorized(user, chat):
            return
        uid, chat_id = user["id"], chat["id"]
        self.ensure_commands(uid)
        text = (msg.get("text") or "").strip()

        pending_input = self.awaiting.pop(uid, None)
        if pending_input and time.time() - pending_input[1] < INPUT_TTL and not text.startswith("/"):
            kind = pending_input[0]
            if kind == "search":
                return self.send(chat_id, *self.search_screen(text))
            if kind == "admin_add":
                return self.send(chat_id, *self.admin_add_from_message(uid, msg))

        if not text.startswith("/"):
            if text:  # plain text = user search, the most common quick lookup
                return self.send(chat_id, *self.search_screen(text))
            return

        now = time.time()
        last_text, last_at = self._last_cmd.get(uid, ("", 0))
        if text == last_text and now - last_at < 1.0:  # accidental double send
            return
        self._last_cmd[uid] = (text, now)
        parts = text.split()
        cmd, args = parts[0].split("@")[0].lower(), parts[1:]
        self.log(f"INFO bot: user={uid} command {cmd} {' '.join(args)}")
        try:
            screen = self.command_screen(cmd, args, uid)
        except CoreError as e:
            screen = self.error_screen(e)
        except Exception as e:
            self.log(f"ERROR bot command {cmd}: {e}")
            screen = self.error_screen(e)
        if screen:
            self.send(chat_id, *screen)

    def command_screen(self, cmd, args, uid):
        if cmd in ("/start", "/menu"):
            return self.home(uid)
        if cmd == "/status":
            return self.status_screen()
        if cmd == "/users":
            return self.search_screen(" ".join(args)) if args else self.users_screen(0)
        if cmd == "/user":
            if not args:
                self.awaiting[uid] = ("search", time.time())
                return "<p>🔎 Пришлите email, username или ID пользователя.</p>", [[B("⬅ Меню", "m")]]
            return self.search_screen(" ".join(args))
        if cmd == "/subs":
            return self.subs_screen(0)
        if cmd == "/keys":
            return self.keys_screen(0)
        if cmd == "/nodes":
            return self.nodes_screen()
        if cmd == "/clients":
            return self.clients_screen()
        if cmd == "/errors":
            return self.errors_screen()
        if cmd == "/logs":
            n = 30
            if args and args[0].isdigit():
                n = min(200, max(1, int(args[0])))
            return self.logs_screen(n)
        if cmd == "/reconnects":
            return self.reconnects_screen(args[0] if args else None)
        if cmd == "/audit":
            return self.audit_screen()
        if cmd == "/admins":
            if not self.access.is_owner(uid):
                return "<p>🛡 Управлять доступом может только владелец.</p>", None
            if len(args) >= 2 and args[0] == "add":
                return self.admin_add(uid, args[1], " ".join(args[2:]))
            return self.admins_screen()
        if cmd == "/help":
            return self.help_screen(uid)
        return f"<p>Неизвестная команда <code>{esc(cmd)}</code>. /help — список.</p>", [[B("🌊 Меню", "m")]]

    def send(self, chat_id, html, keyboard=None):
        self.tg.send(chat_id, html, keyboard)

    # ----- callbacks -----

    def on_callback(self, cq):
        user = cq.get("from") or {}
        msg = cq.get("message") or {}
        chat = msg.get("chat") or {}
        if not self._authorized(user, chat):
            self.tg.answer(cq["id"])
            return
        uid, data = user["id"], cq.get("data") or ""
        self.ensure_commands(uid)
        toast = None
        try:
            screen, toast = self.callback_screen(data, uid)
        except CoreError as e:
            screen = self.error_screen(e)
        except Exception as e:
            self.log(f"ERROR bot callback {data}: {e}")
            screen = self.error_screen(e)
        self.tg.answer(cq["id"], toast)
        if screen:
            self.tg.edit(chat["id"], msg["message_id"], *screen)

    def callback_screen(self, data, uid):
        head, _, arg = data.partition(":")
        simple = {
            "m": lambda: self.home(uid), "mon": self.status_screen,
            "cl": self.clients_screen, "er": self.errors_screen, "lg": lambda: self.logs_screen(30),
            "rc": lambda: self.reconnects_screen(None), "n": self.nodes_screen, "a": self.audit_screen,
            "h": lambda: self.help_screen(uid),
        }
        if head in simple:
            return simple[head](), None
        if head == "ul":
            return self.users_screen(int(arg or 0)), None
        if head == "sl":
            return self.subs_screen(int(arg or 0)), None
        if head == "kl":
            return self.keys_screen(int(arg or 0)), None
        if head == "u":
            return self.user_screen(arg), None
        if head == "srch":
            self.awaiting[uid] = ("search", time.time())
            return ("<h3>🔎 Поиск пользователя</h3><p>Пришлите email, username или ID следующим сообщением.</p>",
                    [[B("⬅ Пользователи", "ul:0")]]), None
        if head in ("ad", "adadd", "adrm"):
            if not self.access.is_owner(uid):
                return None, "Только для владельца"
            if head == "ad":
                return self.admins_screen(), None
            if head == "adadd":
                self.awaiting[uid] = ("admin_add", time.time())
                return ("<h3>➕ Новый администратор</h3>"
                        "<p>Пришлите его числовой Telegram ID (узнать: @userinfobot) — "
                        "или просто перешлите сюда любое его сообщение.</p>"
                        "<blockquote>Человек должен один раз нажать Start у бота, иначе бот не сможет ему писать.</blockquote>",
                        [[B("⬅ Назад", "ad")]]), None
            return self.confirm_screen(self.token({"kind": "admin_remove", "target": int(arg)})), None
        if head == "p":   # action menu (plan picker / extend picker / device list)
            return self.picker(arg), None
        if head == "c":   # show confirmation
            return self.confirm_screen(arg), None
        if head == "y":   # confirmed
            return self.execute(arg, uid)
        return None, "Кнопка устарела — откройте экран заново"

    # ---------- screens: home & monitoring ----------

    def home(self, uid):
        st = mon.status_snapshot()
        ld = mon.load_snapshot()
        services = mon.services_snapshot()
        broken = [s for s in services if not s["ok"]]
        core_ok, dash, core_msg = self._dashboard()
        all_ok = all(c["up"] for c in st["cores"]) and st["tcp443"] and not broken and core_ok
        headline = "🟢 Все системы в норме" if all_ok else "🔴 Есть проблемы — см. ниже"

        mem_used = ld["mem_total"] - ld["mem_avail"]
        mem_pct = mem_used / ld["mem_total"] * 100 if ld["mem_total"] else None
        disk_pct = ld["disk_used"] / ld["disk_total"] * 100 if ld["disk_total"] else None
        vitals = table(["Показатель", "Значение"], [
            ["⚙️ Нагрузка", f"{esc(' / '.join(ld['load']))} <i>({ld['cpus']} CPU)</i>"],
            ["🧠 Память", f"{bar(mem_pct)} · {gb(mem_used)} из {gb(ld['mem_total'])}"],
            ["💽 Диск", f"{bar(disk_pct)} · {gb(ld['disk_used'])} из {gb(ld['disk_total'])}"],
            ["🔗 TCP-соединений", str(ld["connections"])],
            ["⏱ Аптайм", f"{int(ld['uptime'] // 86400)} дн {int(ld['uptime'] % 86400 // 3600)} ч"],
        ])
        cores = table(["Узел", "Статус"], [
            [f"<b>{esc(c['name'])}</b>", "🟢 работает" if c["up"] else "🔴 <b>ЛЕЖИТ</b>"] for c in st["cores"]
        ] + [
            ["<b>tcp/443</b>", "🟢 слушает" if st["tcp443"] else "🔴 <b>не слушает</b>"],
        ] + ([["<b>udp/443</b>", "🟢 слушает" if st["udp443"] else "🟠 не слушает"]] if st.get("udp443") is not None else []) + [
            ["<b>Core API</b>", "🟢 отвечает" if core_ok else f"🔴 {esc(core_msg)}"],
        ] + [[f"<b>{esc(s['name'])}</b>", f"🔴 {esc(s['status'])}"] for s in broken])

        kpi = ""
        if core_ok:
            kpi = table(["", ""], [
                ["👥 Пользователи", f"<b>{dash.get('users', '—')}</b> · активных {dash.get('active_users', '—')}"],
                ["💳 Подписки", f"<b>{dash.get('active_subscriptions', '—')}</b> активных из {dash.get('subscriptions', '—')}"],
                ["📡 Онлайн сейчас", f"<b>{mon.online_count()}</b> клиентов"],
                ["🔑 Ключей доступа", str(dash.get("access_grants", "—"))],
                ["🖥 Ноды", f"{dash.get('nodes_online', '—')} / {dash.get('nodes', '—')} онлайн"],
                ["📶 Трафик всего", gb(dash.get("bytes_total") or 0)],
            ], caption="Сервис")

        html = (f"<h2>🌊 WAVEBREAK · Центр управления</h2><p><b>{headline}</b></p>"
                f"{cores}{kpi}<details><summary>🖥 Сервер</summary>{vitals}</details>{footer()}")
        kb = [
            [B("📊 Мониторинг", "mon", "primary"), B("👥 Пользователи", "ul:0", "primary")],
            [B("💳 Подписки", "sl:0"), B("🔑 Ключи", "kl:0")],
            [B("🖥 Ноды", "n"), B("🗂 Аудит", "a")],
        ]
        last = [B("🔄 Обновить", "m")]
        if self.access.is_owner(uid):
            last.insert(0, B("🛡 Доступ к боту", "ad"))
        kb.append(last)
        return html, kb

    def _dashboard(self):
        if not self.core:
            return False, {}, self.core_error or "не настроен"
        try:
            return True, self.core.dashboard(), ""
        except CoreError as e:
            return False, {}, str(e)

    def status_screen(self):
        st = mon.status_snapshot()
        services = mon.services_snapshot()
        cores = table(["Ядро", "Статус", "Рестартов", "Запущено"], [
            [f"<b>{esc(c['name'])}</b>", "🟢 UP" if c["up"] else "🔴 DOWN", esc(c["restarts"]), esc(c["started"])]
            for c in st["cores"]
        ], caption=st["xray_version"])
        ports = table(["Порт", "Статус"], [
            ["tcp/443 (REALITY/TLS/сайт)", "🟢" if st["tcp443"] else "🔴"],
        ] + ([["udp/443 (Hysteria2)", "🟢" if st["udp443"] else "🔴"]] if st.get("udp443") is not None else []) + [
            ["udp/51820 (ops WireGuard)", "🟢" if st["udp51820"] else "⚪"],
        ])
        svc = table(["Контейнер", "Состояние"], [
            [("🟢 " if s["ok"] else "🔴 ") + esc(s["name"]), esc(s["status"])] for s in services
        ])
        bans = mon.active_bans_snapshot()
        dpi = mon.dpi_blocked_snapshot()
        if bans:
            ban_rows = [[f"<code>{esc(b['ip'])}</code>", esc(b["kind"]), f"{b['left_sec'] // 60} мин"] for b in bans]
            dpi_html = f"<p>Сейчас в бане: <b>{len(bans)}</b></p>" + table(["IP", "Бан", "Осталось"], ban_rows)
        else:
            dpi_html = "<p>🟢 Сейчас никто не забанен.</p>"
        hist_bans = mon.ban_history_snapshot()
        if hist_bans["rows"]:
            allow = getattr(mon, "DPI_ALLOWLIST_LABELS", {})
            hist_rows = [[f"<code>{esc(r['ip'])}</code>" + (f" {esc(allow[r['ip']])}" if r["ip"] in allow else ""),
                          str(r["count"]), esc(r["last"].replace("T", " ")[5:16])] for r in hist_bans["rows"]]
            hist = (f"<p><b>За {hist_bans['window_hours']} ч:</b> {len(hist_bans['rows'])} адресов, "
                    f"{hist_bans['bans']} банов</p>" + table(["IP", "Банов", "Последний"], hist_rows))
        else:
            hist = f"<p>За {hist_bans['window_hours']} ч банов не было.</p>"
        dpi_block = (f"<details><summary>🛡 Антипробинг tcp/443 (в бане: {len(bans)})</summary>{dpi_html}{hist}"
                     "<blockquote>20+ новых соединений на 443 за 60 сек с одного IP — бан на 5 мин, повторные — на 7 дней.</blockquote></details>")
        html = f"<h3>📊 Мониторинг</h3>{cores}{ports}{dpi_block}<details><summary>🐳 Контейнеры ({len(services)})</summary>{svc}</details>{footer()}"
        kb = [
            [B("📡 Клиенты", "cl")],
            [B("⚠️ Ошибки", "er"), B("📜 Логи", "lg"), B("🔁 Реконнекты", "rc")],
            [B("⬅ Меню", "m"), B("🔄 Обновить", "mon")],
        ]
        return html, kb

    def clients_screen(self):
        rows = mon.clients_snapshot()
        online = sum(1 for r in rows if r["online"])
        body = table(["Клиент", "Статус", "Активность", "Сессий 1ч", "Потоков 24ч"], [
            [f"<code>{esc(r['client'])}</code>", "🟢 онлайн" if r["online"] else "⚪ офлайн",
             esc(ago(r["last"])), str(r["reconnects_1h"]), str(r["flows_24h"])] for r in rows[:40]
        ]) if rows else "<p>Клиентов нет.</p>"
        html = (f"<h3>📡 Клиенты · {online} онлайн из {len(rows)}</h3>{body}"
                "<blockquote>Онлайн = активность за последние ~10 минут (эвристика по логам, не живая сессия).</blockquote>"
                f"{footer()}")
        return html, [[B("⬅ Мониторинг", "mon"), B("🔄 Обновить", "cl")]]

    def errors_screen(self):
        groups = mon.error_groups()
        body = (table(["×", "Сообщение"], [[str(n), f"<code>{esc(p)}</code>"] for n, p in groups])
                if groups else "<p>🟢 За последний час ошибок и предупреждений нет.</p>")
        return f"<h3>⚠️ Ошибки {'xray/hysteria' if mon.HY_ENABLED else 'xray'} · 60 мин</h3>{body}{footer()}", [
            [B("📜 Логи", "lg"), B("⬅ Мониторинг", "mon"), B("🔄", "er")]]

    def logs_screen(self, n):
        text = mon.xray_logs(n)
        if len(text) > 20000:
            text = text[-20000:]
        return f"<h3>📜 xray · последние {n} строк</h3><pre>{esc(text)}</pre>{footer()}", [
            [B("⚠️ Ошибки", "er"), B("⬅ Мониторинг", "mon"), B("🔄", "lg")]]

    def reconnects_screen(self, client):
        events = mon.reconnect_events(client)
        rows = []
        for l in events:
            ts, _, rest = l.partition(" ")
            rows.append([esc(ts[11:19]), f"<code>{esc(rest)}</code>"])
        title = f"🔁 Подключения{' · ' + esc(client) if client else ''}"
        body = table(["Время", "Событие"], rows) if rows else "<p>Событий нет.</p>"
        return f"<h3>{title}</h3>{body}{footer()}", [[B("⬅ Мониторинг", "mon"), B("🔄", "rc")]]

    # ---------- screens: Core ----------

    def _need_core(self):
        if not self.core:
            raise CoreError(f"Связь с Core не настроена: {self.core_error or 'нет учётных данных'}")

    def users_screen(self, page, users=None, title="👥 Пользователи"):
        self._need_core()
        if users is None:
            users = sorted(self.core.users(), key=lambda u: u.get("created_at") or "", reverse=True)
        total = len(users)
        pages = max(1, (total + PAGE - 1) // PAGE)
        page = max(0, min(page, pages - 1))
        chunk = users[page * PAGE:(page + 1) * PAGE]
        rows = []
        for u in chunk:
            sub = u.get("subscription") or {}
            blocked = u.get("status") == "disabled" or u.get("disabled_at")
            rows.append([
                f"{'⛔ ' if blocked else ''}<b>{esc(u.get('email') or '—')}</b>",
                esc(sub.get("plan_name") or "—"),
                sub_badge(sub.get("status")) if sub else "⚪ нет",
                esc(fmt_dt(sub.get("current_period_end"), False)) if sub else "—",
            ])
        html = (f"<h3>{title} · {total}</h3>"
                f"{table(['Email', 'Тариф', 'Подписка', 'До'], rows) if rows else '<p>Никого не найдено.</p>'}"
                f"<footer>Стр. {page + 1} из {pages} · нажмите на пользователя, чтобы открыть карточку</footer>")
        kb = [[B(f"👤 {(u.get('email') or u['id'])[:40]}", f"u:{u['id']}")] for u in chunk]
        nav = []
        if page > 0:
            nav.append(B("◀", f"ul:{page - 1}"))
        nav.append(B("🔎 Поиск", "srch"))
        if page < pages - 1:
            nav.append(B("▶", f"ul:{page + 1}"))
        kb.append(nav)
        kb.append([B("⬅ Меню", "m")])
        return html, kb

    def search_screen(self, query):
        self._need_core()
        q = query.strip().lower()
        users = self.core.users()
        hits = [u for u in users if q and (q in (u.get("email") or "").lower()
                                           or q in (u.get("username") or "").lower() or q == u.get("id", "").lower())]
        if len(hits) == 1:
            return self.user_screen(hits[0]["id"])
        if not hits:
            return (f"<p>🔎 По запросу <b>{esc(query)}</b> никого не нашлось.</p>",
                    [[B("🔎 Искать ещё", "srch"), B("👥 Все", "ul:0")], [B("⬅ Меню", "m")]])
        return self.users_screen(0, hits, f"🔎 «{esc(query)}»")

    def user_screen(self, user_id, banner=None):
        self._need_core()
        d = self.core.user(user_id)
        u, sub = d.get("user") or {}, d.get("subscription")
        access, traffic, devices = d.get("access") or {}, d.get("traffic") or {}, d.get("devices") or {}
        blocked = u.get("status") == "disabled" or bool(u.get("disabled_at"))

        parts = []
        if banner:
            parts.append(f"<blockquote>{banner}</blockquote>")
        parts.append(f"<h3>👤 {esc(u.get('email'))}</h3>")
        parts.append(table(["", ""], [
            ["Статус", "⛔ <b>Заблокирован</b>" if blocked else "🟢 Активен"],
            ["Роль", esc(u.get("role"))],
            ["Username", esc(u.get("username") or "—")],
            ["Регистрация", esc(fmt_dt(u.get("created_at"), False))],
            ["Последний вход", esc(ago(u.get("last_login_at")))],
        ]))
        if sub:
            plan = sub.get("plan") or {}
            left = days_left(sub.get("expires_at"))
            left_txt = "" if left is None else (f" · осталось {left} дн" if left >= 0 else " · <b>просрочена</b>")
            used, limit = traffic.get("bytes_total") or 0, traffic.get("limit_bytes")
            traffic_line = f"{gb(used)} из {gb(limit)}"
            if traffic.get("used_percent") is not None:
                traffic_line = f"{bar(traffic['used_percent'])} · {traffic_line}"
            parts.append(table(["", ""], [
                ["Тариф", f"<b>{esc(plan.get('name') or 'Индивидуальный')}</b>"],
                ["Статус", sub_badge(sub.get("status"))],
                ["Действует до", esc(fmt_dt(sub.get("expires_at"))) + left_txt],
                ["Трафик", traffic_line],
                ["Устройства", f"{devices.get('registered', 0)} из {devices.get('limit') if devices.get('limit') is not None else '—'}"],
                ["Ключей активно", str(access.get("active_grants", 0))],
            ], caption="💳 Подписка"))
        else:
            parts.append("<p>💳 <b>Подписки нет.</b></p>")
        url = access.get("subscription_url")
        if url:
            parts.append(f"<details><summary>🔗 Ссылка подписки</summary><pre>{esc(url)}</pre></details>")
        items = devices.get("items") or []
        if items:
            parts.append("<details><summary>📱 Устройства ({})</summary>{}</details>".format(len(items), table(
                ["Устройство", "Платформа", "Статус", "Активность"],
                [[esc(i.get("name")), esc(i.get("platform") or "—"),
                  "⛔ отозвано" if i.get("revoked_at") else "🟢", esc(ago(i.get("last_seen_at")))] for i in items])))
        parts.append(footer())

        uid = u.get("id") or user_id
        email = u.get("email") or uid
        kb = []
        if not sub:
            kb.append([B("🎁 Выдать тариф", "p:" + self.token({"kind": "pick_plan", "user": uid, "email": email}), "success")])
        else:
            sid = sub["id"]
            if not access.get("active_grants"):
                kb.append([B("🔑 Выдать ключ доступа", "c:" + self.token({"kind": "issue_access", "user": uid, "email": email}), "success")])
            else:
                row = [B("♻️ Перевыпустить ключ", "c:" + self.token({"kind": "reissue", "user": uid, "sub": sid, "email": email}))]
                if url:
                    row.append(B("📋 Ссылка", copy=url))
                kb.append(row)
            kb.append([
                B("⏩ Продлить", "p:" + self.token({"kind": "pick_extend", "user": uid, "sub": sid, "email": email,
                                                     "expires": sub.get("expires_at"), "status": sub.get("status")})),
                B("🔄 Сбросить трафик", "c:" + self.token({"kind": "reset", "user": uid, "sub": sid, "email": email})),
            ])
            if sub.get("status") == "active":
                kb.append([B("⏸ Приостановить подписку", "c:" + self.token({"kind": "sub_status", "user": uid, "sub": sid, "email": email, "status": "suspended"}))])
            elif sub.get("status") == "suspended":
                kb.append([B("▶️ Возобновить подписку", "c:" + self.token({"kind": "sub_status", "user": uid, "sub": sid, "email": email, "status": "active"}), "success")])
        live_devices = [i for i in items if not i.get("revoked_at")]
        if live_devices:
            kb.append([B(f"📱 Отозвать устройство ({len(live_devices)})", "p:" + self.token({"kind": "pick_device", "user": uid, "email": email}))])
        kb.append([B("✅ Разблокировать", "c:" + self.token({"kind": "enable", "user": uid, "email": email}), "success")] if blocked
                  else [B("⛔ Заблокировать", "c:" + self.token({"kind": "disable", "user": uid, "email": email}), "danger")])
        kb.append([B("⬅ Пользователи", "ul:0"), B("🔄 Обновить", f"u:{uid}")])
        return "".join(parts), kb

    def subs_screen(self, page):
        self._need_core()
        subs = self.core.subscriptions()
        users = {u["id"]: u for u in self.core.users()}
        plans = {p["id"]: p for p in self.core.plans()}

        def urgency(s):
            left = days_left(s.get("current_period_end"))
            bad = s.get("status") not in ("active", "trialing")
            return (0 if bad else 1 if left is not None and left <= 3 else 2, left if left is not None else 9999)

        subs.sort(key=urgency)
        pages = max(1, (len(subs) + PAGE - 1) // PAGE)
        page = max(0, min(page, pages - 1))
        chunk = subs[page * PAGE:(page + 1) * PAGE]
        rows = []
        for s in chunk:
            left = days_left(s.get("current_period_end"))
            warn = " ⚠️" if left is not None and 0 <= left <= 3 and s.get("status") == "active" else ""
            plan_name = (plans.get(s.get("plan_id")) or {}).get("name") or ("Индивидуальный" if s.get("source") == "admin_manual" else "—")
            rows.append([esc((users.get(s.get("user_id")) or {}).get("email") or "—"), esc(plan_name),
                         sub_badge(s.get("status")), esc(fmt_dt(s.get("current_period_end"), False)) + warn])
        active = sum(1 for s in subs if s.get("status") == "active")
        html = (f"<h3>💳 Подписки · {active} активных из {len(subs)}</h3>"
                f"{table(['Пользователь', 'Тариф', 'Статус', 'До'], rows) if rows else '<p>Подписок нет.</p>'}"
                f"<footer>Сначала проблемные и истекающие · стр. {page + 1}/{pages}</footer>")
        kb = [[B(f"👤 {((users.get(s.get('user_id')) or {}).get('email') or s.get('user_id'))[:40]}", f"u:{s.get('user_id')}")]
              for s in chunk if s.get("user_id")]
        nav = ([B("◀", f"sl:{page - 1}")] if page > 0 else []) + ([B("▶", f"sl:{page + 1}")] if page < pages - 1 else [])
        if nav:
            kb.append(nav)
        kb.append([B("⬅ Меню", "m"), B("🔄", f"sl:{page}")])
        return html, kb

    def keys_screen(self, page):
        self._need_core()
        grants = sorted(self.core.grants(), key=lambda g: (g.get("status") != "active", g.get("created_at") or ""))
        users = {u["id"]: u for u in self.core.users()}
        nodes = {n.get("id"): n for n in self.core.nodes()}
        pages = max(1, (len(grants) + PAGE - 1) // PAGE)
        page = max(0, min(page, pages - 1))
        chunk = grants[page * PAGE:(page + 1) * PAGE]
        rows = [[esc((users.get(g.get("user_id")) or {}).get("email") or "—"),
                 esc((nodes.get(g.get("node_id")) or {}).get("code") or "—"),
                 esc((g.get("protocol") or "").upper()),
                 "🟢 активен" if g.get("status") == "active" else ("⛔ отозван" if g.get("status") == "revoked" else "⚪ " + esc(g.get("status"))),
                 esc(fmt_dt(g.get("expires_at"), False))] for g in chunk]
        active = sum(1 for g in grants if g.get("status") == "active")
        html = (f"<h3>🔑 Ключи доступа · {active} активных</h3>"
                f"{table(['Пользователь', 'Нода', 'Протокол', 'Статус', 'До'], rows) if rows else '<p>Ключей нет.</p>'}"
                f"<footer>Выдача и перевыпуск — в карточке пользователя · стр. {page + 1}/{pages}</footer>")
        kb = [[B(f"👤 {((users.get(g.get('user_id')) or {}).get('email') or '—')[:40]}", f"u:{g.get('user_id')}")]
              for g in chunk if g.get("user_id")]
        nav = ([B("◀", f"kl:{page - 1}")] if page > 0 else []) + ([B("▶", f"kl:{page + 1}")] if page < pages - 1 else [])
        if nav:
            kb.append(nav)
        kb.append([B("⬅ Меню", "m"), B("🔄", f"kl:{page}")])
        return html, kb

    def nodes_screen(self):
        self._need_core()
        rows = []
        for n in self.core.nodes():
            applied, desired = n.get("applied_revision"), n.get("desired_revision")
            sync = "🟢 синхронна" if applied == desired else f"🟡 {applied} → {desired}"
            if n.get("last_sync_error"):
                sync = f"🔴 {esc(str(n['last_sync_error'])[:80])}"
            rows.append([f"{NODE_STATUS.get(n.get('status'), '⚪')} <b>{esc(n.get('code'))}</b>", esc(n.get("region") or "—"),
                         esc(ago(n.get("last_heartbeat_at"))), sync])
        probe_rows = []
        for p in node_probe.summary():
            if p["ok"] is None:
                state, ms = "⚪ нет данных", "—"
            elif not p["ok"]:
                state, ms = "🔴 недоступна", "—"
            else:
                state, ms = "🟢 доступна", f"{p['ms']:.0f} мс"
            med = f"{p['median_1h']:.0f} мс" if p["median_1h"] is not None else "—"
            probe_rows.append([f"<b>{esc(p['node'])}</b>", f"<code>{esc(p['endpoint'])}</code>", state, ms, med])
        html = (f"<h3>🖥 Ноды</h3>{table(['Нода', 'Регион', 'Heartbeat', 'Конфигурация'], rows) if rows else '<p>Нод нет.</p>'}"
                f"<h3>📡 Доступность и задержка</h3>"
                f"{table(['Точка', 'Адрес', 'Статус', 'Сейчас', 'Медиана 1 ч'], probe_rows)}"
                f"{footer()}")
        return html, [[B("⬅ Меню", "m"), B("🔄 Обновить", "n")]]

    def audit_screen(self):
        self._need_core()
        events = self.core.audit()[:15]
        users = {u["id"]: u.get("email") for u in self.core.users()}
        rows = []
        for e in events:
            target = users.get(e.get("target_user_id")) or users.get(e.get("target_id")) or e.get("target_type") or "—"
            rows.append([esc(fmt_dt(e.get("created_at"))), esc(AUDIT_ACTIONS.get(e.get("action"), e.get("action"))),
                         esc(target), esc(users.get(e.get("actor_user_id")) or "система")])
        html = f"<h3>🗂 Журнал действий</h3>{table(['Когда', 'Действие', 'Объект', 'Кто'], rows) if rows else '<p>Пусто.</p>'}{footer()}"
        return html, [[B("⬅ Меню", "m"), B("🔄 Обновить", "a")]]

    # ---------- pickers, confirmation, execution ----------

    def picker(self, tok):
        spec = self.pending.get(tok)
        if not spec:
            return "<p>⌛ Кнопка устарела — откройте карточку заново.</p>", [[B("⬅ Меню", "m")]]
        back = [B("⬅ Карточка", f"u:{spec['user']}")]
        if spec["kind"] == "pick_plan":
            plans = [p for p in self.core.plans() if p.get("is_active", True)]
            term = lambda p: f"{p['duration_days']} дн" if p.get("duration_days") else \
                {"month": "месяц", "year": "год", "week": "неделя", "day": "день"}.get(p.get("interval"), p.get("interval") or "")
            kb = [[B(f"🎁 {p.get('name') or p.get('code')} · {term(p)}",
                     "c:" + self.token({"kind": "issue_plan", "user": spec["user"], "email": spec["email"],
                                        "plan": p["id"], "plan_name": p.get("name") or p.get("code")}))] for p in plans]
            return f"<h3>🎁 Какой тариф выдать {esc(spec['email'])}?</h3>", kb + [back]
        if spec["kind"] == "pick_extend":
            kb = [[B(f"+{d} дн", "c:" + self.token(dict(spec, kind="extend", days=d))) for d in (7, 30)],
                  [B(f"+{d} дн", "c:" + self.token(dict(spec, kind="extend", days=d))) for d in (90, 365)]]
            return (f"<h3>⏩ Продлить подписку {esc(spec['email'])}</h3>"
                    f"<p>Сейчас до: <b>{esc(fmt_dt(spec.get('expires')))}</b>. Срок добавляется к текущей дате окончания "
                    "(или к сегодняшней, если подписка уже истекла).</p>"), kb + [back]
        if spec["kind"] == "pick_device":
            items = [i for i in (self.core.user(spec["user"]).get("devices") or {}).get("items") or [] if not i.get("revoked_at")]
            kb = [[B(f"📱 {i.get('name')} · {i.get('platform') or '?'}",
                     "c:" + self.token({"kind": "revoke_device", "user": spec["user"], "email": spec["email"],
                                        "device": i["id"], "device_name": i.get("name")}), "danger")] for i in items]
            return f"<h3>📱 Какое устройство отозвать у {esc(spec['email'])}?</h3>", kb + [back]
        return "<p>Неизвестное действие.</p>", [back]

    def describe(self, spec):
        e = f"<b>{esc(spec.get('email'))}</b>"
        k = spec["kind"]
        if k == "issue_access":
            return f"Выдать ключ доступа {e}?", "Будет создан ключ на активной подписке пользователя."
        if k == "issue_plan":
            return f"Выдать тариф «{esc(spec['plan_name'])}» {e}?", "Создаётся подписка по тарифу и сразу выдаётся ключ."
        if k == "reissue":
            return f"Перевыпустить ключ {e}?", "⚠️ Старая ссылка подписки перестанет работать сразу — пользователю нужно обновить подписку в приложении."
        if k == "reset":
            return f"Сбросить израсходованный трафик {e}?", "Счётчик трафика текущего периода обнулится."
        if k == "extend":
            new = self._extended(spec)
            return f"Продлить подписку {e} на {spec['days']} дн?", f"Новая дата окончания: <b>{esc(fmt_dt(new))}</b>."
        if k == "sub_status":
            return (f"Приостановить подписку {e}?", "Ключи перестанут работать до возобновления.") if spec["status"] == "suspended" \
                else (f"Возобновить подписку {e}?", "Ключи снова начнут работать.")
        if k == "disable":
            return f"Заблокировать {e}?", "⚠️ Пользователь не сможет войти, его ключи перестанут работать."
        if k == "enable":
            return f"Разблокировать {e}?", "Вход и ключи снова заработают."
        if k == "revoke_device":
            return f"Отозвать устройство «{esc(spec['device_name'])}» у {e}?", "Устройству придётся войти заново."
        if k == "admin_remove":
            name = next((a.get("name") for a in self.access.admins() if a["id"] == spec["target"]), "")
            return f"Убрать <code>{spec['target']}</code> {esc(name)} из администраторов бота?", "Бот сразу перестанет ему отвечать."
        return "Выполнить действие?", ""

    def confirm_screen(self, tok):
        spec = self.pending.get(tok)
        if not spec:
            return "<p>⌛ Кнопка устарела — откройте экран заново.</p>", [[B("⬅ Меню", "m")]]
        question, detail = self.describe(spec)
        back = "ad" if spec["kind"] == "admin_remove" else f"u:{spec['user']}"
        danger = spec["kind"] in ("disable", "reissue", "revoke_device", "admin_remove") or \
            (spec["kind"] == "sub_status" and spec["status"] == "suspended")
        return (f"<h3>❓ Подтверждение</h3><p>{question}</p>" + (f"<blockquote>{detail}</blockquote>" if detail else ""),
                [[B("✅ Да, выполнить", f"y:{tok}", "danger" if danger else "success"), B("❌ Отмена", back)]])

    def _extended(self, spec):
        current = parse_ts(spec.get("expires")) or 0
        return max(current, time.time()) + spec["days"] * 86400

    def execute(self, tok, uid):
        spec = self.pending.pop(tok, None)
        if not spec:
            return None, "Кнопка устарела — действие не выполнено"
        k = spec["kind"]
        self.log(f"INFO bot: user={uid} executes {k} target_user={spec.get('user') or spec.get('target')}")
        if k == "admin_remove":
            if not self.access.is_owner(uid):
                return None, "Только для владельца"
            self.access.remove(spec["target"])
            self._commands_set.discard(spec["target"])
            try:
                self.tg.delete_commands(chat_id=spec["target"])
            except Exception as e:
                self.log(f"WARN deleteMyCommands {spec['target']}: {e}")
            return self.admins_screen("✅ Администратор удалён."), "Удалено"
        try:
            if k == "issue_access":
                self.core.issue_access(spec["user"]); done = "🔑 Ключ доступа выдан."
            elif k == "issue_plan":
                self.core.issue_subscription(spec["user"], spec["plan"]); done = f"🎁 Выдан тариф «{esc(spec['plan_name'])}»."
            elif k == "reissue":
                self.core.reissue(spec["sub"]); done = "♻️ Ключ перевыпущен — старая ссылка больше не работает."
            elif k == "reset":
                self.core.reset_usage(spec["sub"]); done = "🔄 Трафик сброшен."
            elif k == "extend":
                new = self._extended(spec)
                self.core.set_expiry(spec["sub"], rfc3339(new), "active" if spec.get("status") == "expired" else None)
                done = f"⏩ Продлено до {esc(fmt_dt(new))}."
            elif k == "sub_status":
                self.core.set_subscription_status(spec["sub"], spec["status"])
                done = "⏸ Подписка приостановлена." if spec["status"] == "suspended" else "▶️ Подписка возобновлена."
            elif k == "disable":
                self.core.disable_user(spec["user"]); done = "⛔ Пользователь заблокирован."
            elif k == "enable":
                self.core.enable_user(spec["user"]); done = "✅ Пользователь разблокирован."
            elif k == "revoke_device":
                self.core.revoke_device(spec["device"]); done = f"📱 Устройство «{esc(spec['device_name'])}» отозвано."
            else:
                return None, "Неизвестное действие"
        except CoreError as e:
            return self.user_screen(spec["user"], banner=f"❌ Не получилось: {esc(e)}"), "Ошибка"
        return self.user_screen(spec["user"], banner=done), "Готово"

    # ---------- whitelist management ----------

    def admins_screen(self, banner=None):
        rows = [[f"<code>{self.access.owner_id}</code>", "👑 Владелец", "—"]]
        for a in self.access.admins():
            rows.append([f"<code>{a['id']}</code>", esc(a.get("name") or "—"), esc(fmt_dt(a.get("added_at"), False))])
        html = ((f"<blockquote>{banner}</blockquote>" if banner else "") +
                f"<h3>🛡 Доступ к боту</h3>{table(['Telegram ID', 'Кто', 'Добавлен'], rows)}"
                "<p>Все остальные получают тишину: бот не отвечает и не показывает меню.</p>")
        kb = [[B(f"❌ Убрать {a.get('name') or a['id']}", f"adrm:{a['id']}", "danger")] for a in self.access.admins()]
        kb.append([B("➕ Добавить администратора", "adadd", "success")])
        kb.append([B("⬅ Меню", "m")])
        return html, kb

    def admin_add_from_message(self, owner_uid, msg):
        origin = msg.get("forward_origin") or {}
        fwd = origin.get("sender_user") or msg.get("forward_from")
        if fwd:
            name = " ".join(x for x in (fwd.get("first_name"), fwd.get("last_name")) if x) or fwd.get("username") or ""
            return self.admin_add(owner_uid, fwd["id"], name)
        if origin.get("type") == "hidden_user":
            return ("<p>🙈 У человека скрыт аккаунт при пересылке. Пришлите его числовой ID (@userinfobot).</p>",
                    [[B("➕ Попробовать ещё", "adadd"), B("⬅ Назад", "ad")]])
        text = (msg.get("text") or "").strip().split()
        return self.admin_add(owner_uid, text[0] if text else "", " ".join(text[1:]))

    def admin_add(self, owner_uid, raw_id, name=""):
        try:
            new_id = int(str(raw_id).strip())
            if new_id <= 0:
                raise ValueError
        except ValueError:
            return ("<p>❌ Нужен числовой Telegram ID, например <code>123456789</code>.</p>",
                    [[B("➕ Попробовать ещё", "adadd"), B("⬅ Назад", "ad")]])
        if not self.access.add(new_id, name, owner_uid):
            return self.admins_screen(f"ℹ️ <code>{new_id}</code> уже есть в списке.")
        self.log(f"INFO bot: owner={owner_uid} added admin {new_id} ({name})")
        self.ensure_commands(new_id)
        note = "" if new_id in self._commands_set else " Меню команд появится у него после первого нажатия Start."
        return self.admins_screen(f"✅ <code>{new_id}</code> {esc(name)} добавлен.{note}")

    # ---------- misc ----------

    def help_screen(self, uid):
        cmds = OWNER_COMMANDS if self.access.is_owner(uid) else COMMANDS
        rows = [[f"/{c}", esc(d)] for c, d in cmds]
        return (f"<h3>❔ Команды</h3>{table(['Команда', 'Что делает'], rows)}"
                "<blockquote>Любой текст без / — поиск пользователя по email.</blockquote>",
                [[B("🌊 Меню", "m")]])

    def error_screen(self, err):
        return f"<h3>⚠️ Ошибка</h3><p>{esc(err)}</p>", [[B("⬅ Меню", "m")]]

    # ---------- alerts ----------

    def alert(self, level, text, key=None, cooldown=1800):
        now = time.time()
        if key:
            if now - self._alert_sent.get(key, 0) < cooldown:
                return
            self._alert_sent[key] = now
        icon, title = {"crit": ("🔴", "Авария"), "warn": ("⚠️", "Внимание"), "ok": ("✅", "Восстановлено")}.get(level, ("ℹ️", "Событие"))
        html = f"<h3>{icon} {title}</h3><p>{esc(text)}</p>{footer()}"
        kb = [[B("📊 Мониторинг", "mon", "primary"), B("⚠️ Ошибки", "er"), B("📜 Логи", "lg")]]
        for uid in self.access.ids():
            try:
                self.tg.send(uid, html, kb, silent=(level == "ok"))
            except Exception as e:
                self.log(f"ERROR alert to {uid}: {e}")
