#!/run/current-system/sw/bin/python3
"""Exercise real macOS lid protection with isolated Codex hook state.

Run directly when no Codex keep-awake controller or tracked turn is active.
Requires the same passwordless pmset permission as lidcaffeinate.
Importing this file does not change power settings or start any processes.
"""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
from typing import Callable


def run(*arguments: str) -> str:
    return subprocess.run(
        arguments, check=True, capture_output=True, text=True, timeout=10
    ).stdout


def sleep_disabled() -> int:
    for line in run("/usr/bin/pmset", "-g").splitlines():
        fields = line.split()
        if fields[:1] == ["SleepDisabled"]:
            return int(fields[1])
    return 0


def set_sleep_disabled(value: int) -> None:
    run("/usr/bin/sudo", "-n", "--", "/usr/bin/pmset", "-a", "disablesleep", str(value))


def processes() -> dict[int, tuple[int, str]]:
    result = {}
    for line in run("/bin/ps", "-axo", "pid=,ppid=,command=").splitlines():
        fields = line.strip().split(maxsplit=2)
        if len(fields) == 3:
            result[int(fields[0])] = (int(fields[1]), fields[2])
    return result


def wait_until(condition: Callable[[], bool], message: str) -> None:
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.05)
    raise AssertionError(message)


class Fixture:
    def __init__(self, control):
        self.control = control
        self.owned: dict[int, str] = {}

    def remember_processes(self, controller_pid: int) -> None:
        snapshot = processes()
        related = {controller_pid}
        while True:
            descendants = {
                pid for pid, (parent, _) in snapshot.items() if parent in related
            }
            if descendants <= related:
                break
            related |= descendants
        for pid in related:
            if pid in snapshot:
                self.owned[pid] = snapshot[pid][1]

    def start(self, session_id: str) -> Path:
        path = self.control.state_path(session_id)
        with self.control.state_lock():
            warning = self.control.start(
                path, {"session_id": session_id, "turn_id": session_id}
            )
        assert warning is None, warning
        state = self.control.read_state(path)
        assert state is not None and isinstance(state.get("pid"), int), state
        self.remember_processes(state["pid"])
        wait_until(lambda: sleep_disabled() == 1, "start did not disable lid sleep")
        return path

    def stop(self, path: Path) -> None:
        with self.control.state_lock():
            self.control.stop_existing(path)

    def assert_stopped(self) -> None:
        wait_until(
            lambda: all(
                self.control.process_command(pid) != command
                for pid, command in self.owned.items()
            ),
            "controller or a child process survived final stop",
        )
        assert not list(self.control.STATE_ROOT.glob("session-*.json"))
        assert not self.control.LID_STATE_PATH.exists()
        assert sleep_disabled() == 0, "final stop left SleepDisabled=1"

    def cleanup(self) -> None:
        # Only signal PIDs whose commands still match processes this fixture saw.
        for pid, command in list(self.owned.items()):
            if self.control.process_command(pid) == command:
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if all(
                self.control.process_command(pid) != command
                for pid, command in self.owned.items()
            ):
                break
            time.sleep(0.05)
        for pid, command in self.owned.items():
            if self.control.process_command(pid) == command:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        self.owned.clear()
        for path in self.control.STATE_ROOT.glob("*.json"):
            path.unlink(missing_ok=True)
        set_sleep_disabled(0)


def clean_start_stop(fixture: Fixture) -> None:
    set_sleep_disabled(0)
    fixture.stop(fixture.start("clean"))
    fixture.assert_stopped()


def inherited_stale_flag(fixture: Fixture) -> None:
    set_sleep_disabled(1)
    fixture.stop(fixture.start("stale"))
    fixture.assert_stopped()


def overlapping_sessions(fixture: Fixture) -> None:
    set_sleep_disabled(0)
    first = fixture.start("overlap-first")
    second = fixture.start("overlap-second")
    first_state = fixture.control.read_state(first)
    second_state = fixture.control.read_state(second)
    assert first_state["pid"] == second_state["pid"], "sessions did not share a controller"
    fixture.stop(first)
    assert sleep_disabled() == 1, "first stop removed the other session's protection"
    assert fixture.control.process_command(second_state["pid"]) is not None
    fixture.stop(second)
    fixture.assert_stopped()


def abrupt_controller_death(fixture: Fixture) -> None:
    set_sleep_disabled(0)
    path = fixture.start("crashed-controller")
    state = fixture.control.read_state(path)
    os.kill(state["pid"], signal.SIGKILL)
    wait_until(
        lambda: sleep_disabled() == 0,
        "controller death left SleepDisabled=1",
    )
    wait_until(
        lambda: all(
            fixture.control.process_command(pid) != command
            for pid, command in fixture.owned.items()
        ),
        "a controller child survived controller death",
    )
    # Once the watchdog releases protection, a later hook removes its metadata.
    fixture.stop(path)
    fixture.assert_stopped()


def main() -> int:
    sys.dont_write_bytecode = True
    module_path = (
        Path(__file__).resolve().parents[2]
        / "codex/.codex/hooks/caffeinate_control.py"
    )
    spec = importlib.util.spec_from_file_location("codex_awake_control", module_path)
    control = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(control)

    if any(
        any(Path(part).name == "lidcaffeinate" for part in command.split())
        for _, command in processes().values()
    ):
        print("REFUSED: another lidcaffeinate controller is running")
        return 2
    if list(control.STATE_ROOT.glob("session-*.json")):
        print("REFUSED: main Codex keep-awake state contains tracked sessions")
        return 2

    original = sleep_disabled()
    failures = 0
    with tempfile.TemporaryDirectory(prefix="codex-awake-regression-") as temporary:
        control.STATE_ROOT = Path(temporary)
        control.LOCK_PATH = control.STATE_ROOT / "lock"
        control.LID_STATE_PATH = control.STATE_ROOT / "lid-controller.json"
        control.LID_SLEEP_PATH = control.STATE_ROOT / "lid-sleep.json"
        control.selected_mode = lambda: "lid"
        owner_command = control.process_command(os.getpid())
        control.codex_owner = lambda: (os.getpid(), owner_command)
        fixture = Fixture(control)
        try:
            for test in (
                clean_start_stop,
                inherited_stale_flag,
                overlapping_sessions,
                abrupt_controller_death,
            ):
                try:
                    test(fixture)
                except Exception as error:
                    failures += 1
                    print(f"FAIL: {test.__name__}: {error}", flush=True)
                else:
                    print(f"PASS: {test.__name__}", flush=True)
                finally:
                    fixture.cleanup()
        finally:
            try:
                fixture.cleanup()
            finally:
                set_sleep_disabled(original)
    return int(failures != 0)


if __name__ == "__main__":
    raise SystemExit(main())
