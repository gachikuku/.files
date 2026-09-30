#!/bin/sh
set -eu

fixture=/nix/store/w7wxgb11s11a6qghbjbzp62s4f0p3aj2-source/src/config/url.zig
[ -f "$fixture" ] || {
    printf 'Nix source fixture is missing: %s\n' "$fixture" >&2
    exit 1
}

before_ids=$(tmux list-windows -a -F '#{window_id}' | tr '\n' ' ')
/usr/bin/open "$fixture"
sleep 1

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
    printf 'FAIL: system open created no tmux window for the Nix Zig source\n' >&2
    exit 1
}
command=$(tmux display-message -p -t "$new_id" '#{pane_current_command}')
tmux kill-window -t "$new_id"
[ "$command" = vim ] || {
    printf 'FAIL: Nix Zig source launched %s instead of vim\n' "$command" >&2
    exit 1
}

printf 'PASS: system open routes the Nix Zig source to Vim in tmux\n'
