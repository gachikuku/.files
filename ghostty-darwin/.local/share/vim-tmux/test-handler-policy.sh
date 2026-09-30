#!/bin/sh
set -eu

fixture="$HOME/.local/share/vim-tmux/fixtures/should-open-in-vim.txt"
before_ids=$(tmux list-windows -a -F '#{window_id}' | tr '\n' ' ')
open "$fixture"
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
    printf 'FAIL: TextEdit-owned .txt file created no tmux window\n' >&2
    exit 1
}
command=$(tmux display-message -p -t "$new_id" '#{pane_current_command}')
tmux kill-window -t "$new_id"
[ "$command" = vim ] || {
    printf 'FAIL: .txt window runs %s instead of vim\n' "$command" >&2
    exit 1
}

for extension in js mjs; do
    handler=$(duti -x "$extension" 2>/dev/null | awk 'NR == 3 {print}')
    [ "$handler" = org.chromium.Chromium ] || {
        printf 'FAIL: .%s belongs to %s instead of Chromium\n' "$extension" "$handler" >&2
        exit 1
    }
done

json_handler=$(duti -x json 2>/dev/null | awk 'NR == 3 {print}')
[ "$json_handler" = local.gachikuku.vim-tmux ] || {
    printf 'FAIL: .json belongs to %s instead of Vim in tmux\n' "$json_handler" >&2
    exit 1
}

json_fixture="$HOME/.local/share/vim-tmux/fixtures/should-open-in-vim.json"
before_ids=$(tmux list-windows -a -F '#{window_id}' | tr '\n' ' ')
/usr/bin/open "$json_fixture"
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
    printf 'FAIL: opening .json created no tmux window\n' >&2
    exit 1
}
command=$(tmux display-message -p -t "$new_id" '#{pane_current_command}')
tmux kill-window -t "$new_id"
[ "$command" = vim ] || {
    printf 'FAIL: .json window runs %s instead of vim\n' "$command" >&2
    exit 1
}

printf 'PASS: TextEdit and JSON files use Vim; Chromium associations are preserved\n'
