#!/run/current-system/sw/bin/python3
"""Keep macOS awake while a main Codex turn is active."""

from __future__ import annotations

import hashlib
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
PS = "/bin/ps"
STATE_ROOT = Path(tempfile.gettempdir()) / f"codex-caffeinate-{os.getuid()}"


def read_event() -> dict[str, Any]:
    try:
        value = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        return {}
    return value if isinstance(value, dict) else {}


def state_path(session_id: str) -> Path:
    digest = hashlib.sha256(session_id.encode("utf-8")).hexdigest()
    return STATE_ROOT / f"{digest}.json"


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


def stop_existing(path: Path) -> None:
    state = read_state(path)
    if state is None:
        path.unlink(missing_ok=True)
        return

    try:
        pid = int(state["caffeinate_pid"])
    except (KeyError, TypeError, ValueError):
        path.unlink(missing_ok=True)
        return

    expected = f"{CAFFEINATE} -si"
    if process_command(pid) == expected:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    path.unlink(missing_ok=True)


def start(path: Path, event: dict[str, Any]) -> None:
    stop_existing(path)

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
        return

    state = {
        "session_id": event.get("session_id"),
        "turn_id": event.get("turn_id"),
        "caffeinate_pid": process.pid,
    }
    temporary = path.with_suffix(f".{os.getpid()}.tmp")
    temporary.write_text(json.dumps(state), encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def main() -> int:
    event = read_event()
    event_name = event.get("hook_event_name")
    session_id = event.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        print("{}")
        return 0

    STATE_ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(STATE_ROOT, 0o700)
    path = state_path(session_id)

    if event_name == "UserPromptSubmit":
        start(path, event)
    elif event_name in {"Stop", "Interrupt", "SessionEnd"}:
        stop_existing(path)

    # Stop hooks require JSON (or no output) on successful exit.
    print("{}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
