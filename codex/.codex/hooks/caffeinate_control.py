#!/run/current-system/sw/bin/python3
"""Keep macOS awake while a main Codex turn is active."""

from __future__ import annotations

import hashlib
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
from typing import Any


CAFFEINATE = "/usr/bin/caffeinate"
LIDCAFFEINATE = "/Users/gachikuku/bin/lidcaffeinate"
PS = "/bin/ps"
STATE_ROOT = Path(tempfile.gettempdir()) / f"codex-caffeinate-{os.getuid()}"
LOCK_PATH = STATE_ROOT / "lock"
LID_STATE_PATH = STATE_ROOT / "lid-controller.json"
MODE_ROOT = Path.home() / ".config" / "codex-awake"
MODE_PATH = MODE_ROOT / "mode"
VALID_MODES = {"normal", "lid", "off"}


def read_event() -> dict[str, Any]:
    try:
        value = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        return {}
    return value if isinstance(value, dict) else {}


def state_path(session_id: str) -> Path:
    digest = hashlib.sha256(session_id.encode("utf-8")).hexdigest()
    return STATE_ROOT / f"session-{digest}.json"


def read_state(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None
    return value if isinstance(value, dict) else None


def process_command(pid: int) -> str | None:
    result = subprocess.run(
        [PS, "-p", str(pid), "-o", "command="],
        check=False,
        capture_output=True,
        text=True,
    )
    command = result.stdout.strip()
    return command if result.returncode == 0 and command else None


def write_state(path: Path, state: dict[str, Any]) -> None:
    temporary = path.with_suffix(f".{os.getpid()}.tmp")
    temporary.write_text(json.dumps(state), encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def terminate_verified(pid: int, expected_command: str) -> None:
    if process_command(pid) != expected_command:
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return


def selected_mode() -> str:
    environment_mode = os.environ.get("CODEX_AWAKE_MODE", "").strip().lower()
    if environment_mode in VALID_MODES:
        return environment_mode
    try:
        configured_mode = MODE_PATH.read_text(encoding="utf-8").strip().lower()
    except OSError:
        return "normal"
    return configured_mode if configured_mode in VALID_MODES else "normal"


@contextmanager
def state_lock():
    STATE_ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(STATE_ROOT, 0o700)
    with LOCK_PATH.open("a", encoding="utf-8") as lock_file:
        os.chmod(LOCK_PATH, 0o600)
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        yield


def start_lid_controller() -> int | None:
    state = read_state(LID_STATE_PATH)
    expected = f"/bin/sh {LIDCAFFEINATE}"
    if state is not None:
        try:
            existing_pid = int(state["pid"])
        except (KeyError, TypeError, ValueError):
            existing_pid = 0
        if existing_pid > 0 and process_command(existing_pid) == expected:
            return existing_pid
        LID_STATE_PATH.unlink(missing_ok=True)

    process = subprocess.Popen(
        ["/bin/sh", LIDCAFFEINATE],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        close_fds=True,
    )
    time.sleep(0.15)
    if process.poll() is not None:
        return None

    write_state(LID_STATE_PATH, {"pid": process.pid, "command": expected})
    return process.pid


def stop_lid_controller_if_unused() -> None:
    for candidate in STATE_ROOT.glob("session-*.json"):
        state = read_state(candidate)
        if state is not None and state.get("mode") == "lid":
            return

    state = read_state(LID_STATE_PATH)
    if state is not None:
        try:
            pid = int(state["pid"])
        except (KeyError, TypeError, ValueError):
            pid = 0
        if pid > 0:
            terminate_verified(pid, f"/bin/sh {LIDCAFFEINATE}")
            for _ in range(30):
                if process_command(pid) is None:
                    break
                time.sleep(0.05)
    LID_STATE_PATH.unlink(missing_ok=True)


def stop_existing(path: Path) -> None:
    state = read_state(path)
    if state is None:
        path.unlink(missing_ok=True)
        return

    if state.get("mode") == "normal":
        try:
            pid = int(state["pid"])
        except (KeyError, TypeError, ValueError):
            pass
        else:
            terminate_verified(pid, f"{CAFFEINATE} -si")

    path.unlink(missing_ok=True)
    if state.get("mode") == "lid":
        stop_lid_controller_if_unused()


def start(path: Path, event: dict[str, Any]) -> str | None:
    stop_existing(path)
    mode = selected_mode()

    state = {
        "session_id": event.get("session_id"),
        "turn_id": event.get("turn_id"),
        "mode": mode,
    }

    if mode == "off":
        return None

    if mode == "lid":
        write_state(path, state)
        lid_pid = start_lid_controller()
        if lid_pid is None:
            path.unlink(missing_ok=True)
            stop_lid_controller_if_unused()
            return "Codex keep-awake could not start lidcaffeinate."
        state["pid"] = lid_pid
        write_state(path, state)
        return None

    process = subprocess.Popen(
        [CAFFEINATE, "-si"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        close_fds=True,
    )

    time.sleep(0.05)
    if process.poll() is not None:
        return "Codex keep-awake could not start caffeinate -si."

    state["pid"] = process.pid
    write_state(path, state)
    return None


def set_mode(mode: str) -> int:
    if mode not in VALID_MODES:
        print("Usage: codex-awake {normal|lid|off|status}", file=sys.stderr)
        return 2
    MODE_ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = MODE_PATH.with_suffix(f".{os.getpid()}.tmp")
    temporary.write_text(f"{mode}\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, MODE_PATH)
    print(f"Codex keep-awake mode: {mode}")
    print("The selection applies when the next prompt is submitted.")
    if mode == "lid":
        print("Keep the closed Mac ventilated; never place it in a bag while running.")
    return 0


def show_status() -> int:
    with state_lock():
        sessions = []
        for candidate in STATE_ROOT.glob("session-*.json"):
            state = read_state(candidate)
            if state is not None:
                sessions.append(state)
        lid_state = read_state(LID_STATE_PATH)

    print(f"Selected mode: {selected_mode()}")
    print(f"Active normal sessions: {sum(s.get('mode') == 'normal' for s in sessions)}")
    print(f"Active lid sessions: {sum(s.get('mode') == 'lid' for s in sessions)}")
    print(f"Lid controller: {'running' if lid_state is not None else 'stopped'}")
    return 0


def run_cli(arguments: list[str]) -> int:
    if len(arguments) != 1:
        print("Usage: codex-awake {normal|lid|off|status}", file=sys.stderr)
        return 2
    if arguments[0] == "status":
        return show_status()
    return set_mode(arguments[0])


def main() -> int:
    if len(sys.argv) > 1:
        return run_cli(sys.argv[1:])

    event = read_event()
    event_name = event.get("hook_event_name")
    session_id = event.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        print("{}")
        return 0

    path = state_path(session_id)

    warning = None
    with state_lock():
        if event_name == "UserPromptSubmit":
            warning = start(path, event)
        elif event_name in {"Stop", "Interrupt", "SessionEnd"}:
            stop_existing(path)

    # Stop hooks require JSON (or no output) on successful exit.
    print(json.dumps({"systemMessage": warning}) if warning else "{}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
