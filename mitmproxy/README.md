# FlowHunter mitmproxy addon

FlowHunter passively deduplicates authorized HTTP(S) traffic, offers bounded
request mutation/replay, compares replay responses with their baselines, and
writes redacted findings that humans or Codex can review.

The addon is loaded by `.mitmproxy/config.yaml`, but it is inert until an
explicit scope is supplied. Runtime data defaults to
`~/Developer/flowhunter-data`; generated captures and findings do not belong in
the dotfiles repository.

## Start safely

Configure the iPhone to use this Mac's proxy, then start mitmproxy with the
exact authorized application hosts. Repeat `--set flowhunter_scope=...` for
multiple hosts:

```sh
mitmproxy \
  --set flowhunter_scope=api.example.com \
  --set flowhunter_scope=*.example.com
```

Automatic replay is enabled by default and runs once for each new endpoint
signature in the authorized scope. FlowHunter stores redacted endpoint summaries;
use mitmproxy's `-w` flag separately if an encrypted-at-rest raw capture is
actually required.

## TUI commands

Focus a completed flow before replaying it:

```text
:flowhunter.status
:flowhunter.replay @focus safe
:flowhunter.replay @focus auth
:flowhunter.replay @focus json
:flowhunter.replay @focus all
:flowhunter.report
:flowhunter.ai true
```

Profiles:

- `safe` changes existing query values.
- `auth` removes Authorization, Cookie, and X-API-Key headers; verify every
  result manually because a `2xx` response alone does not prove an auth issue.
- `json` changes one JSON primitive.
- `all` combines auth removal, JSON mutation, and every bounded query mutation.

Replay and mutation are allowed for every HTTP method. `DELETE` is allowed only
when its URL, query, or body contains a `flowhunter-...` ownership marker;
unknown data remains blocked. State-changing effects still require an authorized
target and should be understood before enabling automatic replay.

Automatic replay defaults to the `all` profile with up to 20 mutations and runs
once for each new endpoint signature:

```sh
mitmproxy \
  --set flowhunter_scope=api.example.com
```

Disable it with `--set flowhunter_auto_replay=false`.

## Codex review

AI review is enabled by default. It starts one background worker that passes only
redacted, deduplicated summaries to `codex exec` using an ephemeral, read-only run
and a strict JSON output schema:

```text
:flowhunter.ai true
```

Disable it with `:flowhunter.ai false` or `--set flowhunter_ai_enabled=false`.
The AI reviews evidence; active requests come from the validated `all` mutation
profile rather than arbitrary model-generated network commands.

Captured content is untrusted and may contain prompt injection. The worker
instructs Codex not to use tools and runs it read-only, but AI output remains
unverified triage—not a vulnerability report.

Inspect results outside mitmproxy:

```sh
flowhunter status
flowhunter endpoints
flowhunter findings --unreviewed
flowhunter show fh-0123456789abcdef
flowhunter watch --interval .5  # live endpoint activity and findings
flowhunter codex-context
flowhunter report
```

The stable files for other tools are:

```text
~/Developer/flowhunter-data/flowhunter.sqlite3
~/Developer/flowhunter-data/findings.jsonl
~/Developer/flowhunter-data/report.md
```

`flowhunter codex-context` is the preferred bounded interface for asking Codex
to review current results. A local addon cannot inject unsolicited messages into
an existing Codex conversation; an external polling automation would be needed
for push-style notifications.
