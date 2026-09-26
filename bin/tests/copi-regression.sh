#!/bin/sh

set -eu

copi=/Users/gachikuku/bin/copi
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/copi-test.XXXXXX")

cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup 0 1 2 15

mkdir -p "$tmpdir/sessions"
state_db="$tmpdir/state.sqlite"
history_db="$tmpdir/history.sqlite"
printf '%s\n' '{"payload":"ordinary old content"}' >"$tmpdir/sessions/old.jsonl"
printf '%s\n' '{"payload":"needle only in the raw rollout"}' >"$tmpdir/sessions/new.jsonl"

sqlite3 "$state_db" <<'SQL'
CREATE TABLE threads (
  id TEXT PRIMARY KEY,
  rollout_path TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  source TEXT NOT NULL,
  cwd TEXT NOT NULL,
  title TEXT NOT NULL,
  archived INTEGER NOT NULL DEFAULT 0,
  first_user_message TEXT NOT NULL DEFAULT '',
  agent_path TEXT,
  created_at_ms INTEGER,
  updated_at_ms INTEGER,
  preview TEXT NOT NULL DEFAULT '',
  recency_at_ms INTEGER NOT NULL DEFAULT 0,
  name TEXT,
  model TEXT,
  originator TEXT
);
INSERT INTO threads VALUES
  ('older', '/does/not/exist-old', 100, 200, 'cli', '/tmp/old', 'Older session', 0,
   'old question', NULL, 100000, 200000, 'old preview', 200000, NULL, 'model-old', NULL),
  ('newest', '/does/not/exist-new', 300, 400, 'cli', '/tmp/new', 'Newest session', 0,
   'new question', NULL, 300000, 400000, 'new preview', 400000, NULL, 'model-new', NULL),
  ('exec-hidden', '/does/not/exist-exec', 500, 500, 'exec', '/tmp/exec', 'Hidden exec', 0,
   'hidden', NULL, 500000, 500000, 'hidden', 500000, NULL, 'model-exec', 'codex_exec');
SQL

sqlite3 "$state_db" "
UPDATE threads SET rollout_path = '$tmpdir/sessions/old.jsonl' WHERE id = 'older';
UPDATE threads SET rollout_path = '$tmpdir/sessions/new.jsonl' WHERE id = 'newest';
"

sqlite3 "$history_db" <<'SQL'
CREATE TABLE thread_items (
  thread_id TEXT NOT NULL,
  rollout_ordinal INTEGER NOT NULL,
  item_json TEXT NOT NULL,
  item_type TEXT NOT NULL
);
CREATE INDEX thread_items_page ON thread_items(thread_id, rollout_ordinal);
INSERT INTO thread_items VALUES
  ('newest', 1, '{"type":"userMessage","content":[{"type":"text","text":"first message"}]}', 'userMessage'),
  ('newest', 2, '{"type":"agentMessage","text":"latest answer"}', 'agentMessage');
SQL

rows=$(CODEX_HOME="$tmpdir" COPI_STATE_DB="$state_db" COPI_HISTORY_DB="$history_db" "$copi" --list)

count=$(printf '%s\n' "$rows" | awk 'NF { count++ } END { print count + 0 }')
[ "$count" -eq 2 ] || {
  echo "FAIL: expected 2 interactive sessions, got $count" >&2
  exit 1
}

first_id=$(printf '%s\n' "$rows" | awk -F '\t' 'NR == 1 { print $6 }')
[ "$first_id" = newest ] || {
  echo "FAIL: newest session was not first (got $first_id)" >&2
  exit 1
}

preview=$(CODEX_HOME="$tmpdir" COPI_STATE_DB="$state_db" COPI_HISTORY_DB="$history_db" "$copi" --preview newest)
printf '%s\n' "$preview" | grep -F '>> first message' >/dev/null || {
  echo "FAIL: preview omitted the user message" >&2
  exit 1
}
printf '%s\n' "$preview" | grep -F '   latest answer' >/dev/null || {
  echo "FAIL: preview omitted the assistant message" >&2
  exit 1
}

deep_rows=$(CODEX_HOME="$tmpdir" COPI_STATE_DB="$state_db" COPI_HISTORY_DB="$history_db" "$copi" --grep-rows needle)
deep_id=$(printf '%s\n' "$deep_rows" | awk -F '\t' 'NR == 1 { print $6 }')
[ "$deep_id" = newest ] || {
  echo "FAIL: deep grep did not map the rollout match back to its session (got $deep_id)" >&2
  exit 1
}
[ "$(printf '%s\n' "$deep_rows" | awk 'NF { count++ } END { print count + 0 }')" -eq 1 ] || {
  echo "FAIL: deep grep returned a session without a raw rollout match" >&2
  exit 1
}

no_match=$(CODEX_HOME="$tmpdir" COPI_STATE_DB="$state_db" COPI_HISTORY_DB="$history_db" "$copi" --grep-rows absent-value)
[ -z "$no_match" ] || {
  echo "FAIL: deep grep should return an empty successful result for fzf reload" >&2
  exit 1
}

echo "PASS: indexed listing, preview, newest-first order, and streaming deep grep"
