#!/bin/sh
set -eu

app="$HOME/Applications/Vim in tmux.app"
target=${1:-"$HOME/.local/share/vim-tmux/README.md"}

[ -d "$app" ] || { printf 'Handler app is not installed: %s\n' "$app" >&2; exit 1; }
[ -f "$target" ] || { printf 'Test file does not exist: %s\n' "$target" >&2; exit 1; }
handler=$(duti -x md 2>/dev/null | tail -n 1)
[ "$handler" = local.gachikuku.vim-tmux ] || {
    printf 'FAIL: Markdown resolves to %s instead of the tmux Vim handler\n' "$handler" >&2
    exit 1
}

before_ids=$(tmux list-windows -a -F '#{window_id}' | tr '\n' ' ')
open "$target"
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
    printf 'FAIL: opening a document created no tmux window\n' >&2
    exit 1
}

command=$(tmux display-message -p -t "$new_id" '#{pane_current_command}')
if [ "$command" != vim ]; then
    tmux kill-window -t "$new_id"
    printf 'FAIL: new tmux window runs %s instead of vim\n' "$command" >&2
    exit 1
fi

tmux kill-window -t "$new_id"
printf 'PASS: document opened in a new tmux Vim window\n'
