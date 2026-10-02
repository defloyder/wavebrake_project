"""Offline tests for dpi_guard's ban decision — no docker/ipset needed.
Run: python -m unittest test_dpi_guard  (from this directory)"""
import unittest

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
        self.guard = dpi_guard.Guard(now_fn=self.clock, ban_fn=self.banned.append)

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


if __name__ == "__main__":
    unittest.main()
