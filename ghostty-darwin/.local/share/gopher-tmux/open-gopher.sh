#!/bin/sh
set -eu

# Choose your Gopher browser: sacc or w3m. Takes effect on the next link click.
browser=sacc

# Launch Services does not inherit the interactive shell's Nix PATH.
PATH="/run/current-system/sw/bin:$HOME/.nix-profile/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export PATH

fail() { printf '%s\n' "$*" >&2; exit 1; }
[ "$#" -eq 1 ] || fail 'Usage: open-gopher.sh <gopher-url>'
url=$1
case "$url" in
    gopher://?*|gophers://?*) ;;
    *) fail 'Expected a gopher:// or gophers:// URL with a host' ;;
esac
host=${url#*://}
host=${host%%[/?#]*}
[ -n "$host" ] || fail 'URL has no host'
if printf '%s' "$url" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    fail 'URL contains a control character'
fi
# grep treats newlines as record separators, so check them separately.
case "$url" in *'
'*) fail 'URL contains a newline' ;; esac
tmux=$(command -v tmux) || fail 'tmux must be installed'
case "$browser" in
    sacc|w3m) ;;
    *) fail 'Set browser to sacc or w3m at the top of open-gopher.sh' ;;
esac
browser_command=$(command -v "$browser") || fail "$browser must be installed"

socket_paths() {
    if [ -n "${TMUX:-}" ]; then
        socket=${TMUX%,*}
        printf '%s\n' "${socket%,*}"
    fi
    for socket in /tmp/tmux-"$(id -u)"/* "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"/*; do
        [ ! -S "$socket" ] || printf '%s\n' "$socket"
    done
}

# Select the most recently active attached client, including named servers.
tab=$(printf '\t')
target=$(
    socket_paths | sort -u | while IFS= read -r socket; do
        "$tmux" -S "$socket" list-clients -F "#{client_activity}${tab}#{session_id}" 2>/dev/null |
            while IFS="$tab" read -r activity session; do
                printf '%s\t%s\t%s\n' "$activity" "$session" "$socket"
            done
    done | sort -rn | head -n 1
)
[ -n "$target" ] || fail 'No attached tmux session. Attach a session in Ghostty first.'
IFS="$tab" read -r activity session socket <<EOF
$target
EOF

# Separate command arguments make tmux exec the browser without a shell.
exec "$tmux" -S "$socket" new-window -t "$session:" -n "$browser" "$browser_command" "$url"
