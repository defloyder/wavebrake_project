import json
import threading
import unittest
import urllib.error
import urllib.request
from http.server import HTTPServer
from unittest.mock import patch

import remote_metrics as rm


class LoadSnapshotTest(unittest.TestCase):
    def test_parses_proc_and_df_output(self):
        fakes = {
            ("cat", "/proc/loadavg"): "0.10 0.20 0.15 1/234 5678\n",
            ("cat", "/proc/meminfo"): "MemTotal:       1000000 kB\nMemAvailable:    400000 kB\n",
            ("hostname",): "wavebreak-test\n",
            ("cat", "/proc/uptime"): "12345.6 999.0\n",
        }

        def fake_run(cmd, timeout=5):
            key = tuple(cmd) if tuple(cmd) != ("df", "-B1", "/") else None
            if key in fakes:
                return fakes[key]
            if cmd == ["df", "-B1", "/"]:
                return "Filesystem 1B-blocks Used Available Use% Mounted\n/dev/sda1 10000000000 4000000000 6000000000 40% /\n"
            return ""

        with patch("remote_metrics.run", side_effect=fake_run):
            snap = rm.load_snapshot()
        self.assertEqual(snap["hostname"], "wavebreak-test")
        self.assertEqual(snap["mem_total"], 1000000 * 1024)
        self.assertEqual(snap["mem_avail"], 400000 * 1024)
        self.assertEqual(snap["disk_total"], 10000000000)
        self.assertEqual(snap["disk_used"], 4000000000)
        self.assertEqual(snap["load"][:2], ["0.10", "0.20"])


FAKE_SNAPSHOT = {"hostname": "x", "load": ["0", "0", "0"], "cpus": 1,
                  "mem_total": 1, "mem_avail": 1, "disk_total": 1, "disk_used": 1, "uptime": 1.0}


class HttpHandlerTest(unittest.TestCase):
    @patch("remote_metrics.load_snapshot", return_value=FAKE_SNAPSHOT)
    def test_metrics_endpoint_serves_json(self, _mock):
        server = HTTPServer(("127.0.0.1", 0), rm.Handler)
        port = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/metrics", timeout=5) as r:
                data = json.loads(r.read())
            self.assertIn("mem_total", data)
            self.assertIn("disk_total", data)
        finally:
            server.shutdown()
            thread.join(timeout=2)

    def test_unknown_path_is_404(self):
        server = HTTPServer(("127.0.0.1", 0), rm.Handler)
        port = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(f"http://127.0.0.1:{port}/other", timeout=5)
            self.assertEqual(ctx.exception.code, 404)
        finally:
            server.shutdown()
            thread.join(timeout=2)


FAKE_SCAN = [{"id": "docker", "label": "Docker", "bytes": 123}]
FAKE_RUN_RESULT = {"freed_bytes": 456, "ran": ["docker"], "errors": []}


class CleanupEndpointTest(unittest.TestCase):
    @patch("remote_metrics.cleanup.scan", return_value=FAKE_SCAN)
    def test_scan_endpoint_serves_json(self, _mock):
        server = HTTPServer(("127.0.0.1", 0), rm.Handler)
        port = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/cleanup/scan", timeout=5) as r:
                data = json.loads(r.read())
            self.assertEqual(data, {"items": FAKE_SCAN})
        finally:
            server.shutdown()
            thread.join(timeout=2)

    @patch("remote_metrics.cleanup.run", return_value=FAKE_RUN_RESULT)
    def test_run_endpoint_passes_ids_and_serves_result(self, mock_run):
        server = HTTPServer(("127.0.0.1", 0), rm.Handler)
        port = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            body = json.dumps({"ids": ["docker", "journal"]}).encode()
            req = urllib.request.Request(
                f"http://127.0.0.1:{port}/cleanup/run", data=body,
                headers={"Content-Type": "application/json"}, method="POST")
            with urllib.request.urlopen(req, timeout=5) as r:
                data = json.loads(r.read())
            self.assertEqual(data, FAKE_RUN_RESULT)
            mock_run.assert_called_once_with(["docker", "journal"])
        finally:
            server.shutdown()
            thread.join(timeout=2)

    def test_run_endpoint_rejects_malformed_body(self):
        server = HTTPServer(("127.0.0.1", 0), rm.Handler)
        port = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            req = urllib.request.Request(
                f"http://127.0.0.1:{port}/cleanup/run", data=b"not json",
                headers={"Content-Type": "application/json"}, method="POST")
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(req, timeout=5)
            self.assertEqual(ctx.exception.code, 400)
        finally:
            server.shutdown()
            thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
