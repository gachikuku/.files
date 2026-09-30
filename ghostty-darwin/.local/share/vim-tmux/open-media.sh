#!/bin/sh
set -eu

PATH="/run/current-system/sw/bin:$HOME/.nix-profile/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export PATH

fail() { printf '%s\n' "$*" >&2; exit 1; }
[ "$#" -eq 1 ] || fail 'Usage: open-media.sh <path-or-url>'
target=$1
if printf '%s' "$target" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    fail 'Media target contains a control character'
fi
case "$target" in *'
'*) fail 'Media target contains a newline' ;; esac

tmux=$(command -v tmux) || fail 'tmux must be installed'
if [ -n "${VIM_TMUX_MPV_COMMAND:-}" ]; then
    mpv=$VIM_TMUX_MPV_COMMAND
else
    mpv=$(command -v mpv) || fail 'mpv must be installed'
fi
[ -x "$mpv" ] || fail "mpv command is not executable: $mpv"

socket_paths() {
    if [ -n "${TMUX:-}" ]; then
        socket=${TMUX%,*}
        printf '%s\n' "${socket%,*}"
    fi
    for socket in /tmp/tmux-"$(id -u)"/* "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"/*; do
        [ ! -S "$socket" ] || printf '%s\n' "$socket"
    done
}

tab=$(printf '\t')
destination=$(
    socket_paths | sort -u | while IFS= read -r socket; do
        "$tmux" -S "$socket" list-clients -F "#{client_activity}${tab}#{session_id}" 2>/dev/null |
            while IFS="$tab" read -r activity session; do
                printf '%s\t%s\t%s\n' "$activity" "$session" "$socket"
            done
    done | sort -rn | head -n 1
)
[ -n "$destination" ] || fail 'No attached tmux session. Attach a session in Ghostty first.'
IFS="$tab" read -r activity session socket <<EOF
$destination
EOF

exec "$tmux" -S "$socket" new-window -t "$session:" -n mpv "$mpv" -- "$target"
