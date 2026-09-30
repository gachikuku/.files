#!/bin/sh
set -eu

test_vim_target() {
    target=$1
    expected_cwd=$(CDPATH= cd -- "$2" && pwd -P)
    before_ids=$(tmux list-windows -a -F '#{window_id}' | tr '\n' ' ')
    VIM_TMUX_GHOSTTY_OPEN_TEST=1 "$HOME/bin/open" "$target"
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
        printf 'FAIL: wrapper created no tmux window for %s\n' "$target" >&2
        exit 1
    }
    command=$(tmux display-message -p -t "$new_id" '#{pane_current_command}')
    cwd=$(tmux display-message -p -t "$new_id" '#{pane_current_path}')
    tmux kill-window -t "$new_id"
    [ "$command" = vim ] || {
        printf 'FAIL: wrapper launched %s instead of vim\n' "$command" >&2
        exit 1
    }
    [ "$cwd" = "$expected_cwd" ] || {
        printf 'FAIL: Vim cwd is %s instead of %s\n' "$cwd" "$expected_cwd" >&2
        exit 1
    }
}

fixtures="$HOME/.local/share/vim-tmux/fixtures"
test_vim_target "$fixtures/should-open-in-vim.txt trailing prose" "$fixtures"
test_vim_target "$fixtures/should\ open\ in\ vim.txt" "$fixtures"

nix_file=/nix/store/w7wxgb11s11a6qghbjbzp62s4f0p3aj2-source/src/config/url.zig
[ -f "$nix_file" ] || {
    printf 'FAIL: Nix-store fixture is missing: %s\n' "$nix_file" >&2
    exit 1
}
test_vim_target "$nix_file" "${nix_file%/*}"

printf 'PASS: wrapper trims prose, accepts escaped spaces, and opens Nix-store source in Vim\n'
