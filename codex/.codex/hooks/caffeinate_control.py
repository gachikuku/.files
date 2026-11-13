#!/run/current-system/sw/bin/python3
"""Keep macOS awake while a main Codex turn is active."""

from __future__ import annotations

import hashlib
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import tempfile
import time
from typing import Any
import uuid


CAFFEINATE = "/usr/bin/caffeinate"
LIDCAFFEINATE = "/Users/gachikuku/bin/lidcaffeinate"
PS = "/bin/ps"
STATE_ROOT = Path(tempfile.gettempdir()) / f"codex-caffeinate-{os.getuid()}"
LOCK_PATH = STATE_ROOT / "lock"
LID_STATE_PATH = STATE_ROOT / "lid-controller.json"
LID_SLEEP_PATH = STATE_ROOT / "lid-sleep.json"
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


def process_parent(pid: int) -> int | None:
    result = subprocess.run(
        [PS, "-p", str(pid), "-o", "ppid="],
        check=False,
        capture_output=True,
        text=True,
    )
    try:
        parent = int(result.stdout.strip())
    except ValueError:
        return None
    return parent if result.returncode == 0 and parent > 0 else None


def codex_owner() -> tuple[int, str] | None:
    """Find the Codex process above the hook's short-lived shell process."""
    pid = os.getppid()
    for _ in range(8):
        command = process_command(pid)
        if command is None:
            return None
        executable = Path(command.split(maxsplit=1)[0]).name
        if executable in {"codex", ".codex-wrapped"}:
            return pid, command
        parent = process_parent(pid)
        if parent is None or parent == pid:
            return None
        pid = parent
    return None


def prune_dead_sessions() -> None:
    """Remove state owned by Codex processes that no longer exist."""
    for candidate in STATE_ROOT.glob("session-*.json"):
        state = read_state(candidate)
        if state is None:
            candidate.unlink(missing_ok=True)
            continue
        try:
            owner_pid = int(state["owner_pid"])
            owner_command = str(state["owner_command"])
        except (KeyError, TypeError, ValueError):
            # Legacy state has no owner metadata. Keep it until its normal Stop
            # hook runs; current writes always include owner metadata.
            continue
        if process_command(owner_pid) != owner_command:
            candidate.unlink(missing_ok=True)


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
        env={**os.environ, "LIDCAFFEINATE_RESTORE_SLEEP": "1"},
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
    prune_dead_sessions()
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


def renew_lid_sleep_request() -> str:
    token = uuid.uuid4().hex
    write_state(LID_SLEEP_PATH, {"token": token})
    return token


def schedule_lid_sleep(stopped_state: dict[str, Any]) -> str | None:
    # Keep the lid-mode obligation until every overlapping turn has finished,
    # including turns that selected normal mode. An untracked Stop adds none.
    if stopped_state.get("mode") != "lid" and not LID_SLEEP_PATH.exists():
        return None
    token = renew_lid_sleep_request()
    prune_dead_sessions()
    if any(STATE_ROOT.glob("session-*.json")):
        return None
    try:
        subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "sleep-if-idle", token],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            close_fds=True,
        )
    except OSError:
        return "Codex keep-awake could not schedule closed-lid sleep."
    return None


def sleep_if_idle(token: str) -> int:
    # Let the Stop hook return before sleeping. A new prompt invalidates the
    # token, even if that newer turn also finishes during this short delay.
    time.sleep(1)
    with state_lock():
        pending = read_state(LID_SLEEP_PATH)
        if pending is None or pending.get("token") != token:
            return 0
        prune_dead_sessions()
        if any(STATE_ROOT.glob("session-*.json")):
            return 0
        try:
            result = subprocess.run(
                ["/usr/sbin/ioreg", "-a", "-r", "-c", "IOPMrootDomain", "-d", "1"],
                check=False, capture_output=True, timeout=2,
            )
            if result.returncode != 0:
                return 0
            roots = plistlib.loads(result.stdout)
            if not isinstance(roots, list) or not roots or not isinstance(roots[0], dict):
                return 0
            power = roots[0]
            if power.get("AppleClamshellState") is False:
                LID_SLEEP_PATH.unlink(missing_ok=True)
                return 0
            if (
                power.get("AppleClamshellState") is not True
                or power.get("SleepDisabled") is not False
            ):
                return 0
            # Hold the same lock used by prompt starts through the request so
            # another task cannot begin between the idle check and sleep.
            LID_SLEEP_PATH.unlink(missing_ok=True)
            result = subprocess.run(
                ["/usr/bin/sudo", "-n", "--", "/usr/bin/pmset", "sleepnow"],
                check=False, capture_output=True, timeout=5,
            )
            return result.returncode
        except (OSError, ValueError, plistlib.InvalidFileException, subprocess.TimeoutExpired):
            return 1


def start(path: Path, event: dict[str, Any]) -> str | None:
    mode = selected_mode()
    if mode == "lid" or LID_SLEEP_PATH.exists():
        renew_lid_sleep_request()
    prune_dead_sessions()
    stop_existing(path)

    state = {
        "session_id": event.get("session_id"),
        "turn_id": event.get("turn_id"),
        "mode": mode,
    }
    owner = codex_owner()
    if owner is not None:
        state["owner_pid"], state["owner_command"] = owner

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
        prune_dead_sessions()
        sessions = []
        for candidate in STATE_ROOT.glob("session-*.json"):
            state = read_state(candidate)
            if state is not None:
                sessions.append(state)
        lid_state = read_state(LID_STATE_PATH)

    lid_controller_running = False
    if lid_state is not None:
        try:
            lid_pid = int(lid_state["pid"])
        except (KeyError, TypeError, ValueError):
            pass
        else:
            lid_controller_running = (
                process_command(lid_pid) == f"/bin/sh {LIDCAFFEINATE}"
            )

    pmset = subprocess.run(
        ["/usr/bin/pmset", "-g"],
        check=False,
        capture_output=True,
        text=True,
    )
    sleep_disabled = any(
        line.split() == ["SleepDisabled", "1"]
        for line in pmset.stdout.splitlines()
    )

    print(f"Selected mode: {selected_mode()}")
    print(f"Active normal sessions: {sum(s.get('mode') == 'normal' for s in sessions)}")
    print(f"Active lid sessions: {sum(s.get('mode') == 'lid' for s in sessions)}")
    print(f"Lid controller: {'running' if lid_controller_running else 'stopped'}")
    print(f"Lid sleep protection: {'active' if sleep_disabled else 'inactive'}")
    return 0


def run_cli(arguments: list[str]) -> int:
    if len(arguments) == 2 and arguments[0] == "sleep-if-idle":
        return sleep_if_idle(arguments[1])
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
            stopped_state = read_state(path)
            stop_existing(path)
            if stopped_state is not None:
                warning = schedule_lid_sleep(stopped_state)

    # Stop hooks require JSON (or no output) on successful exit.
    print(json.dumps({"systemMessage": warning}) if warning else "{}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
