"""Offline tests for the memory/disk resource watchdog (owner, 15.10) --
no docker/network needed. Run: python -m unittest test_resource_watch"""
import unittest

import bot


def _snapshot(mem_total, mem_avail, disk_total, disk_used):
    return {"mem_total": mem_total, "mem_avail": mem_avail,
            "disk_total": disk_total, "disk_used": disk_used}


HEALTHY = _snapshot(2_000_000_000, 1_000_000_000, 100_000_000_000, 40_000_000_000)
MEM_LOW = _snapshot(1_000_000_000, 50_000_000, 10_000_000_000, 4_000_000_000)  # 5% mem free
DISK_LOW = _snapshot(1_000_000_000, 500_000_000, 10_000_000_000, 9_500_000_000)  # 5% disk free
# 88% disk used / 12% free -- below the 15%-free (>85% used) threshold
# (owner, 15.10) but would NOT have tripped the old 10%-free one.
DISK_88_PCT = _snapshot(1_000_000_000, 500_000_000, 10_000_000_000, 8_800_000_000)


class ResourceRatiosTest(unittest.TestCase):
    def test_healthy_snapshot_ratios(self):
        mem_ratio, disk_ratio = bot.resource_ratios(HEALTHY)
        self.assertAlmostEqual(mem_ratio, 0.5)
        self.assertAlmostEqual(disk_ratio, 0.6)

    def test_missing_totals_read_as_fine_not_critical(self):
        # A malformed/partial snapshot (bad JSON key, zeroed field) must
        # never look like 0% free -- that would cry wolf on every restart
        # of remote_metrics.py, not just a real shortage.
        mem_ratio, disk_ratio = bot.resource_ratios({})
        self.assertEqual((mem_ratio, disk_ratio), (1.0, 1.0))


class CheckResourcesTest(unittest.TestCase):
    def setUp(self):
        self.alerts = []
        self.last_low = {}

    def _alert(self, level, text, key=None, cooldown=1800):
        self.alerts.append((level, text, key))

    def test_healthy_server_never_alerts(self):
        bot.check_resources("TR-PILOT-01", HEALTHY, self._alert, self.last_low)
        self.assertEqual(self.alerts, [])

    def test_low_memory_alerts_once_on_the_crossing(self):
        bot.check_resources("RU-MSK-01", MEM_LOW, self._alert, self.last_low)
        self.assertEqual(len(self.alerts), 1)
        level, text, key = self.alerts[0]
        self.assertEqual(level, "warn")
        self.assertIn("RU-MSK-01", text)
        self.assertIn("памяти", text)
        self.assertEqual(key, "mem_low_RU-MSK-01")

    def test_staying_low_does_not_alert_again(self):
        bot.check_resources("RU-MSK-01", MEM_LOW, self._alert, self.last_low)
        bot.check_resources("RU-MSK-01", MEM_LOW, self._alert, self.last_low)
        bot.check_resources("RU-MSK-01", MEM_LOW, self._alert, self.last_low)
        self.assertEqual(len(self.alerts), 1)

    def test_recovery_sends_one_ok_alert(self):
        bot.check_resources("RU-MSK-01", MEM_LOW, self._alert, self.last_low)
        bot.check_resources("RU-MSK-01", HEALTHY, self._alert, self.last_low)
        self.assertEqual(len(self.alerts), 2)
        self.assertEqual(self.alerts[1][0], "ok")

    def test_low_disk_alerts_independently_of_memory(self):
        bot.check_resources("RU-LTE-01", DISK_LOW, self._alert, self.last_low)
        self.assertEqual(len(self.alerts), 1)
        self.assertIn("диске", self.alerts[0][1])

    def test_disk_threshold_is_85_percent_used_not_90(self):
        # owner, 15.10: explicitly asked for an alert above 85% disk used.
        bot.check_resources("TR-PILOT-01", DISK_88_PCT, self._alert, self.last_low)
        self.assertEqual(len(self.alerts), 1)

    def test_missing_snapshot_is_skipped_silently(self):
        # Already has its own "недоступен" row on the servers screen --
        # this loop piling on a second alert for the same fact would just
        # be noise, not new information.
        bot.check_resources("DE-NR-01", None, self._alert, self.last_low)
        self.assertEqual(self.alerts, [])

    def test_each_server_tracked_independently(self):
        bot.check_resources("RU-MSK-01", MEM_LOW, self._alert, self.last_low)
        bot.check_resources("DE-NR-01", HEALTHY, self._alert, self.last_low)
        self.assertEqual(len(self.alerts), 1)
        self.assertIn("RU-MSK-01", self.alerts[0][1])


if __name__ == "__main__":
    unittest.main()
