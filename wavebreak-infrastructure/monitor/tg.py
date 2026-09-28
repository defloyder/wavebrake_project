"""Minimal Telegram Bot API client (stdlib only).

Every reply goes out as a Rich Message (Bot API 10.1+, full-width layout).
If Telegram rejects the rich payload, the same content is re-sent as a
plain-text fallback so an operator never ends up with no answer at all.
"""
import json
import re
import urllib.error
import urllib.request

API = "https://api.telegram.org/bot{token}/{method}"


class TGError(Exception):
    pass


class TG:
    def __init__(self, token, log=print, opener=urllib.request.urlopen):
        self.token = token
        self.log = log
        self._open = opener

    def call(self, method, payload=None, timeout=35):
        req = urllib.request.Request(
            API.format(token=self.token, method=method),
            data=json.dumps(payload or {}).encode(),
            headers={"Content-Type": "application/json"},
        )
        try:
            with self._open(req, timeout=timeout) as resp:
                body = json.loads(resp.read())
        except urllib.error.HTTPError as e:
            try:
                body = json.loads(e.read())
            except Exception:
                raise TGError(f"{method}: HTTP {e.code}") from None
        except Exception as e:
            raise TGError(f"{method}: {e}") from None
        if not body.get("ok"):
            raise TGError(f"{method}: {body.get('description', 'unknown error')}")
        return body.get("result")

    # ---------- messages ----------

    def send(self, chat_id, html, keyboard=None, silent=False):
        payload = {"chat_id": int(chat_id), "rich_message": {"html": html}}
        if keyboard:
            payload["reply_markup"] = {"inline_keyboard": keyboard}
        if silent:
            payload["disable_notification"] = True
        try:
            return self.call("sendRichMessage", payload)
        except TGError as e:
            self.log(f"WARN sendRichMessage failed, plain fallback: {e}")
            return self._send_plain(chat_id, html, keyboard, silent)

    def edit(self, chat_id, message_id, html, keyboard=None):
        payload = {"chat_id": int(chat_id), "message_id": int(message_id), "rich_message": {"html": html}}
        if keyboard:
            payload["reply_markup"] = {"inline_keyboard": keyboard}
        try:
            return self.call("editMessageText", payload)
        except TGError as e:
            if "not modified" in str(e):
                return None
            # Message too old / deleted / not a rich message: answer anew.
            self.log(f"WARN edit failed, sending new message: {e}")
            return self.send(chat_id, html, keyboard)

    def _send_plain(self, chat_id, html, keyboard, silent):
        payload = {"chat_id": int(chat_id), "text": html_to_text(html)[:4000]}
        if keyboard:
            payload["reply_markup"] = {"inline_keyboard": keyboard}
        if silent:
            payload["disable_notification"] = True
        try:
            return self.call("sendMessage", payload)
        except TGError as e:
            self.log(f"ERROR plain send failed: {e}")
            return None

    def answer(self, callback_id, text=None, alert=False):
        payload = {"callback_query_id": callback_id}
        if text:
            payload["text"] = text[:200]
            payload["show_alert"] = alert
        try:
            self.call("answerCallbackQuery", payload, timeout=10)
        except TGError as e:
            self.log(f"WARN answerCallbackQuery: {e}")

    def send_document(self, chat_id, filename, content):
        boundary = "wavebreakboundary7f3a"
        parts = [
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n{chat_id}\r\n".encode(),
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"document\"; filename=\"{filename}\"\r\n"
            f"Content-Type: text/plain\r\n\r\n".encode(),
            content.encode(),
            f"\r\n--{boundary}--\r\n".encode(),
        ]
        req = urllib.request.Request(
            API.format(token=self.token, method="sendDocument"), data=b"".join(parts),
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        )
        try:
            with self._open(req, timeout=30):
                pass
        except Exception as e:
            self.log(f"ERROR sendDocument failed: {e}")

    # ---------- command menu ----------

    def set_commands(self, commands, chat_id=None):
        """commands: list of (command, description). chat_id=None → default scope."""
        payload = {"commands": [{"command": c, "description": d} for c, d in commands]}
        if chat_id is not None:
            payload["scope"] = {"type": "chat", "chat_id": int(chat_id)}
        self.call("setMyCommands", payload, timeout=15)

    def delete_commands(self, chat_id=None):
        payload = {}
        if chat_id is not None:
            payload["scope"] = {"type": "chat", "chat_id": int(chat_id)}
        self.call("deleteMyCommands", payload, timeout=15)

    def get_updates(self, offset, timeout=25):
        return self.call("getUpdates", {
            "offset": offset, "timeout": timeout,
            "allowed_updates": ["message", "callback_query"],
        }, timeout=timeout + 10)


def html_to_text(html):
    """Crude rich-HTML → plain text for the fallback path."""
    s = re.sub(r"</(tr|p|h\d|li|pre|blockquote|details|summary|footer|caption)>", "\n", html)
    s = re.sub(r"<br\s*/?>|<hr\s*/?>", "\n", s)
    s = re.sub(r"</t[dh]>", " | ", s)
    s = re.sub(r"<[^>]+>", "", s)
    s = s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"').replace("&amp;", "&")
    return re.sub(r"\n{3,}", "\n\n", s).strip()


def button(text, data=None, style=None, url=None, copy=None):
    b = {"text": text}
    if data is not None:
        b["callback_data"] = data
    elif url is not None:
        b["url"] = url
    elif copy is not None:
        b["copy_text"] = {"text": copy}
    if style:
        b["style"] = style
    return b
