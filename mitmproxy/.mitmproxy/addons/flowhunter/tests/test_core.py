from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from mitmproxy import http
from mitmproxy.test import tflow

from flowhunter.core import (
    build_mutations,
    compare_replay,
    host_in_scope,
    snapshot_from_flow,
)
from flowhunter.storage import Storage


def make_flow(
    method: str = "GET",
    url: str = "https://api.example.com/users/123?token=secret&limit=10",
    request_body: str = "",
    request_type: str = "",
    status: int = 200,
    response_body: str = '{"ok":true}',
    response_type: str = "application/json",
) -> http.HTTPFlow:
    request_headers = {"authorization": "Bearer very-secret"}
    if request_type:
        request_headers["content-type"] = request_type
    request = http.Request.make(method, url, request_body, request_headers)
    response = http.Response.make(
        status,
        response_body,
        {"content-type": response_type, "set-cookie": "sid=also-secret"},
    )
    return tflow.tflow(req=request, resp=response)


class ScopeTests(unittest.TestCase):
    def test_exact_and_wildcard_scope(self) -> None:
        self.assertTrue(host_in_scope("api.example.com", ["api.example.com"]))
        self.assertTrue(host_in_scope("a.example.com", ["*.example.com"]))
        self.assertFalse(host_in_scope("example.com", ["*.example.com"]))
        self.assertFalse(host_in_scope("example.com.attacker.test", ["*.example.com"]))


class SnapshotTests(unittest.TestCase):
    def test_signature_deduplicates_values_and_dynamic_integer_paths(self) -> None:
        first = snapshot_from_flow(make_flow())
        second = snapshot_from_flow(
            make_flow(url="https://api.example.com/users/999?token=other&limit=50")
        )
        self.assertEqual(first.signature, second.signature)
        self.assertEqual(first.path_template, "/users/{int}")
        self.assertEqual(first.query_keys, ["limit", "token"])

    def test_secrets_are_redacted(self) -> None:
        snapshot = snapshot_from_flow(make_flow())
        encoded = json.dumps(snapshot.to_dict())
        self.assertNotIn("very-secret", encoded)
        self.assertNotIn("also-secret", encoded)
        self.assertIn("<redacted:", encoded)

    def test_json_shape_ignores_secret_values(self) -> None:
        first = snapshot_from_flow(
            make_flow(
                method="POST",
                request_body='{"username":"alice","password":"one","flags":[true]}',
                request_type="application/json",
            )
        )
        second = snapshot_from_flow(
            make_flow(
                method="POST",
                request_body='{"username":"bob","password":"two","flags":[false]}',
                request_type="application/json",
            )
        )
        self.assertEqual(first.signature, second.signature)
        self.assertNotIn("one", first.request_preview)

    def test_free_text_and_personal_values_are_redacted(self) -> None:
        snapshot = snapshot_from_flow(
            make_flow(
                response_body=(
                    '{"email":"alice@example.com","note":"Bearer abcdefghijklmnop",'
                    '"opaque":"aaaaaaaaaa.bbbbbbbbbb.cccccccc"}'
                )
            )
        )
        self.assertNotIn("alice@example.com", snapshot.response_preview)
        self.assertNotIn("abcdefghijklmnop", snapshot.response_preview)
        self.assertNotIn("aaaaaaaaaa.bbbbbbbbbb.cccccccc", snapshot.response_preview)


class MutationTests(unittest.TestCase):
    def test_safe_query_mutations_are_bounded(self) -> None:
        mutations = build_mutations(make_flow(), "safe", 2, False)
        self.assertEqual(len(mutations), 2)
        self.assertTrue(all(candidate.response is None for candidate, _, _ in mutations))

    def test_unsafe_method_requires_explicit_permission(self) -> None:
        with self.assertRaisesRegex(ValueError, "disabled"):
            build_mutations(
                make_flow(method="POST", request_body='{"name":"x"}', request_type="application/json"),
                "json",
                3,
                False,
            )

    def test_auth_mutation_removes_credentials(self) -> None:
        candidate, description, _ = build_mutations(make_flow(), "auth", 3, False)[0]
        self.assertNotIn("authorization", candidate.request.headers)
        self.assertIn("remove-auth", description)


class ComparisonTests(unittest.TestCase):
    def test_auth_success_and_server_error_are_findings(self) -> None:
        baseline = snapshot_from_flow(make_flow())
        auth_candidate = snapshot_from_flow(make_flow(response_body='{"ok":true}'))
        auth = compare_replay(baseline, auth_candidate, "remove-auth:authorization", "")
        self.assertIn("auth-removal-success", {finding.kind for finding in auth})

        error_candidate = snapshot_from_flow(
            make_flow(status=500, response_body="Traceback: SQL error", response_type="text/plain")
        )
        errors = compare_replay(baseline, error_candidate, "query:id:negative", "")
        kinds = {finding.kind for finding in errors}
        self.assertIn("server-error", kinds)
        self.assertIn("error-disclosure", kinds)


class StorageTests(unittest.TestCase):
    def test_endpoint_and_finding_deduplication(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            storage = Storage(Path(directory))
            snapshot = snapshot_from_flow(make_flow())
            self.assertTrue(storage.record_endpoint(snapshot))
            self.assertFalse(storage.record_endpoint(snapshot))
            self.assertEqual(storage.counts()["observations"], 2)

            candidate = snapshot_from_flow(make_flow())
            finding = compare_replay(
                snapshot, candidate, "remove-auth:authorization", ""
            )[0]
            finding_id, created = storage.add_finding(finding)
            self.assertTrue(created)
            self.assertFalse(storage.add_finding(finding)[1])
            stored = storage.get_finding(finding_id)
            self.assertIsNotNone(stored)
            self.assertEqual(stored["occurrences"], 2)
            self.assertTrue(storage.report_path.exists())


if __name__ == "__main__":
    unittest.main()
