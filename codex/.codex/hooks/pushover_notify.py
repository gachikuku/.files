#!/run/current-system/sw/bin/python3
"""Send sparse, attention-worthy Codex notifications through Pushover."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


PUSHOVER_ENDPOINT = "https://api.pushover.net/1/messages.json"
USER_KEY_ENTRY = "api/pushover-user-key"
APP_TOKEN_ENTRY = "api/pushover-app-token"
STATE_ROOT = Path(tempfile.gettempdir()) / f"codex-pushover-{os.getuid()}"
BREAKTHROUGH_COOLDOWN_SECONDS = 30 * 60


def read_event() -> dict[str, Any]:
    try:
        value = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        return {}
    return value if isinstance(value, dict) else {}


def read_secret(entry: str) -> str:
    gopass = shutil.which("gopass") or "/run/current-system/sw/bin/gopass"
    result = subprocess.run(
        [gopass, "show", "-o", entry],
        check=False,
        capture_output=True,
        text=True,
        timeout=5,
    )
    value = result.stdout.strip()
    if result.returncode != 0 or not value:
        raise RuntimeError(f"missing gopass entry: {entry}")
    return value


def project_name(cwd: object = None) -> str:
    path = str(cwd).strip() if isinstance(cwd, str) else ""
    return Path(path or os.getcwd()).name or "Codex"


def compact(text: object, limit: int = 850) -> str:
    if not isinstance(text, str):
        return ""
    value = " ".join(text.split())
    if len(value) <= limit:
        return value
    return f"{value[: limit - 1].rstrip()}…"


def send_notification(title: str, message: str, priority: int = 0) -> None:
    body = urlencode(
        {
            "token": read_secret(APP_TOKEN_ENTRY),
            "user": read_secret(USER_KEY_ENTRY),
            "title": compact(title, 200),
            "message": compact(message) or "Codex needs your attention.",
            "priority": str(priority),
        }
    ).encode("utf-8")
    request = Request(PUSHOVER_ENDPOINT, data=body, method="POST")
    request.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urlopen(request, timeout=5) as response:
            result = json.load(response)
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")[:300]
        raise RuntimeError(f"Pushover rejected the notification: {detail}") from error
    except (URLError, TimeoutError, json.JSONDecodeError) as error:
        raise RuntimeError(f"Pushover request failed: {error}") from error
    if not isinstance(result, dict) or result.get("status") != 1:
        raise RuntimeError("Pushover returned an unsuccessful response")


def event_marker(event: dict[str, Any]) -> Path | None:
    session_id = event.get("session_id")
    turn_id = event.get("turn_id")
    if not isinstance(session_id, str) or not isinstance(turn_id, str):
        return None
    digest = hashlib.sha256(f"{session_id}\0{turn_id}".encode()).hexdigest()
    return STATE_ROOT / f"terminal-{digest}"


def mark_terminal_notification(event: dict[str, Any]) -> None:
    marker = event_marker(event)
    if marker is None:
        return
    STATE_ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    marker.touch(mode=0o600)


def consume_terminal_marker(event: dict[str, Any]) -> bool:
    marker = event_marker(event)
    if marker is None:
        return False
    try:
        marker.unlink()
    except FileNotFoundError:
        return False
    return True


def handle_hook(event: dict[str, Any]) -> None:
    event_name = event.get("hook_event_name")
    tool_name = event.get("tool_name")
    project = project_name(event.get("cwd"))

    if event_name == "PostToolUse" and tool_name == "update_goal":
        tool_input = event.get("tool_input")
        status = tool_input.get("status") if isinstance(tool_input, dict) else None
        if status == "complete":
            send_notification(
                "Codex goal achieved",
                f"The goal in {project} is complete.",
                priority=0,
            )
            mark_terminal_notification(event)
        elif status == "blocked":
            send_notification(
                "Codex goal blocked",
                f"The goal in {project} cannot continue without attention.",
                priority=1,
            )
            mark_terminal_notification(event)
        return

    if event_name == "PermissionRequest":
        tool_input = event.get("tool_input")
        description = tool_input.get("description") if isinstance(tool_input, dict) else None
        detail = compact(description, 500) or f"Approval is required for {tool_name or 'an action'}."
        send_notification("Codex needs approval", f"{project}: {detail}", priority=1)
        return

    if event_name == "PreToolUse" and tool_name == "request_user_input":
        send_notification(
            "Codex needs your input",
            f"Open the {project} session to answer a question.",
            priority=1,
        )
        return

    if event_name == "Stop":
        if consume_terminal_marker(event):
            return
        last_message = compact(event.get("last_assistant_message"), 750)
        send_notification(
            "Codex stopped",
            f"{project}: {last_message or 'The root turn is no longer running.'}",
            priority=1,
        )


def breakthrough_marker() -> Path:
    digest = hashlib.sha256(os.getcwd().encode()).hexdigest()
    return STATE_ROOT / f"breakthrough-{digest}"


def send_breakthrough(message: str) -> bool:
    marker = breakthrough_marker()
    try:
        last_sent = marker.stat().st_mtime
    except FileNotFoundError:
        last_sent = 0
    if time.time() - last_sent < BREAKTHROUGH_COOLDOWN_SECONDS:
        return False
    send_notification(
        "Codex breakthrough",
        f"{project_name()}: {compact(message, 750)}",
        priority=0,
    )
    STATE_ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    marker.touch(mode=0o600)
    return True


def main() -> int:
    try:
        if len(sys.argv) >= 2 and sys.argv[1] == "test":
            send_notification(
                "Codex notifications ready",
                "Pushover is connected and the notification test succeeded.",
                priority=0,
            )
            print("Pushover test notification sent.")
            return 0

        if len(sys.argv) >= 2 and sys.argv[1] == "breakthrough":
            message = " ".join(sys.argv[2:]).strip()
            if not message:
                print("Usage: pushover_notify.py breakthrough <message>", file=sys.stderr)
                return 2
            sent = send_breakthrough(message)
            print("Pushover breakthrough notification sent." if sent else "Notification suppressed by cooldown.")
            return 0

        if len(sys.argv) > 1:
            print("Usage: pushover_notify.py [test|breakthrough <message>]", file=sys.stderr)
            return 2

        handle_hook(read_event())
        # Stop hooks require a JSON response; an empty object is also harmless
        # for the other lifecycle events handled by this script.
        print("{}")
        return 0
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Codex Pushover notification failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
