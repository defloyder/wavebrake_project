#!/usr/bin/env python3
"""WaveBreak monitor + ops Telegram bot (entry point).

Runs the host monitoring loops (monitor.py) and the whitelisted Telegram
control panel (bot.py). Config: /etc/wavebreak/telegram.env
  TELEGRAM_BOT_TOKEN    bot token
  TELEGRAM_OWNER_ID     owner's Telegram user id (falls back to TELEGRAM_CHAT_ID)
  CORE_API_URL          e.g. http://127.0.0.1:18080
  CORE_BOT_EMAIL / CORE_BOT_PASSWORD   the bot's own Core admin account
Whitelist of extra admins: /var/lib/wavebreak-monitor/admins.json (managed from the bot).
"""
import os
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import dpi_guard  # noqa: E402
import monitor as mon  # noqa: E402
from access import AccessList  # noqa: E402
from bot import Bot  # noqa: E402
from core import Core  # noqa: E402
from tg import TG, TGError  # noqa: E402

ENV_FILE = "/etc/wavebreak/telegram.env"
ADMINS_FILE = "/var/lib/wavebreak-monitor/admins.json"


def load_env(path=ENV_FILE):
    env = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip()
    return env


def build_bot(env):
    tg = TG(env["TELEGRAM_BOT_TOKEN"], log=mon.log_event)
    owner = env.get("TELEGRAM_OWNER_ID") or env["TELEGRAM_CHAT_ID"]
    access = AccessList(ADMINS_FILE, owner)
    core, core_error = None, None
    if env.get("CORE_API_URL") and env.get("CORE_BOT_EMAIL") and env.get("CORE_BOT_PASSWORD"):
        core = Core(env["CORE_API_URL"], env["CORE_BOT_EMAIL"], env["CORE_BOT_PASSWORD"])
    else:
        core_error = "нет CORE_API_URL / CORE_BOT_EMAIL / CORE_BOT_PASSWORD в telegram.env"
    return Bot(tg, core, access, core_error=core_error)


def poll_loop(bot):
    offset = 0
    while True:
        try:
            for update in bot.tg.get_updates(offset) or []:
                offset = update["update_id"] + 1
                try:
                    bot.handle_update(update)
                except Exception as e:
                    mon.log_event(f"ERROR bot update {update.get('update_id')}: {e}")
        except TGError as e:
            mon.log_event(f"ERROR bot poll: {e}")
            time.sleep(5)
        except Exception as e:
            mon.log_event(f"ERROR bot poll: {e}")
            time.sleep(5)


def main():
    mon.log_event("INFO wavebreak-monitor starting")
    bot = build_bot(load_env())
    bot.sync_commands()
    loops = [
        (mon.tail_container, (mon.XRAY_CONTAINER, "xray", bot.alert)),
        (mon.health_check_loop, (bot.alert,)),
        (mon.traffic_sample_loop, ()),
        (dpi_guard.run_loop, ()),
        (poll_loop, (bot,)),
    ]
    if mon.HY_ENABLED:
        loops.insert(1, (mon.tail_container, (mon.HY_CONTAINER, "hysteria", bot.alert)))
    for target, args in loops:
        threading.Thread(target=target, args=args, daemon=True).start()
    bot.alert("ok", "Монитор запущен — центр управления: /start")
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
