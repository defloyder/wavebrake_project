"""Offline tests for cleanup.py's size parsing and release-mirror junk
detection -- no docker/journald needed. Run: python -m unittest test_cleanup"""
import os
import shutil
import tempfile
import time
import unittest

import cleanup


class ParseSizeTest(unittest.TestCase):
    def test_common_docker_units(self):
        self.assertEqual(cleanup._parse_size("13.37GB"), int(13.37 * 1024**3))
        self.assertEqual(cleanup._parse_size("512MB"), 512 * 1024**2)
        self.assertEqual(cleanup._parse_size("0B"), 0)

    def test_with_space_and_percentage_suffix(self):
        # docker system df's Reclaimable column: "13.37GB (93%)"
        self.assertEqual(cleanup._parse_size("13.37GB (93%)"), int(13.37 * 1024**3))

    def test_garbage_input_is_zero_not_a_crash(self):
        self.assertEqual(cleanup._parse_size(""), 0)
        self.assertEqual(cleanup._parse_size("n/a"), 0)
        self.assertEqual(cleanup._parse_size(None), 0)


class ReleaseMirrorJunkTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self._orig_dir = cleanup.RELEASE_MIRROR_DIR
        cleanup.RELEASE_MIRROR_DIR = self.tmp
        self.addCleanup(setattr, cleanup, "RELEASE_MIRROR_DIR", self._orig_dir)

    def _touch(self, name, age_sec=0, content=b"x" * 1024):
        path = os.path.join(self.tmp, name)
        with open(path, "wb") as f:
            f.write(content)
        if age_sec:
            t = time.time() - age_sec
            os.utime(path, (t, t))
        return path

    def _mkdir(self, name, age_sec=0):
        path = os.path.join(self.tmp, name)
        os.mkdir(path)
        if age_sec:
            t = time.time() - age_sec
            os.utime(path, (t, t))
        return path

    def test_no_release_mirror_dir_is_empty_not_an_error(self):
        cleanup.RELEASE_MIRROR_DIR = os.path.join(self.tmp, "does-not-exist")
        total, detail = cleanup._release_mirror_junk()
        self.assertEqual((total, detail), (0, []))

    def test_fresh_incoming_dir_is_not_stale(self):
        self._mkdir("incoming-20261015-1200", age_sec=60)
        total, detail = cleanup._release_mirror_junk()
        self.assertEqual((total, detail), (0, []))

    def test_old_incoming_dir_is_stale(self):
        self._mkdir("incoming-20261001-0000",
                     age_sec=cleanup.INCOMING_STALE_AFTER_SEC + 3600)
        total, detail = cleanup._release_mirror_junk()
        self.assertEqual(len(detail), 1)
        self.assertEqual(detail[0][0], "rmtree")
        self.assertTrue(detail[0][1].endswith("incoming-20261001-0000"))

    def test_only_newest_bak_generation_is_kept(self):
        self._touch("app.apk.bak-before-20261001-0000", age_sec=1000000)
        self._touch("app.apk.bak-before-20261010-0000", age_sec=500000)
        self._touch("app.apk.bak-before-20261015-0000", age_sec=100)
        total, detail = cleanup._release_mirror_junk()
        removed = sorted(os.path.basename(p) for _, p, _ in detail)
        self.assertEqual(removed, [
            "app.apk.bak-before-20261001-0000",
            "app.apk.bak-before-20261010-0000",
        ])
        self.assertEqual(total, 2048)  # two 1KB files

    def test_single_generation_is_never_removed(self):
        self._touch("app.apk.bak-before-20261015-0000")
        total, detail = cleanup._release_mirror_junk()
        self.assertEqual((total, detail), (0, []))

    def test_current_release_files_are_never_touched(self):
        self._touch("wavebreak-android.apk")
        self._touch("wavebreak-android-rollback-1.3.5.apk")
        self._touch("version.json")
        total, detail = cleanup._release_mirror_junk()
        self.assertEqual((total, detail), (0, []))


class ScanTest(unittest.TestCase):
    def test_scan_only_lists_release_mirror_when_dir_exists(self):
        with tempfile.TemporaryDirectory() as tmp:
            missing = os.path.join(tmp, "nope")
            orig = cleanup.RELEASE_MIRROR_DIR
            cleanup.RELEASE_MIRROR_DIR = missing
            try:
                ids = {item["id"] for item in cleanup.scan()}
            finally:
                cleanup.RELEASE_MIRROR_DIR = orig
        self.assertNotIn("release_mirror", ids)
        self.assertEqual(ids, {"docker", "journal", "apt"})


if __name__ == "__main__":
    unittest.main()
