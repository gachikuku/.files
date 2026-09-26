#!/bin/sh
set -eu

fixture="$HOME/.local/share/vim-tmux/fixtures/should-open-in-vim"
marker=/tmp/vim-tmux-executable-was-run

[ -x "$fixture" ] || { printf 'Executable fixture is missing: %s\n' "$fixture" >&2; exit 1; }
find "$marker" -maxdepth 0 -type f -delete 2>/dev/null || true

before_ids=$(tmux list-windows -a -F '#{window_id}' | tr '\n' ' ')
open "$fixture"
sleep 1

if [ -f "$marker" ]; then
    find "$marker" -maxdepth 0 -type f -delete
    printf 'FAIL: macOS executed the file instead of opening it in Vim\n' >&2
    exit 1
fi

new_id=$(
    tmux list-windows -a -F '#{window_id}' | while IFS= read -r id; do
        if printf ' %s ' "$before_ids" | grep -Fq " $id "; then
            continue
        fi
        printf '%s\n' "$id"
        break
    done
)

[ -n "$new_id" ] || {
    printf 'FAIL: opening the executable created no tmux window\n' >&2
    exit 1
}

command=$(tmux display-message -p -t "$new_id" '#{pane_current_command}')
tmux kill-window -t "$new_id"
[ "$command" = vim ] || {
    printf 'FAIL: new tmux window runs %s instead of vim\n' "$command" >&2
    exit 1
}

printf 'PASS: executable opened in a new tmux Vim window without running\n'
