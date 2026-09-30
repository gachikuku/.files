#!/bin/sh
set -eu

# Launch Services does not inherit the interactive shell's Nix PATH.
PATH="/run/current-system/sw/bin:$HOME/.nix-profile/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export PATH

fail() { printf '%s\n' "$*" >&2; exit 1; }
[ "$#" -eq 1 ] || fail 'Usage: open-file.sh <absolute-path[:line[:column]]>'
spec=$1

if printf '%s' "$spec" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    fail 'Path contains a control character'
fi
case "$spec" in *'
'*) fail 'Path contains a newline' ;; esac
case "$spec" in /*) ;; *) fail 'Expected an absolute path' ;; esac

path=$spec
line=
column=
if [ ! -e "$path" ]; then
    final=${spec##*:}
    before_final=${spec%:*}
    case "$final" in
        ''|*[!0-9]*) ;;
        *)
            possible_line=${before_final##*:}
            before_line=${before_final%:*}
            case "$possible_line" in
                ''|*[!0-9]*) ;;
                *)
                    if [ -e "$before_line" ]; then
                        path=$before_line
                        line=$possible_line
                        column=$final
                    fi
                    ;;
            esac
            if [ -z "$line" ] && [ -e "$before_final" ]; then
                path=$before_final
                line=$final
            fi
            ;;
    esac
fi
[ -e "$path" ] || fail "File does not exist: $path"

# Directories belong to Finder. This helper only redirects files to Vim.
if [ -d "$path" ]; then
    exec /usr/bin/open "$path"
fi

tmux=$(command -v tmux) || fail 'tmux must be installed'
vim=$(command -v vim) || fail 'vim must be installed'

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

cwd=${path%/*}
[ -n "$cwd" ] || cwd=/

if [ -n "$column" ]; then
    exec "$tmux" -S "$socket" new-window -t "$session:" -n vim -c "$cwd" \
        "$vim" "+call cursor($line,$column)" -- "$path"
elif [ -n "$line" ]; then
    exec "$tmux" -S "$socket" new-window -t "$session:" -n vim -c "$cwd" \
        "$vim" "+$line" -- "$path"
else
    exec "$tmux" -S "$socket" new-window -t "$session:" -n vim -c "$cwd" \
        "$vim" -- "$path"
fi
