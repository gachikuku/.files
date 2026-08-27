from __future__ import annotations

import json
import sqlite3
import threading
import time
from pathlib import Path
from typing import Any

from .core import Finding, Snapshot


SCHEMA = """
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS endpoints (
    signature TEXT PRIMARY KEY,
    method TEXT NOT NULL,
    host TEXT NOT NULL,
    path_template TEXT NOT NULL,
    first_seen REAL NOT NULL,
    last_seen REAL NOT NULL,
    observation_count INTEGER NOT NULL,
    sample_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS replays (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    signature TEXT NOT NULL,
    created_at REAL NOT NULL,
    profile TEXT NOT NULL,
    mutation TEXT NOT NULL,
    baseline_json TEXT NOT NULL,
    replay_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS findings (
    id TEXT PRIMARY KEY,
    signature TEXT NOT NULL,
    kind TEXT NOT NULL,
    severity TEXT NOT NULL,
    title TEXT NOT NULL,
    first_seen REAL NOT NULL,
    last_seen REAL NOT NULL,
    occurrences INTEGER NOT NULL,
    reviewed INTEGER NOT NULL DEFAULT 0,
    evidence_json TEXT NOT NULL,
    ai_review_json TEXT
);

CREATE TABLE IF NOT EXISTS ai_reviews (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    signature TEXT NOT NULL,
    created_at REAL NOT NULL,
    subject_type TEXT NOT NULL,
    subject_id TEXT,
    review_json TEXT NOT NULL
);
"""


