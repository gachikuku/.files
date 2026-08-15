#!/bin/dash

set -eu

trash_session='__window_undo'
keep_windows=25

list_closed_windows()
{
    tmux list-windows -t "$trash_session" \
        -F '#{@window_undo_sequence} #{window_id}' 2>/dev/null |
        awk '$1 ~ /^[0-9]+$/ { print $1, $2 }' |
        sort -n
}

ensure_trash_session()
{
    if ! tmux has-session -t "=$trash_session" 2>/dev/null
    then
        tmux new-session -d -s "$trash_session" -n '__keepalive'
    fi
}

next_sequence()
{
    sequence=$(tmux show-options -gv @window_undo_counter 2>/dev/null || true)
    case "$sequence" in
        ''|*[!0-9]*) sequence=0 ;;
    esac
    sequence=$((sequence + 1))
    tmux set-option -g @window_undo_counter "$sequence"
    printf '%s\n' "$sequence"
}

prune_closed_windows()
{
    while [ "$(list_closed_windows | wc -l | tr -d ' ')" -gt "$keep_windows" ]
    do
        oldest=$(list_closed_windows | awk 'NR == 1 { print $2 }')
        [ -n "$oldest" ] || break
        tmux kill-window -t "$oldest"
    done
}

close_window()
{
    origin_session=$1
    window_id=$2
    origin_index=$3

    origin_name=$(tmux display-message -p -t "$origin_session" '#{session_name}')
    [ "$origin_name" != "$trash_session" ] || exit 1

    ensure_trash_session

    # Keep the client attached if its final window is removed.
    window_count=$(tmux display-message -p -t "$origin_session" '#{session_windows}')
    if [ "$window_count" -eq 1 ]
    then
        tmux new-window -d -t "$origin_session:" -n shell
    fi

    tmux set-option -w -t "$window_id" @window_undo_sequence "$(next_sequence)"
    tmux set-option -w -t "$window_id" @window_undo_origin_index "$origin_index"
    tmux move-window -s "$window_id" -t "$trash_session:"
    prune_closed_windows
}

restore_window()
{
    target_session=$1

    if ! tmux has-session -t "=$trash_session" 2>/dev/null
    then
        tmux display-message 'No recently killed windows'
        exit 0
    fi

    window_id=$(list_closed_windows | awk 'END { print $2 }')
    if [ -z "$window_id" ]
    then
        tmux display-message 'No recently killed windows'
        exit 0
    fi

    origin_index=$(tmux show-options -wv -t "$window_id" @window_undo_origin_index 2>/dev/null || true)
    case "$origin_index" in
        ''|*[!0-9]*) destination="$target_session:" ;;
        *)
            if tmux list-windows -t "$target_session" -F '#{window_index}' | grep -qx "$origin_index"
            then
                destination="$target_session:"
            else
                destination="$target_session:$origin_index"
            fi
            ;;
    esac

    tmux move-window -s "$window_id" -t "$destination"
    tmux set-option -wu -t "$window_id" @window_undo_sequence 2>/dev/null || true
    tmux set-option -wu -t "$window_id" @window_undo_origin_index 2>/dev/null || true
    tmux select-window -t "$window_id"
}

case "${1:-}" in
    close)   close_window "$2" "$3" "$4" ;;
    restore) restore_window "$2" ;;
    *) exit 2 ;;
esac
