"""Offline tests for dpi_guard's ban decision — no docker/ipset needed.
Run: python -m unittest test_dpi_guard  (from this directory)"""
import unittest
import unittest.mock

import dpi_guard


class FakeClock:
    def __init__(self, start=0.0):
        self.t = start

    def __call__(self):
        return self.t

    def advance(self, seconds):
        self.t += seconds


class GuardTest(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock()
        self.banned = []
        self.escalated = []
        self.guard = dpi_guard.Guard(
            now_fn=self.clock, ban_fn=self.banned.append, escalate_fn=self.escalated.append
        )

    def _trigger_ban(self, ip):
        """One full short-session-flood cycle against ip -- exactly one ban."""
        for _ in range(dpi_guard.MIN_CONNECTIONS):
            self.guard.observe(ip, duration=0.1)
            self.clock.advance(1)

    def test_real_nat_pool_is_not_banned(self):
        """Many different real sessions behind one carrier-NAT IP, each held
        open for a normal duration — exactly what flagged the old pure-count
        rule as a false positive against Beeline/Rostelecom pools."""
        for _ in range(40):
            self.guard.observe("128.71.233.198", duration=45.0)
            self.clock.advance(1)
        self.assertEqual(self.banned, [])

    def test_short_session_flood_is_banned(self):
        """Same connection rate, but every session closes almost immediately
        — the actual probing signature."""
        for _ in range(20):
            self.guard.observe("203.0.113.9", duration=0.1)
            self.clock.advance(1)
        self.assertEqual(self.banned, ["203.0.113.9"])

    def test_mixed_short_and_long_under_threshold_not_banned(self):
        """A few short sessions mixed into mostly-normal traffic shouldn't
        trip the ban — real clients do sometimes reconnect quickly."""
        for i in range(20):
            self.guard.observe("198.51.100.5", duration=0.1 if i % 3 == 0 else 30.0)
            self.clock.advance(1)
        self.assertEqual(self.banned, [])

    def test_below_minimum_connection_count_not_banned(self):
        """All-short sessions, but too few of them to distinguish from noise."""
        for _ in range(5):
            self.guard.observe("203.0.113.9", duration=0.05)
            self.clock.advance(1)
        self.assertEqual(self.banned, [])

    def test_old_events_fall_out_of_the_window(self):
        for _ in range(14):
            self.guard.observe("203.0.113.9", duration=0.1)
            self.clock.advance(1)
        self.clock.advance(dpi_guard.WINDOW_SEC)  # everything above is now stale
        for _ in range(14):
            self.guard.observe("203.0.113.9", duration=0.1)
            self.clock.advance(1)
        self.assertEqual(self.banned, [])  # only 14 in-window each time, below MIN_CONNECTIONS

    def test_separate_ips_tracked_independently(self):
        for _ in range(20):
            self.guard.observe("203.0.113.9", duration=0.1)
            self.guard.observe("198.51.100.5", duration=30.0)
            self.clock.advance(1)
        self.assertEqual(self.banned, ["203.0.113.9"])

    def test_pruning_forgets_stale_ips_without_crashing(self):
        self.guard.observe("203.0.113.9", duration=1.0)
        self.clock.advance(dpi_guard.PRUNE_INTERVAL_SEC + dpi_guard.WINDOW_SEC + 1)
        self.guard.observe("198.51.100.5", duration=1.0)  # triggers the prune path
        self.assertNotIn("203.0.113.9", self.guard._events)

    def test_repeat_offender_is_escalated(self):
        """Same IP re-triggers the short-session-flood ban
        REPEAT_BAN_THRESHOLD times within REPEAT_BAN_WINDOW_SEC -- a bot that
        keeps coming back the moment its 5-minute ban expires."""
        for _ in range(dpi_guard.REPEAT_BAN_THRESHOLD):
            self._trigger_ban("203.0.113.9")
            self.clock.advance(10)  # well under REPEAT_BAN_WINDOW_SEC apart
        self.assertEqual(self.banned.count("203.0.113.9"), dpi_guard.REPEAT_BAN_THRESHOLD)
        self.assertEqual(self.escalated, ["203.0.113.9"])

    def test_below_repeat_threshold_not_escalated(self):
        """A single confirmed probe, or even two, isn't a pattern yet --
        only the long-ban/CGNAT-unfriendly step needs real confidence."""
        for _ in range(dpi_guard.REPEAT_BAN_THRESHOLD - 1):
            self._trigger_ban("203.0.113.9")
            self.clock.advance(10)
        self.assertEqual(self.escalated, [])

    def test_offenses_outside_the_window_do_not_accumulate(self):
        """Three bans, but spread out well beyond REPEAT_BAN_WINDOW_SEC --
        this is occasional bad luck (or a long-lived prober's slow retries),
        not the tight repeat pattern escalation is meant to catch."""
        for _ in range(dpi_guard.REPEAT_BAN_THRESHOLD):
            self._trigger_ban("203.0.113.9")
            self.clock.advance(dpi_guard.REPEAT_BAN_WINDOW_SEC + 1)
        self.assertEqual(self.escalated, [])

    def test_escalation_does_not_repeat_every_ban_after_threshold(self):
        """Crossing the threshold escalates once; it shouldn't re-fire on
        every subsequent ban for the same still-offending IP."""
        for _ in range(dpi_guard.REPEAT_BAN_THRESHOLD + 2):
            self._trigger_ban("203.0.113.9")
            self.clock.advance(10)
        self.assertEqual(self.escalated, ["203.0.113.9"])

    def test_repeat_offenses_tracked_independently_per_ip(self):
        for _ in range(dpi_guard.REPEAT_BAN_THRESHOLD):
            self._trigger_ban("203.0.113.9")
            self.clock.advance(10)
        for _ in range(dpi_guard.REPEAT_BAN_THRESHOLD - 1):
            self._trigger_ban("198.51.100.5")
            self.clock.advance(10)
        self.assertEqual(self.escalated, ["203.0.113.9"])


    def test_allowlisted_relay_is_never_banned(self):
        """Our own relay: many short sessions from it must not ban or escalate."""
        relay = next(iter(dpi_guard.ALLOWLIST))
        for _ in range(dpi_guard.MIN_CONNECTIONS * 5):
            self.guard.observe(relay, duration=0.1)
            self.clock.advance(1)
        self.assertEqual(self.banned, [])
        self.assertEqual(self.escalated, [])


    def test_person_with_recent_long_session_is_not_banned(self):
        """A real phone held one long session, then its app retried in a burst:
        the burst alone must not ban it."""
        ip = "5.228.113.146"
        self.guard.observe(ip, duration=120.0)
        self.clock.advance(1)
        for _ in range(dpi_guard.MIN_CONNECTIONS):
            self.guard.observe(ip, duration=0.1)
            self.clock.advance(1)
        self.assertEqual(self.banned, [])

    def test_pure_prober_without_long_sessions_still_banned(self):
        ip = "203.0.113.50"
        for _ in range(dpi_guard.MIN_CONNECTIONS):
            self.guard.observe(ip, duration=0.1)
            self.clock.advance(1)
        self.assertEqual(self.banned, [ip])


class AlertWiringTest(unittest.TestCase):
    """run_loop's ban_and_alert/escalate_and_alert (owner, 15.10): a real
    ban/escalation reaches Telegram, not only the local events.log."""

    def setUp(self):
        self.alerts = []
        self.ban_patch = unittest.mock.patch.object(dpi_guard, "ban")
        self.escalate_patch = unittest.mock.patch.object(dpi_guard, "escalate")
        self.mock_ban = self.ban_patch.start()
        self.mock_escalate = self.escalate_patch.start()
        self.addCleanup(self.ban_patch.stop)
        self.addCleanup(self.escalate_patch.stop)

    def _alert(self, level, text, key=None, cooldown=1800):
        self.alerts.append((level, text, key))

    def test_ban_still_bans_and_also_alerts(self):
        dpi_guard.ban_and_alert("203.0.113.9", self._alert)
        self.mock_ban.assert_called_once_with("203.0.113.9")
        self.assertEqual(len(self.alerts), 1)
        level, text, key = self.alerts[0]
        self.assertEqual(level, "warn")
        self.assertIn("203.0.113.9", text)
        self.assertEqual(key, "dpi_ban_203.0.113.9")

    def test_escalate_still_escalates_and_also_alerts_crit(self):
        dpi_guard.escalate_and_alert("203.0.113.9", self._alert)
        self.mock_escalate.assert_called_once_with("203.0.113.9")
        self.assertEqual(len(self.alerts), 1)
        level, text, key = self.alerts[0]
        self.assertEqual(level, "crit")
        self.assertIn("203.0.113.9", text)
        self.assertEqual(key, "dpi_escalate_203.0.113.9")

    def test_no_alert_callback_still_bans_without_crashing(self):
        dpi_guard.ban_and_alert("203.0.113.9")
        dpi_guard.escalate_and_alert("203.0.113.9")
        self.mock_ban.assert_called_once_with("203.0.113.9")
        self.mock_escalate.assert_called_once_with("203.0.113.9")


if __name__ == "__main__":
    unittest.main()
