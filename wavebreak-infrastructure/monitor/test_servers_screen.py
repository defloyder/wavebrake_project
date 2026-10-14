import unittest
from unittest.mock import patch

import bot

FAKE_LOCAL = {"hostname": "tr", "load": ["0", "0", "0"], "cpus": 2,
              "mem_total": 2_000_000_000, "mem_avail": 1_000_000_000,
              "disk_total": 100_000_000_000, "disk_used": 40_000_000_000, "uptime": 1.0}

FAKE_REMOTE = {"hostname": "ru-msk", "load": ["0", "0", "0"], "cpus": 4,
               "mem_total": 4_000_000_000, "mem_avail": 500_000_000,
               "disk_total": 50_000_000_000, "disk_used": 45_000_000_000, "uptime": 1.0}


class ServersScreenTest(unittest.TestCase):
    def test_renders_local_and_reachable_remote(self):
        with patch("bot.mon.load_snapshot", return_value=FAKE_LOCAL), \
             patch("bot.fetch_remote_metrics",
                    side_effect=[FAKE_REMOTE, None, FAKE_REMOTE]):
            html, kb = bot.Bot.servers_screen(None)
        self.assertIn("TR-PILOT-01", html)
        self.assertIn("RU-MSK-01", html)
        self.assertIn("недоступен", html)  # DE-NR-01 returned None
        self.assertIn("RU-LTE-01", html)
        self.assertTrue(kb)

    def test_all_remote_unreachable_does_not_crash(self):
        with patch("bot.mon.load_snapshot", return_value=FAKE_LOCAL), \
             patch("bot.fetch_remote_metrics", return_value=None):
            html, _ = bot.Bot.servers_screen(None)
        self.assertEqual(html.count("недоступен"), len(bot.REMOTE_SERVERS))


class FetchRemoteMetricsTest(unittest.TestCase):
    def test_returns_none_on_connection_error(self):
        with patch("bot.urllib.request.urlopen", side_effect=OSError("refused")):
            self.assertIsNone(bot.fetch_remote_metrics("10.66.0.4", 8787))


if __name__ == "__main__":
    unittest.main()
