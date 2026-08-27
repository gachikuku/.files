from __future__ import annotations

import io
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

from mitmproxy import http
from mitmproxy.test import tflow

from flowhunter.cli import main
from flowhunter.core import snapshot_from_flow
from flowhunter.storage import Storage


class WatchTests(unittest.TestCase):
    def test_watch_is_not_silent_before_first_finding(self) -> None:
        with tempfile.TemporaryDirectory() as data_dir:
            output = io.StringIO()
            with (
                redirect_stdout(output),
                patch("flowhunter.cli.time.sleep", side_effect=KeyboardInterrupt),
            ):
                result = main(["--data-dir", data_dir, "watch", "--interval", ".5"])

        self.assertEqual(result, 0)
        self.assertIn("FlowHunter watching", output.getvalue())

    def test_watch_prints_captured_endpoint_activity(self) -> None:
        with tempfile.TemporaryDirectory() as data_dir:
            request = http.Request.make("GET", "https://api.example.com/items/123")
            response = http.Response.make(200, '{"ok":true}')
            Storage(data_dir).record_endpoint(
                snapshot_from_flow(tflow.tflow(req=request, resp=response))
            )
            output = io.StringIO()
            with (
                redirect_stdout(output),
                patch("flowhunter.cli.time.sleep", side_effect=KeyboardInterrupt),
            ):
                main(["--data-dir", data_dir, "watch", "--interval", ".5"])

        self.assertIn("[endpoint]", output.getvalue())
        self.assertIn("api.example.com/items/{int}", output.getvalue())


if __name__ == "__main__":
    unittest.main()
