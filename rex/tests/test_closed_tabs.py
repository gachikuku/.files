"""Exercise retention policy without contacting Rex or writing live state."""
import copy
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch


sys.dont_write_bytecode = True
SOURCE = Path(__file__).resolve().parents[1] / ".config/rex/closed-tabs.py"
SPEC = importlib.util.spec_from_file_location("rex_closed_tabs_under_test", SOURCE)
closed_tabs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(closed_tabs)

NOW = 2_000_000_000
SESSION = "session:test"
TTL = closed_tabs.RETENTION_SECONDS


def layout(*ids):
    if len(ids) == 1:
        return {"block_id": ids[0]}
    return {"split": {"direction": "horizontal", "ratio": 0.4,
                      "before": layout(ids[0]), "after": layout(*ids[1:])}}


def retained(*ids, closed_at=None, window="window:original"):
    return {"window": {"window_id": window,
                       "layers": [{"kind": "tiled", "layout": layout(*ids)}]},
            "index": 0, "closed_at": NOW - TTL if closed_at is None else closed_at}


def terminal(bid, placement="detached", window=None):
    result = {"block_id": bid, "placement": placement}
    if window is not None:
        result["window_id"] = window
    return result


class FakeRex:
    """Small server model: successful closes really remove blocks."""

    def __init__(self, *items, session=SESSION):
        self.sessions = {session: {item["block_id"]: copy.deepcopy(item)
                                   for item in items}}
        self.calls = []
        self.closed = []
        self.close_failures = {}
        self.list_error = None

    def api(self, session, method, **args):
        self.calls.append((session, method, copy.deepcopy(args)))
        if method == "session.list":
            if self.list_error:
                raise self.list_error
            return {"sessions": [{"session_id": sid} for sid in self.sessions]}
        if method == "session.list_blocks":
            return {"blocks": copy.deepcopy(list(self.sessions[session].values()))}
        if method == "block.close":
            bid = args["block_id"]
            if self.close_failures.get(bid):
                raise self.close_failures[bid].pop(0)
            if args.get("keep_last") is not True:
                raise AssertionError("Expiry must request last-visible-pane protection")
            item = self.sessions[session][bid]
            if item["placement"] != "detached":
                raise AssertionError("Expiry attempted to close a placed/unknown block")
            del self.sessions[session][bid]
            self.closed.append((session, bid))
            return {"block_id": bid, "revision": 1}
        raise AssertionError("Unexpected Rex method: " + method)


