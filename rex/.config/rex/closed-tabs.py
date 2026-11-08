#!/usr/bin/python3
"""Retain and reopen Rex tabs using the supported Rex CLI.

Only the custom close action detaches terminals. Native close/exit still ends
them. Records contain layout metadata, not terminal contents. Retained
terminals expire 24 hours after closing; reopened/visible panes are preserved.
"""
import copy
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

REX = "/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
ROOT = Path.home() / ".config/rex"
STATE = ROOT / "closed-tabs-state.json"
RETENTION_SECONDS = 24 * 60 * 60
FLAVOR = "com.superlogical.terminal.shell"
ANCHOR = {"block": {"flavor": FLAVOR, "options": {
    "shell": "none", "command": ["/bin/cat"],
}}}


def api(session, method, **args):
    command = [REX, "--autostart=false", "api", "call"]
    if session:
        command += ["-s", session]
    result = subprocess.run(
        command + [method, json.dumps(args)],
        capture_output=True, text=True, timeout=12,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return json.loads(result.stdout)


def save(state):
    temporary = STATE.with_suffix(".tmp")
    with temporary.open("w") as output:
        json.dump(state, output)
        output.flush()
        os.fsync(output.fileno())
    os.replace(temporary, STATE)


def block_ids(node):
    if not node:
        return []
    if node.get("block_id"):
        return [node["block_id"]]
    split = node["split"]
    return block_ids(split["before"]) + block_ids(split["after"])


def surviving_layout(node, available):
    if not node:
        return None
    if node.get("block_id"):
        return node if node["block_id"] in available else None
    split = node["split"]
    before = surviving_layout(split["before"], available)
    after = surviving_layout(split["after"], available)
    if not before or not after:
        return before or after
    return {"split": {"direction": split["direction"], "ratio": split["ratio"],
                      "before": before, "after": after}}


def placeholder_layout(node, prefix):
    if node.get("block_id"):
        result = copy.deepcopy(ANCHOR)
        result["block"]["label"] = prefix + node["block_id"]
        return result
    split = node["split"]
    return {"split": {"direction": split["direction"], "ratio": split["ratio"],
                      "before": placeholder_layout(split["before"], prefix),
                      "after": placeholder_layout(split["after"], prefix)}}


def find_placeholders(session, prefix):
    # A create request can commit before its response or journal write arrives.
    # Unique labels let a retry reuse those placeholders rather than leak them.
    for window in api(session, "session.view").get("windows") or []:
        for layer in window["layers"]:
            found = [b for b in layer.get("blocks") or []
                     if b.get("label", "").startswith(prefix)]
            if found:
                return {"window_id": window["window_id"], "layer_id": layer["layer_id"],
                        "block_ids": [b["block_id"] for b in found]}
    return None


def blocks(session):
    return {block["block_id"]: block
            for block in api(session, "session.list_blocks")["blocks"]}


def entry_blocks(entry):
    return {bid for layer in entry["window"]["layers"]
            for bid in block_ids(layer.get("layout"))}


def expire_tabs(state, now=None, session_only=None):
    """Expire only retained terminals, while holding the normal action lock.

    Do not terminate visible panes, cleanup placeholders, or programs referenced
    by a more recent retained tab. Failed closes remain recorded for retry.
    """
    now = time.time() if now is None else now
    cutoff = now - RETENTION_SECONDS
    result = {"expired_tabs": 0, "closed_terminals": 0, "errors": []}
    due = {sid: [entry for entry in history if entry.get("closed_at", now) <= cutoff]
           for sid, history in state["sessions"].items()
           if session_only is None or sid == session_only}
    due = {sid: entries for sid, entries in due.items() if entries}
    if not due:
        return result
    # If Rex is unavailable this raises before changing any recovery metadata.
    live = {s["session_id"] for s in api(None, "session.list")["sessions"]}
    for session, entries in due.items():
        history = state["sessions"][session]
        if session not in live:
            result["expired_tabs"] += len(entries)
            del state["sessions"][session]
            save(state)
            continue
        protected = set()
        for entry in history:
            if entry.get("closed_at", now) > cutoff:
                protected.update(entry_blocks(entry))
        for entry in entries:
            failed = False
            for bid in sorted(entry_blocks(entry) - protected):
                try:
                    # Recheck just before each close; a pane may have been placed
                    # elsewhere through Rex's own UI since it was retained.
                    item = blocks(session).get(bid)
                    if item and item.get("placement") == "detached":
                        api(session, "block.close", block_id=bid, keep_last=True)
                        result["closed_terminals"] += 1
                except RuntimeError as error:
                    message = str(error)
                    if (message.endswith("(status=404 code=not_found)")
                            or message.endswith("(status=404 code=session_not_found)")):
                        continue  # The program/session already ended.
                    failed = True
                    result["errors"].append(message)
                except subprocess.TimeoutExpired:
                    failed = True
                    result["errors"].append("Rex timed out while expiring a retained terminal.")
            if not failed and not entry.get("restoring"):
                history.remove(entry)
                result["expired_tabs"] += 1
                save(state)
            # An interrupted restore may have visible panes/placeholders. Keep
            # its plan so reopening can finish; its detached originals still
            # expire above. Never close visible panes as part of this sweep.
        if not history:
            state["sessions"].pop(session, None)
            save(state)
    return result


def choose_window(view, block):
    for window in view.get("windows") or []:
        if any(block == item["block_id"]
               for layer in window["layers"] for item in layer.get("blocks") or []):
            return window
    return next((w for w in view.get("windows") or []
                 if w["window_id"] == view.get("active_window_id")), None)


def close_tab(state, session, block):
    view = api(session, "session.view")
    window = choose_window(view, block)
    if not window:
        return {"changed": False, "reason": "No tab is selected."}
    if not window["layers"][0].get("layout"):
        raise RuntimeError("This tab has no tiled pane to retain.")
    history = state["sessions"].setdefault(session, [])
    entry = next((x for x in history if x["window"]["window_id"] == window["window_id"]
                  and not x.get("restoring")), None)
    if entry is None:
        entry = {"window": window, "index": view["windows"].index(window),
                 "closed_at": time.time()}
        history.append(entry)
        # Journal before the first detach so interrupted closes stay recoverable.
        save(state)
    if len(view["windows"]) == 1:
        # Rex's app may destroy sessions with zero visible tabs. Keep this one alive.
        api(session, "session.new_window", focus=False,
            layout={"block": {"flavor": FLAVOR}}, window_label="New Tab")
    current = blocks(session)
    for layer in entry["window"]["layers"]:
        for bid in block_ids(layer.get("layout")):
            item = current.get(bid)
            if item and item.get("window_id") == window["window_id"]:
                api(session, "session.detach_block", block_id=bid)
    view = api(session, "session.view")
    return {"changed": True, "session_id": session,
            "window_id": view.get("active_window_id"), "retained": len(history)}


def reopen_tab(state, session):
    history = state["sessions"].setdefault(session, [])
    while history:
        entry = history[-1]
        current = blocks(session)
        original = entry["window"]
        restoring = entry.get("restoring")
        if restoring and restoring.get("window_id"):
            view = api(session, "session.view")
            if not any(w["window_id"] == restoring["window_id"]
                       for w in view.get("windows") or []):
                # A partial restoration was closed; surviving detached panes
                # can still be rebuilt in a new tab.
                entry.pop("restoring")
                restoring = None
                save(state)
        allowed_windows = {original["window_id"]}
        if restoring and restoring.get("window_id"):
            allowed_windows.add(restoring["window_id"])
        available = {bid for bid, item in current.items()
                     if item["placement"] == "detached"
                     or item.get("window_id") in allowed_windows}
        available &= {bid for layer in original["layers"]
                      for bid in block_ids(layer.get("layout"))}
        if available:
            break
        history.pop()
        save(state)
    else:
        return {"changed": False, "reason": "No closed tabs remain in this session."}

    if not restoring:
        layouts = []
        for layer in original["layers"]:
            layout = surviving_layout(layer.get("layout"), available)
            if layout:
                layouts.append({"source": layer, "layout": layout})
        # If only floating panes survived, give the first one the main layout.
        restoring = {"token": uuid.uuid4().hex, "layers": [], "plans": layouts}
        entry["restoring"] = restoring
        save(state)

    if not restoring.get("window_id"):
        first = restoring["plans"][0]
        prefix = "rex-reopen-" + restoring["token"] + "-0-"
        made = find_placeholders(session, prefix)
        if not made:
            made = api(session, "session.new_window", focus=False,
                       window_label=original.get("label", "Reopened Tab"),
                       layout=placeholder_layout(first["layout"], prefix))
        restoring["window_id"] = made["window_id"]
        restoring["layers"].append({"pairs": list(zip(
            block_ids(first["layout"]), made["block_ids"])), "layer_id": None})
        save(state)

    target = restoring["window_id"]
    # Recovery resumes an interrupted restore using its recorded placeholders.
    for plan in restoring["plans"][len(restoring["layers"]):]:
        prefix = "rex-reopen-" + restoring["token"] + "-" + str(len(restoring["layers"])) + "-"
        made = find_placeholders(session, prefix)
        if not made:
            made = api(session, "session.new_layer", window_id=target, focus=False,
                       bounds=plan["source"]["bounds"],
                       layout=placeholder_layout(plan["layout"], prefix))
        restoring["layers"].append({"pairs": list(zip(
            block_ids(plan["layout"]), made["block_ids"])),
            "layer_id": made["layer_id"]})
        save(state)

    for layer in restoring["layers"]:
        for retained, placeholder in layer["pairs"]:
            current = blocks(session)
            item = current.get(retained)
            anchor = current.get(placeholder)
            if item and anchor:
                if item.get("window_id") != target:
                    if (item["placement"] != "detached"
                            and item.get("window_id") != original["window_id"]):
                        raise RuntimeError("A retained pane was moved elsewhere; leaving it intact.")
                    api(session, "session.move_block", block_id=retained,
                        anchor_block_id=placeholder, side="after")
                api(session, "block.close", block_id=placeholder)
            elif anchor:
                # The original program exited while retained; don't resurrect it.
                api(session, "block.close", block_id=placeholder)
            elif item and item.get("window_id") != target:
                raise RuntimeError("A restoration placeholder disappeared; retained pane is safe.")

    view = api(session, "session.view")
    target_view = next((w for w in view.get("windows") or [] if w["window_id"] == target), None)
    if not target_view:
        history.pop()
        save(state)
        return {"changed": False, "reason": "The retained programs have exited."}
    placed = {b["block_id"] for layer in target_view["layers"] for b in layer.get("blocks") or []}
    live_layers = {layer["layer_id"] for layer in target_view["layers"]}
    for saved_layer, plan in zip(restoring["layers"], restoring["plans"]):
        if (saved_layer["layer_id"] in live_layers
                and plan["source"].get("state") == "minimized"):
            api(session, "session.set_layer_state", layer_id=saved_layer["layer_id"], state="minimized")
    focus = original.get("focused_block_id")
    if focus not in placed:
        focus = next(iter(placed), None)
    if focus:
        api(session, "session.focus_block", block_id=focus)
    zoom = original.get("zoomed_block_id")
    if zoom in placed:
        api(session, "session.zoom_block", block_id=zoom, zoom=True)
    others = [w["window_id"] for w in view.get("windows") or [] if w["window_id"] != target]
    index = entry["index"]
    api(session, "session.move_window", window_id=target,
        **({"before_window_id": others[index]} if index < len(others) else {}))
    history.pop()
    save(state)
    return {"changed": True, "session_id": session, "window_id": target,
            "remaining": len(history)}


def main():
    os.umask(0o077)
    if len(sys.argv) < 2 or sys.argv[1] not in {"close", "reopen", "expire"}:
        raise RuntimeError("Expected close SESSION, reopen SESSION, or expire.")
    operation = sys.argv[1]
    session = sys.argv[2] if len(sys.argv) > 2 else None
    if operation != "expire" and not session:
        raise RuntimeError("A session is required for close/reopen.")
    with (ROOT / "closed-tabs.lock").open("a") as lock:
        # A kernel lock is released even if this helper is interrupted.
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            if operation == "expire":
                return  # An interactive action is running; try next minute.
            raise
        state = json.loads(STATE.read_text()) if STATE.exists() else {"version": 1, "sessions": {}}
        if state.get("version") != 1:
            raise RuntimeError("Unrecognized closed-tab state; leaving it intact.")
        expired = expire_tabs(state, session_only=session)
        if operation == "expire":
            if expired["expired_tabs"] or expired["closed_terminals"] or expired["errors"]:
                print(json.dumps(expired))
            if expired["errors"]:
                sys.exit(1)
            return
        if expired["errors"]:
            raise RuntimeError("Expiry cleanup failed; please retry. " + expired["errors"][0])
        if operation == "close":
            result = close_tab(state, session, sys.argv[3] if len(sys.argv) > 3 else "")
        elif operation == "reopen":
            result = reopen_tab(state, session)
        print(json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
