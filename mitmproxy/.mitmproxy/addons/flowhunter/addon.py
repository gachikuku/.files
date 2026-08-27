from __future__ import annotations

import json
import os
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from mitmproxy import command, ctx, flow, http, types

from .ai import AIWorker, AnalysisTask, CodexAnalyzer
from .core import (
    Snapshot,
    build_mutations,
    compare_replay,
    host_in_scope,
    snapshot_from_flow,
)
from .storage import Storage


DEFAULT_DATA_DIR = os.path.expanduser("~/Developer/flowhunter-data")


class FlowHunterAddon:
    """Mitmproxy adapter; core behavior stays behind addon commands and options."""

    def __init__(self) -> None:
        self.storage: Storage | None = None
        self.ai_worker: AIWorker | None = None
        self._data_dir: str | None = None

    def load(self, loader: Any) -> None:
        loader.add_option(
            "flowhunter_data_dir",
            str,
            DEFAULT_DATA_DIR,
            "Directory for the redacted FlowHunter database and reports.",
        )
        loader.add_option(
            "flowhunter_scope",
            Sequence[str],
            [],
            "Exact hosts or *.example.com patterns FlowHunter may collect and replay.",
        )
        loader.add_option(
            "flowhunter_auto_replay",
            bool,
            False,
            "Replay the safe mutation profile once for each new endpoint.",
        )
        loader.add_option(
            "flowhunter_replay_profile",
            str,
            "safe",
            "Automatic replay profile: safe, auth, or json.",
        )
        loader.add_option(
            "flowhunter_allow_unsafe_methods",
            bool,
            False,
            "Allow mutation/replay of methods other than GET, HEAD, and OPTIONS.",
        )
        loader.add_option(
            "flowhunter_max_mutations",
            int,
            3,
            "Maximum mutations produced for one replay command or endpoint.",
        )
        loader.add_option(
            "flowhunter_ai_enabled",
            bool,
            False,
            "Send redacted, deduplicated summaries to an isolated Codex CLI worker.",
        )
        loader.add_option(
            "flowhunter_ai_timeout",
            int,
            120,
            "Timeout in seconds for one background Codex review.",
        )

    def configure(self, updated: set[str]) -> None:
        data_dir = os.path.expanduser(ctx.options.flowhunter_data_dir)
        if self.storage is None or data_dir != self._data_dir:
            self._stop_ai()
            self.storage = Storage(data_dir)
            self._data_dir = data_dir
        if ctx.options.flowhunter_ai_enabled:
            self._ensure_ai()
        else:
            self._stop_ai()

    def running(self) -> None:
        self._ensure_storage()
        if not list(ctx.options.flowhunter_scope):
            ctx.log.warn(
                "FlowHunter is loaded but inactive: set flowhunter_scope to authorized hosts"
            )
        else:
            ctx.log.info(
                f"FlowHunter collecting authorized scope into {ctx.options.flowhunter_data_dir}"
            )

    def response(self, current: http.HTTPFlow) -> None:
        if current.response is None or not self._in_scope(current.request.host):
            return
        replay_metadata = current.metadata.get("flowhunter_replay")
        if replay_metadata:
            self._handle_replay_response(current, replay_metadata)
            return
        snapshot = snapshot_from_flow(current)
        storage = self._ensure_storage()
        is_new = storage.record_endpoint(snapshot)
        if is_new:
            ctx.log.info(
                f"FlowHunter new endpoint {snapshot.signature}: "
                f"{snapshot.method} {snapshot.host}{snapshot.path_template}"
            )
            self._submit_ai(
                AnalysisTask(
                    signature=snapshot.signature,
                    subject_type="endpoint",
                    subject_id=None,
                    payload={"subject": "new endpoint", "snapshot": snapshot.to_dict()},
                )
            )
            if ctx.options.flowhunter_auto_replay:
                self._replay_flows([current], ctx.options.flowhunter_replay_profile)

    def done(self) -> None:
        self._stop_ai()
        if self.storage:
            self.storage.write_report()

    @command.command("flowhunter.status")
    def status(self) -> str:
        counts = self._ensure_storage().counts()
        value = {
            **counts,
            "scope": list(ctx.options.flowhunter_scope),
            "auto_replay": ctx.options.flowhunter_auto_replay,
            "replay_profile": ctx.options.flowhunter_replay_profile,
            "allow_unsafe_methods": ctx.options.flowhunter_allow_unsafe_methods,
            "ai_enabled": ctx.options.flowhunter_ai_enabled,
            "data_dir": ctx.options.flowhunter_data_dir,
        }
        message = json.dumps(value, sort_keys=True)
        ctx.log.alert(message)
        return message

    @command.command("flowhunter.replay")
    def replay(self, flows: types.Sequence[flow.Flow], profile: str = "safe") -> str:
        http_flows = [item for item in flows if isinstance(item, http.HTTPFlow)]
        count, errors = self._replay_flows(http_flows, profile)
        message = f"FlowHunter queued {count} replay mutation(s)"
        if errors:
            message += "; " + "; ".join(errors)
        ctx.log.alert(message)
        return message

    @command.command("flowhunter.report")
    def report(self) -> str:
        path = str(self._ensure_storage().write_report())
        ctx.log.alert(f"FlowHunter report: {path}")
        return path

    @command.command("flowhunter.ai")
    def ai(self, enabled: bool) -> str:
        ctx.options.update(flowhunter_ai_enabled=enabled)
        message = f"FlowHunter AI {'enabled' if enabled else 'disabled'}"
        ctx.log.alert(message)
        return message

    def _replay_flows(
        self,
        flows: Sequence[http.HTTPFlow],
        profile: str,
    ) -> tuple[int, list[str]]:
        count = 0
        errors: list[str] = []
        for original in flows:
            if original.response is None:
                errors.append("flow has no baseline response")
                continue
            if not self._in_scope(original.request.host):
                errors.append(f"out of scope: {original.request.host}")
                continue
            baseline = snapshot_from_flow(original)
            try:
                mutations = build_mutations(
                    original,
                    profile,
                    max(1, min(ctx.options.flowhunter_max_mutations, 20)),
                    ctx.options.flowhunter_allow_unsafe_methods,
                )
            except ValueError as error:
                errors.append(str(error))
                continue
            if not mutations:
                errors.append(f"no {profile} mutations available for {baseline.signature}")
                continue
            for replay_flow, mutation, marker in mutations:
                replay_flow.metadata["flowhunter_replay"] = {
                    "baseline": baseline.to_dict(),
                    "profile": profile,
                    "mutation": mutation,
                    "marker": marker,
                }
                ctx.master.commands.call("replay.client", [replay_flow])
                count += 1
        return count, errors

    def _handle_replay_response(
        self,
        current: http.HTTPFlow,
        metadata: dict[str, Any],
    ) -> None:
        baseline = Snapshot.from_dict(metadata["baseline"])
        replay = snapshot_from_flow(current)
        profile = str(metadata.get("profile", "unknown"))
        mutation = str(metadata.get("mutation", "unknown"))
        marker = str(metadata.get("marker", ""))
        storage = self._ensure_storage()
        storage.record_replay(baseline, replay, profile, mutation)
        for finding in compare_replay(baseline, replay, mutation, marker):
            finding_id, created = storage.add_finding(finding)
            if created:
                ctx.log.alert(
                    f"FlowHunter [{finding.severity}] {finding.title} ({finding_id})"
                )
                self._submit_ai(
                    AnalysisTask(
                        signature=finding.signature,
                        subject_type="finding",
                        subject_id=finding_id,
                        payload={
                            "subject": "deterministic replay anomaly",
                            "finding": {
                                "id": finding_id,
                                "kind": finding.kind,
                                "severity": finding.severity,
                                "title": finding.title,
                                "evidence": finding.evidence,
                            },
                            "baseline": baseline.to_dict(),
                            "replay": replay.to_dict(),
                        },
                    )
                )

    def _in_scope(self, host: str) -> bool:
        return host_in_scope(host, ctx.options.flowhunter_scope)

    def _ensure_storage(self) -> Storage:
        if self.storage is None:
            data_dir = os.path.expanduser(
                getattr(ctx.options, "flowhunter_data_dir", DEFAULT_DATA_DIR)
            )
            self.storage = Storage(data_dir)
            self._data_dir = data_dir
        return self.storage

    def _ensure_ai(self) -> AIWorker:
        if self.ai_worker is None:
            storage = self._ensure_storage()
            analyzer = CodexAnalyzer(
                Path(storage.data_dir),
                timeout_seconds=ctx.options.flowhunter_ai_timeout,
            )
            self.ai_worker = AIWorker(
                analyzer,
                on_review=self._on_ai_review,
                on_log=ctx.log.warn,
            )
        return self.ai_worker

    def _submit_ai(self, task: AnalysisTask) -> None:
        if ctx.options.flowhunter_ai_enabled:
            self._ensure_ai().submit(task)

    def _on_ai_review(self, task: AnalysisTask, review: dict[str, Any]) -> None:
        self._ensure_storage().add_ai_review(
            task.signature,
            task.subject_type,
            task.subject_id,
            review,
        )
        ctx.log.alert(
            f"FlowHunter AI [{review.get('severity', 'info')}] "
            f"{review.get('title', task.signature)}"
        )

    def _stop_ai(self) -> None:
        if self.ai_worker:
            self.ai_worker.stop()
            self.ai_worker = None
