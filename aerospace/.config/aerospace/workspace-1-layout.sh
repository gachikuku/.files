#!/bin/sh

set -eu

state_file="/tmp/aerospace-workspace-1-tiling-$(id -u)"

current_layout() {
	if [ -e "$state_file" ]; then
		printf '%s\n' tiling
	else
		printf '%s\n' floating
	fi
}

apply_to_workspace() {
	layout="$1"
	aerospace list-windows --workspace 1 --format '%{window-id}' |
		while IFS= read -r window_id; do
			if [ -n "$window_id" ]; then
				aerospace layout --window-id "$window_id" "$layout"
			fi
		done
}

case "${1:-toggle}" in
	apply)
		aerospace layout "$(current_layout)"
		;;
	apply-if-workspace-one)
		if [ -n "${AEROSPACE_WINDOW_ID:-}" ] &&
			aerospace list-windows --workspace 1 --format '%{window-id}' |
			/usr/bin/grep -Fxq "$AEROSPACE_WINDOW_ID"
		then
			aerospace layout "$(current_layout)"
		fi
		;;
	toggle)
		if [ -e "$state_file" ]; then
			rm -f -- "$state_file"
			layout=floating
		else
			: > "$state_file"
			layout=tiling
		fi
		apply_to_workspace "$layout"
		;;
	*)
		printf 'Usage: %s [apply|apply-if-workspace-one|toggle]\n' "$0" >&2
		exit 2
		;;
esac
