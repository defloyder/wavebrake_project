"""Client for the WaveBreak Core admin API (same endpoints the admin panel uses).

The bot signs in as its own Core account (role admin), so every change it
makes lands in Core's audit log under that account.
"""
import json
import threading
import time
import urllib.error
import urllib.parse
import urllib.request


class CoreError(Exception):
    def __init__(self, message, status=None):
        super().__init__(message)
        self.status = status


class Core:
    def __init__(self, base_url, email, password, opener=urllib.request.urlopen):
        self.base = base_url.rstrip("/")
        self.email = email
        self.password = password
        self._open = opener
        self._token = None
        self._token_exp = 0
        self._lock = threading.Lock()

    # ---------- transport ----------

    def _raw(self, method, path, body=None, token=None, query=None, timeout=15):
        url = self.base + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        headers = {"Accept": "application/json"}
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        if token:
            headers["Authorization"] = f"Bearer {token}"
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with self._open(req, timeout=timeout) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            raise CoreError(_error_message(e), e.code) from None
        except Exception as e:
            raise CoreError(f"Core недоступен: {e}") from None

    def _auth_token(self, force=False):
        with self._lock:
            if force or not self._token or time.time() > self._token_exp - 60:
                res = self._raw("POST", "/v1/auth/login", {"email": self.email, "password": self.password})
                self._token = res["access_token"]
                self._token_exp = time.time() + int(res.get("expires_in") or 600)
            return self._token

    def request(self, method, path, body=None, query=None):
        try:
            return self._raw(method, path, body, self._auth_token(), query)
        except CoreError as e:
            if e.status != 401:
                raise
            return self._raw(method, path, body, self._auth_token(force=True), query)

    # ---------- reads ----------

    def health(self):
        try:
            return self._raw("GET", "/healthz", timeout=5)
        except CoreError as e:
            return {"status": "down", "error": str(e)}

    def dashboard(self):
        return self.request("GET", "/v1/admin/dashboard")

    def users(self):
        return self.request("GET", "/v1/admin/users").get("users") or []

    def user(self, user_id):
        return self.request("GET", "/v1/admin/users/" + urllib.parse.quote(user_id, safe=""))

    def plans(self):
        return self.request("GET", "/v1/admin/plans").get("plans") or []

    def subscriptions(self):
        return self.request("GET", "/v1/admin/subscriptions").get("subscriptions") or []

    def grants(self):
        return self.request("GET", "/v1/admin/access/grants").get("grants") or []

    def nodes(self):
        return self.request("GET", "/v1/nodes").get("nodes") or []

    def audit(self):
        return self.request("GET", "/v1/admin/audit").get("events") or []

    def traffic(self):
        return self.request("GET", "/v1/admin/traffic").get("traffic") or []

    # ---------- actions ----------

    def issue_access(self, user_id):
        return self.request("POST", f"/v1/admin/users/{_q(user_id)}/access")

    def issue_subscription(self, user_id, plan_id):
        return self.request("POST", f"/v1/admin/users/{_q(user_id)}/subscriptions", {"plan_id": plan_id})

    def set_expiry(self, subscription_id, expires_at_iso, status=None):
        # Only the given fields are sent: Core keeps every other field as-is
        # (traffic_unlimited=false + null limit = "leave traffic alone").
        body = {"expires_at": expires_at_iso, "traffic_unlimited": False}
        if status:
            body["status"] = status
        return self.request("PATCH", f"/v1/admin/subscriptions/{_q(subscription_id)}", body)

    def set_subscription_status(self, subscription_id, status):
        return self.request("PATCH", f"/v1/admin/subscriptions/{_q(subscription_id)}",
                            {"status": status, "traffic_unlimited": False})

    def reset_usage(self, subscription_id):
        return self.request("POST", f"/v1/admin/subscriptions/{_q(subscription_id)}/reset-usage")

    def reissue(self, subscription_id):
        return self.request("POST", f"/v1/admin/subscriptions/{_q(subscription_id)}/reissue")

    def disable_user(self, user_id):
        return self.request("POST", f"/v1/admin/users/{_q(user_id)}/disable")

    def enable_user(self, user_id):
        return self.request("POST", f"/v1/admin/users/{_q(user_id)}/enable")

    def revoke_grant(self, grant_id, reason="telegram-bot"):
        return self.request("POST", f"/v1/admin/access/grants/{_q(grant_id)}/revoke", {"reason": reason})

    def revoke_device(self, device_id):
        return self.request("POST", f"/v1/admin/devices/{_q(device_id)}/revoke")


def _q(value):
    return urllib.parse.quote(str(value), safe="")


def _error_message(http_error):
    try:
        body = json.loads(http_error.read())
    except Exception:
        return f"Core ответил HTTP {http_error.code}"
    err = body.get("error")
    if isinstance(err, dict):
        return err.get("message") or err.get("code") or f"HTTP {http_error.code}"
    if isinstance(err, str):
        return err
    return body.get("message") or f"HTTP {http_error.code}"