class Storage:
    """SQLite-backed persistence behind a small addon/CLI interface."""

    def __init__(self, data_dir: str | Path):
        self.data_dir = Path(data_dir).expanduser().resolve()
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.db_path = self.data_dir / "flowhunter.sqlite3"
        self.findings_path = self.data_dir / "findings.jsonl"
        self.report_path = self.data_dir / "report.md"
        self._write_lock = threading.Lock()
        with self._connect() as connection:
            connection.executescript(SCHEMA)

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.db_path, timeout=10)
        connection.row_factory = sqlite3.Row
        return connection

    def record_endpoint(self, snapshot: Snapshot) -> bool:
        sample = json.dumps(snapshot.to_dict(), sort_keys=True)
        with self._write_lock, self._connect() as connection:
            row = connection.execute(
                "SELECT 1 FROM endpoints WHERE signature = ?", (snapshot.signature,)
            ).fetchone()
            if row:
                connection.execute(
                    """
                    UPDATE endpoints
                    SET last_seen = ?, observation_count = observation_count + 1, sample_json = ?
                    WHERE signature = ?
                    """,
                    (snapshot.timestamp, sample, snapshot.signature),
                )
                return False
            connection.execute(
                """
                INSERT INTO endpoints (
                    signature, method, host, path_template, first_seen, last_seen,
                    observation_count, sample_json
                ) VALUES (?, ?, ?, ?, ?, ?, 1, ?)
                """,
                (
                    snapshot.signature,
                    snapshot.method,
                    snapshot.host,
                    snapshot.path_template,
                    snapshot.timestamp,
                    snapshot.timestamp,
                    sample,
                ),
            )
            return True

    def record_replay(
        self,
        baseline: Snapshot,
        replay: Snapshot,
        profile: str,
        mutation: str,
    ) -> None:
        with self._write_lock, self._connect() as connection:
            connection.execute(
                """
                INSERT INTO replays (
                    signature, created_at, profile, mutation, baseline_json, replay_json
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    baseline.signature,
                    time.time(),
                    profile,
                    mutation,
                    json.dumps(baseline.to_dict(), sort_keys=True),
                    json.dumps(replay.to_dict(), sort_keys=True),
                ),
            )

    def add_finding(self, finding: Finding) -> tuple[str, bool]:
        now = time.time()
        evidence = json.dumps(finding.evidence, sort_keys=True)
        with self._write_lock, self._connect() as connection:
            existing = connection.execute(
                "SELECT occurrences FROM findings WHERE id = ?", (finding.finding_id,)
            ).fetchone()
            if existing:
                connection.execute(
                    """
                    UPDATE findings
                    SET last_seen = ?, occurrences = occurrences + 1, evidence_json = ?
                    WHERE id = ?
                    """,
                    (now, evidence, finding.finding_id),
                )
                created = False
            else:
                connection.execute(
                    """
                    INSERT INTO findings (
                        id, signature, kind, severity, title, first_seen, last_seen,
                        occurrences, evidence_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)
                    """,
                    (
                        finding.finding_id,
                        finding.signature,
                        finding.kind,
                        finding.severity,
                        finding.title,
                        now,
                        now,
                        evidence,
                    ),
                )
                created = True
        if created:
            self._append_jsonl(
                {
                    "id": finding.finding_id,
                    "signature": finding.signature,
                    "kind": finding.kind,
                    "severity": finding.severity,
                    "title": finding.title,
                    "created_at": now,
                    "evidence": finding.evidence,
                }
            )
            self.write_report()
        return finding.finding_id, created

    def add_ai_review(
        self,
        signature: str,
        subject_type: str,
        subject_id: str | None,
        review: dict[str, Any],
    ) -> None:
        encoded = json.dumps(review, sort_keys=True)
        with self._write_lock, self._connect() as connection:
            connection.execute(
                """
                INSERT INTO ai_reviews (signature, created_at, subject_type, subject_id, review_json)
                VALUES (?, ?, ?, ?, ?)
                """,
                (signature, time.time(), subject_type, subject_id, encoded),
            )
            if subject_id:
                connection.execute(
                    "UPDATE findings SET ai_review_json = ? WHERE id = ?",
                    (encoded, subject_id),
                )
        self.write_report()

    def _append_jsonl(self, value: dict[str, Any]) -> None:
        with self.findings_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(value, sort_keys=True) + "\n")

    def counts(self) -> dict[str, int]:
        with self._connect() as connection:
            return {
                "endpoints": connection.execute("SELECT COUNT(*) FROM endpoints").fetchone()[0],
                "observations": connection.execute(
                    "SELECT COALESCE(SUM(observation_count), 0) FROM endpoints"
                ).fetchone()[0],
                "replays": connection.execute("SELECT COUNT(*) FROM replays").fetchone()[0],
                "findings": connection.execute("SELECT COUNT(*) FROM findings").fetchone()[0],
                "unreviewed_findings": connection.execute(
                    "SELECT COUNT(*) FROM findings WHERE reviewed = 0"
                ).fetchone()[0],
                "ai_reviews": connection.execute("SELECT COUNT(*) FROM ai_reviews").fetchone()[0],
            }

    def list_endpoints(self, limit: int = 100) -> list[dict[str, Any]]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT signature, method, host, path_template, first_seen, last_seen,
                       observation_count
                FROM endpoints ORDER BY last_seen DESC LIMIT ?
                """,
                (limit,),
            ).fetchall()
        return [dict(row) for row in rows]

    def list_findings(self, unreviewed: bool = False, limit: int = 100) -> list[dict[str, Any]]:
        where = "WHERE reviewed = 0" if unreviewed else ""
        with self._connect() as connection:
            rows = connection.execute(
                f"""
                SELECT id, signature, kind, severity, title, first_seen, last_seen,
                       occurrences, reviewed, evidence_json, ai_review_json
                FROM findings {where} ORDER BY last_seen DESC LIMIT ?
                """,
                (limit,),
            ).fetchall()
        return [self._decode_finding(dict(row)) for row in rows]

    def get_finding(self, finding_id: str) -> dict[str, Any] | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM findings WHERE id = ?", (finding_id,)
            ).fetchone()
        return self._decode_finding(dict(row)) if row else None

    def mark_reviewed(self, finding_id: str) -> bool:
        with self._write_lock, self._connect() as connection:
            cursor = connection.execute(
                "UPDATE findings SET reviewed = 1 WHERE id = ?", (finding_id,)
            )
        self.write_report()
        return cursor.rowcount > 0

    @staticmethod
    def _decode_finding(row: dict[str, Any]) -> dict[str, Any]:
        row["evidence"] = json.loads(row.pop("evidence_json"))
        ai_review = row.pop("ai_review_json")
        row["ai_review"] = json.loads(ai_review) if ai_review else None
        row["reviewed"] = bool(row["reviewed"])
        return row

    def write_report(self) -> Path:
        counts = self.counts()
        findings = self.list_findings(limit=500)
        lines = [
            "# FlowHunter report",
            "",
            f"- Endpoints: {counts['endpoints']}",
            f"- Observations: {counts['observations']}",
            f"- Replays: {counts['replays']}",
            f"- Findings: {counts['findings']} ({counts['unreviewed_findings']} unreviewed)",
            f"- AI reviews: {counts['ai_reviews']}",
            "",
        ]
        if not findings:
            lines.append("No findings yet.")
        for item in findings:
            lines.extend(
                [
                    f"## [{item['severity'].upper()}] {item['title']}",
                    "",
                    f"- ID: `{item['id']}`",
                    f"- Endpoint: `{item['signature']}`",
                    f"- Kind: `{item['kind']}`",
                    f"- Occurrences: {item['occurrences']}",
                    f"- Reviewed: {item['reviewed']}",
                    "",
                    "```json",
                    json.dumps(item["evidence"], indent=2, sort_keys=True),
                    "```",
                    "",
                ]
            )
            if item["ai_review"]:
                lines.extend(
                    [
                        "AI triage (unverified):",
                        "",
                        "```json",
                        json.dumps(item["ai_review"], indent=2, sort_keys=True),
                        "```",
                        "",
                    ]
                )
        self.report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return self.report_path
