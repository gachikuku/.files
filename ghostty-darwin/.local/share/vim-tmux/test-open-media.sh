#!/bin/sh
set -eu

fake_mpv="$HOME/.local/share/vim-tmux/fixtures/mpv"

test_media_target() {
    target=$1
    before_ids=$(tmux list-windows -a -F '#{window_id}' | tr '\n' ' ')
    VIM_TMUX_GHOSTTY_OPEN_TEST=1 VIM_TMUX_MPV_COMMAND="$fake_mpv" \
        "$HOME/bin/open" "$target"
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
        printf 'FAIL: media target created no tmux window: %s\n' "$target" >&2
        exit 1
    }
    name=$(tmux display-message -p -t "$new_id" '#{window_name}')
    tmux kill-window -t "$new_id"
    [ "$name" = mpv ] || {
        printf 'FAIL: media window is named %s instead of mpv\n' "$name" >&2
        exit 1
    }
}

test_media_target 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'
test_media_target 'https://media.example/video.mp4?token=test'
printf 'PASS: YouTube and direct media links route to mpv in tmux\n'