class ExpireTabsTests(unittest.TestCase):
    def setUp(self):
        self.saved = []
        self.save_patch = patch.object(
            closed_tabs, "save", side_effect=lambda state: self.saved.append(copy.deepcopy(state)))
        self.save_patch.start()
        self.addCleanup(self.save_patch.stop)

    def expire(self, state, server, **kwargs):
        with patch.object(closed_tabs, "api", side_effect=server.api):
            return closed_tabs.expire_tabs(state, now=kwargs.pop("now", NOW), **kwargs)

    def test_expires_at_24_hours_but_not_one_second_before(self):
        state = {"version": 1, "sessions": {SESSION: [retained("block:old")]}}
        server = FakeRex(terminal("block:old"))

        before = self.expire(state, server, now=NOW - 1)
        self.assertEqual(before, {"expired_tabs": 0, "closed_terminals": 0, "errors": []})
        self.assertEqual(server.calls, [])
        self.assertEqual(self.saved, [])

        at_boundary = self.expire(state, server)
        self.assertEqual(at_boundary, {"expired_tabs": 1, "closed_terminals": 1, "errors": []})
        self.assertEqual(server.closed, [(SESSION, "block:old")])
        self.assertEqual(state["sessions"], {})
        self.assertEqual(self.saved[-1], state)

    def test_reopened_visible_panes_are_not_terminated(self):
        state = {"version": 1, "sessions": {SESSION: [retained("block:visible")]}}
        server = FakeRex(terminal("block:visible", "placed", "window:reopened"))

        result = self.expire(state, server)

        self.assertEqual(server.closed, [])
        self.assertIn("block:visible", server.sessions[SESSION])
        self.assertEqual(result["expired_tabs"], 1)
        self.assertEqual(state["sessions"], {})
        self.assertFalse(any(method == "block.close" for _, method, _ in server.calls))

    def test_unknown_placement_is_not_treated_as_detached(self):
        state = {"version": 1, "sessions": {SESSION: [retained("block:unknown")]}}
        server = FakeRex(terminal("block:unknown", "future-placement"))

        self.expire(state, server)

        self.assertEqual(server.closed, [])
        self.assertIn("block:unknown", server.sessions[SESSION])

    def test_newer_duplicate_reference_gets_its_own_full_retention_period(self):
        old = retained("block:shared", "block:old-only")
        recent = retained("block:shared", "block:new-only", closed_at=NOW - 30,
                          window="window:new-close")
        state = {"version": 1, "sessions": {SESSION: [old, recent]}}
        server = FakeRex(*(terminal(bid) for bid in
                           ("block:shared", "block:old-only", "block:new-only")))

        result = self.expire(state, server)

        self.assertEqual(server.closed, [(SESSION, "block:old-only")])
        self.assertEqual(result["expired_tabs"], 1)
        self.assertEqual(state["sessions"][SESSION], [recent])
        self.assertEqual(set(server.sessions[SESSION]), {"block:shared", "block:new-only"})

        self.expire(state, server, now=recent["closed_at"] + TTL)
        self.assertEqual(set(server.closed), {(SESSION, "block:old-only"),
                                             (SESSION, "block:shared"),
                                             (SESSION, "block:new-only")})
        self.assertEqual(state["sessions"], {})

    def test_failed_close_keeps_record_and_retries_remaining_block(self):
        for failure in (RuntimeError("transport unavailable"),
                        subprocess.TimeoutExpired("rex", 12)):
            with self.subTest(failure=type(failure).__name__):
                self.saved.clear()
                entry = retained("block:a", "block:b")
                state = {"version": 1, "sessions": {SESSION: [entry]}}
                original_state = copy.deepcopy(state)
                server = FakeRex(terminal("block:a"), terminal("block:b"))
                server.close_failures["block:b"] = [failure]

                first = self.expire(state, server)

                self.assertEqual(first["closed_terminals"], 1)
                self.assertEqual(first["expired_tabs"], 0)
                self.assertEqual(len(first["errors"]), 1)
                self.assertEqual(state, original_state)
                self.assertEqual(self.saved, [])
                self.assertEqual(server.closed, [(SESSION, "block:a")])

                second = self.expire(state, server)

                self.assertEqual(second, {"expired_tabs": 1, "closed_terminals": 1,
                                          "errors": []})
                self.assertEqual(server.closed, [(SESSION, "block:a"), (SESSION, "block:b")])
                self.assertEqual(state["sessions"], {})
                self.assertEqual(self.saved[-1], state)

    def test_unavailable_server_does_not_discard_recovery_state(self):
        state = {"version": 1, "sessions": {SESSION: [retained("block:old")]}}
        original_state = copy.deepcopy(state)
        server = FakeRex(terminal("block:old"))
        server.list_error = RuntimeError("Rex is not running")

        with self.assertRaisesRegex(RuntimeError, "not running"):
            self.expire(state, server)

        self.assertEqual(state, original_state)
        self.assertEqual(self.saved, [])
        self.assertEqual(server.closed, [])
        self.assertEqual(server.calls, [(None, "session.list", {})])

        server.list_error = None
        self.expire(state, server)
        self.assertEqual(server.closed, [(SESSION, "block:old")])

    def test_partial_restore_expires_detached_originals_but_keeps_visible_and_placeholder(self):
        entry = retained("block:visible", "block:pending")
        entry["restoring"] = {
            "token": "partial", "window_id": "window:restoring",
            "layers": [{"pairs": [["block:pending", "block:placeholder"]]}],
        }
        state = {"version": 1, "sessions": {SESSION: [entry]}}
        original_state = copy.deepcopy(state)
        server = FakeRex(
            terminal("block:visible", "placed", "window:restoring"),
            terminal("block:pending"),
            terminal("block:placeholder", "placed", "window:restoring"),
        )

        result = self.expire(state, server)

        self.assertEqual(result, {"expired_tabs": 0, "closed_terminals": 1, "errors": []})
        self.assertEqual(server.closed, [(SESSION, "block:pending")])
        self.assertEqual(set(server.sessions[SESSION]), {"block:visible", "block:placeholder"})
        self.assertEqual(state, original_state)
        self.expire(state, server)
        self.assertEqual(server.closed, [(SESSION, "block:pending")])
        self.assertEqual(state, original_state)

    def test_empty_history_never_contacts_server(self):
        for histories in ({}, {SESSION: []}):
            with self.subTest(histories=histories):
                state = {"version": 1, "sessions": copy.deepcopy(histories)}
                server = FakeRex()

                result = self.expire(state, server)

                self.assertEqual(result, {"expired_tabs": 0, "closed_terminals": 0, "errors": []})
                self.assertEqual(server.calls, [])
                self.assertEqual(self.saved, [])

    def test_missing_block_is_pruned_without_a_close_request(self):
        state = {"version": 1, "sessions": {SESSION: [retained("block:already-exited")]}}
        server = FakeRex()

        result = self.expire(state, server)

        self.assertEqual(result, {"expired_tabs": 1, "closed_terminals": 0, "errors": []})
        self.assertEqual(server.closed, [])
        self.assertEqual(state["sessions"], {})

    def test_session_filter_leaves_other_sessions_untouched(self):
        other = "session:other"
        state = {"version": 1, "sessions": {
            SESSION: [retained("block:here")], other: [retained("block:there")],
        }}
        untouched = copy.deepcopy(state["sessions"][other])
        server = FakeRex(terminal("block:here"))
        server.sessions[other] = {"block:there": terminal("block:there")}

        self.expire(state, server, session_only=SESSION)

        self.assertEqual(server.closed, [(SESSION, "block:here")])
        self.assertEqual(state["sessions"], {other: untouched})
        self.assertFalse(any(sid == other for sid, _, _ in server.calls))


if __name__ == "__main__":
    unittest.main()
