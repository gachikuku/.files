#!/run/current-system/sw/bin/python3
"""Offline regression checks for sleep after an already-closed-lid turn.

Every process and power-management boundary is mocked. These tests never
change the Mac's power settings, run a subprocess, or signal a real process.
"""

from __future__ import annotations

from contextlib import ExitStack, redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


class FakeProcess:
    pid = 900001

    def poll(self):
        return None


class ClosedLidTests(unittest.TestCase):
    def setUp(self):
        sys.dont_write_bytecode = True
        module_path = (
            Path(__file__).resolve().parents[2]
            / "codex/.codex/hooks/caffeinate_control.py"
        )
        spec = importlib.util.spec_from_file_location("closed_lid_control", module_path)
        self.control = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.control)

        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        temporary = self.stack.enter_context(
            tempfile.TemporaryDirectory(prefix="codex-awake-closed-lid-")
        )
        self.control.STATE_ROOT = Path(temporary)
        self.control.LOCK_PATH = self.control.STATE_ROOT / "lock"
        self.control.LID_STATE_PATH = self.control.STATE_ROOT / "lid-controller.json"
        self.control.LID_SLEEP_PATH = self.control.STATE_ROOT / "lid-sleep.json"
        self.mode = "lid"
        self.closed = True
        self.disabled = False
        self.power_query_failed = False
        self.power_state_missing = False
        self.pending_workers = []
        self.sleep_requests = []

        self.stack.enter_context(patch.object(self.control, "selected_mode", lambda: self.mode))
        self.stack.enter_context(patch.object(self.control, "codex_owner", lambda: (1234, "codex test-owner")))
        self.stack.enter_context(patch.object(self.control, "process_command", lambda pid: "codex test-owner" if pid == 1234 else None))
        self.stack.enter_context(patch.object(self.control, "start_lid_controller", return_value=900002))
        self.stack.enter_context(patch.object(self.control.time, "sleep"))
        self.stack.enter_context(patch.object(self.control.subprocess, "run", side_effect=self.run_process))
        self.stack.enter_context(patch.object(self.control.subprocess, "Popen", side_effect=self.spawn_process))
        self.stack.enter_context(patch.object(self.control.os, "kill", side_effect=AssertionError("unexpected process signal")))

    def run_process(self, arguments, **kwargs):
        arguments = list(arguments)
        if arguments == ["/usr/bin/sudo", "-n", "--", "/usr/bin/pmset", "sleepnow"]:
            self.sleep_requests.append(arguments)
            return subprocess.CompletedProcess(arguments, 0, "", "")
        if Path(arguments[0]).name == "ioreg":
            state = {"AppleClamshellState": self.closed}
            if not self.power_state_missing:
                state["SleepDisabled"] = self.disabled
            output = plistlib.dumps([state])
            if kwargs.get("text") or kwargs.get("encoding"):
                output = output.decode()
            return subprocess.CompletedProcess(arguments, int(self.power_query_failed), output, "")
        if arguments == ["/usr/bin/pmset", "-g"]:
            output = "" if self.power_state_missing else f" SleepDisabled {int(self.disabled)}\n"
            if not (kwargs.get("text") or kwargs.get("encoding")):
                output = output.encode()
            return subprocess.CompletedProcess(arguments, int(self.power_query_failed), output, "")
        self.fail(f"Unexpected subprocess request: {arguments!r}")

    def spawn_process(self, arguments, **kwargs):
        arguments = list(arguments)
        if "sleep-if-idle" in arguments:
            self.assertTrue(kwargs.get("start_new_session"), "worker must detach")
            self.assertTrue(kwargs.get("close_fds"), "worker must not inherit the state lock")
            self.assertEqual(kwargs.get("stdin"), subprocess.DEVNULL)
            self.assertEqual(kwargs.get("stdout"), subprocess.DEVNULL)
            self.assertEqual(kwargs.get("stderr"), subprocess.DEVNULL)
            self.pending_workers.append(arguments)
        elif arguments != [self.control.CAFFEINATE, "-si"]:
            self.fail(f"Unexpected process launch: {arguments!r}")
        return FakeProcess()

    def hook(self, name, session="first"):
        event = {"hook_event_name": name, "session_id": session, "turn_id": session}
        output = io.StringIO()
        with patch.object(sys, "argv", ["caffeinate_control.py"]), patch.object(sys, "stdin", io.StringIO(json.dumps(event))), redirect_stdout(output):
            self.assertEqual(self.control.main(), 0)
        self.assertEqual(json.loads(output.getvalue()), {})

    def run_worker(self, arguments):
        offset = arguments.index("sleep-if-idle")
        with patch.object(sys, "argv", ["caffeinate_control.py", *arguments[offset:]]), redirect_stdout(io.StringIO()):
            self.assertEqual(self.control.main(), 0)

    def drain_workers(self):
        workers, self.pending_workers = self.pending_workers, []
        for arguments in workers:
            self.run_worker(arguments)

    def test_final_lid_stop_requests_sleep_when_lid_was_already_closed(self):
        self.hook("UserPromptSubmit")
        self.hook("Stop")
        self.assertEqual(self.sleep_requests, [], "Stop must return before sleep")
        self.drain_workers()
        self.assertEqual(len(self.sleep_requests), 1, "last lid turn must explicitly request sleep")

    def test_lid_opened_before_worker_does_not_sleep(self):
        self.hook("UserPromptSubmit")
        self.hook("Stop")
        self.closed = False
        self.drain_workers()
        self.assertEqual(self.sleep_requests, [])

    def test_remaining_lid_session_waits_for_last_stop(self):
        self.hook("UserPromptSubmit", "first")
        self.hook("UserPromptSubmit", "second")
        self.hook("Stop", "first")
        self.drain_workers()
        self.assertEqual(self.sleep_requests, [])
        self.assertIsNotNone(self.control.read_state(self.control.state_path("second")))
        self.hook("Stop", "second")
        self.drain_workers()
        self.assertEqual(len(self.sleep_requests), 1)

    def test_remaining_normal_session_retains_lid_sleep_obligation(self):
        self.hook("UserPromptSubmit", "first")
        self.mode = "normal"
        self.hook("UserPromptSubmit", "second")
        self.hook("Stop", "first")
        self.drain_workers()
        self.assertEqual(self.sleep_requests, [])
        self.assertIsNotNone(self.control.read_state(self.control.state_path("second")))
        self.hook("Stop", "second")
        self.drain_workers()
        self.assertEqual(len(self.sleep_requests), 1)

    def test_final_normal_stop_ignores_another_session_whose_owner_died(self):
        self.hook("UserPromptSubmit", "first")
        self.mode = "normal"
        self.hook("UserPromptSubmit", "second")
        self.hook("UserPromptSubmit", "crashed")
        self.hook("Stop", "first")
        self.drain_workers()
        self.assertEqual(self.sleep_requests, [])
        crashed_path = self.control.state_path("crashed")
        crashed = self.control.read_state(crashed_path)
        crashed["owner_pid"] = 5678
        self.control.write_state(crashed_path, crashed)
        self.hook("Stop", "second")
        self.drain_workers()
        self.assertFalse(crashed_path.exists())
        self.assertEqual(len(self.sleep_requests), 1)

    def test_new_start_invalidates_old_worker_even_after_new_turn_stops(self):
        self.hook("UserPromptSubmit", "first")
        self.hook("Stop", "first")
        self.assertEqual(len(self.pending_workers), 1)
        old_worker = self.pending_workers.pop()
        self.hook("UserPromptSubmit", "second")
        self.hook("Stop", "second")
        self.run_worker(old_worker)
        self.assertEqual(self.sleep_requests, [], "old worker must not shorten new turn's grace period")
        self.drain_workers()
        self.assertEqual(len(self.sleep_requests), 1)

    def test_new_active_normal_turn_prevents_queued_sleep(self):
        self.hook("UserPromptSubmit", "first")
        self.hook("Stop", "first")
        self.mode = "normal"
        self.hook("UserPromptSubmit", "second")
        self.drain_workers()
        self.assertEqual(self.sleep_requests, [])

    def test_start_replacement_does_not_schedule_sleep(self):
        self.hook("UserPromptSubmit")
        self.hook("UserPromptSubmit")
        self.assertEqual(self.pending_workers, [])
        self.assertEqual(self.sleep_requests, [])
        self.hook("Stop")
        self.drain_workers()
        self.assertEqual(len(self.sleep_requests), 1)

    def test_failed_power_query_does_not_sleep(self):
        self.hook("UserPromptSubmit")
        self.hook("Stop")
        self.power_query_failed = True
        self.drain_workers()
        self.assertEqual(self.sleep_requests, [])

    def test_unknown_sleep_setting_does_not_sleep(self):
        self.hook("UserPromptSubmit")
        self.hook("Stop")
        self.power_state_missing = True
        self.drain_workers()
        self.assertEqual(self.sleep_requests, [])

    def test_sleep_disabled_setting_does_not_sleep(self):
        self.hook("UserPromptSubmit")
        self.hook("Stop")
        self.disabled = True
        self.drain_workers()
        self.assertEqual(self.sleep_requests, [])

    def test_interrupt_and_session_end_release_final_lid_turn(self):
        for event in ("Interrupt", "SessionEnd"):
            with self.subTest(event=event):
                previous_count = len(self.sleep_requests)
                self.hook("UserPromptSubmit", event)
                self.hook(event, event)
                self.drain_workers()
                self.assertEqual(len(self.sleep_requests), previous_count + 1)

    def test_untracked_stop_never_schedules_sleep(self):
        self.hook("Stop", "missing")
        self.drain_workers()
        self.assertEqual(self.sleep_requests, [])
        self.assertEqual(self.pending_workers, [])

    def test_normal_or_off_only_turn_does_not_request_lid_sleep(self):
        for mode in ("normal", "off"):
            with self.subTest(mode=mode):
                self.mode = mode
                self.hook("UserPromptSubmit", mode)
                self.hook("Stop", mode)
                self.drain_workers()
                self.assertEqual(self.sleep_requests, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
