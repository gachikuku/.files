#!/bin/sh

set -eu

user_id="$(id -u)"
state_dir="/tmp/aerospace-workspace-layout-$user_id"
/bin/mkdir -p "$state_dir"

focused_workspace() {
	aerospace list-workspaces --focused --format '%{workspace}'
}

target_workspace() {
	if [ -n "${AEROSPACE_WINDOW_ID:-}" ]; then
		aerospace list-windows --all --format '%{window-id}|%{workspace}' |
			/usr/bin/awk -F '|' -v id="$AEROSPACE_WINDOW_ID" '$1 == id { print $2; exit }'
	elif [ -n "${AEROSPACE_WORKSPACE:-}" ]; then
		printf '%s\n' "$AEROSPACE_WORKSPACE"
	else
		focused_workspace
	fi
}

state_file_for() {
	workspace_key="$(printf '%s' "$1" | /usr/bin/cksum | /usr/bin/awk '{ print $1 }')"
	printf '%s/%s\n' "$state_dir" "$workspace_key"
}

selected_layout() {
	workspace="$1"
	state_file="$(state_file_for "$workspace")"
	old_workspace_one_state="/tmp/aerospace-workspace-1-tiling-$user_id"

	# Preserve workspace 1's state from the original single-workspace toggle.
	if [ "$workspace" = 1 ] && [ -e "$old_workspace_one_state" ] && [ ! -e "$state_file" ]; then
		printf '%s\n' tiling > "$state_file"
		rm -f -- "$old_workspace_one_state"
	fi

	if [ -e "$state_file" ]; then
		layout="$(/bin/cat "$state_file")"
		case "$layout" in
			floating|tiling) printf '%s\n' "$layout" ;;
			*) return 1 ;;
		esac
	elif [ "$workspace" = 1 ]; then
		# Workspace 1 remains floating by default, as before.
		printf '%s\n' floating
	else
		# Untoggled workspaces keep AeroSpace's normal default layout.
		return 1
	fi
}

apply_to_workspace() {
	workspace="$1"
	layout="$2"
	aerospace list-windows --workspace "$workspace" --format '%{window-id}' |
		while IFS= read -r window_id; do
			if [ -n "$window_id" ]; then
				aerospace layout --window-id "$window_id" "$layout"
			fi
		done
}

toggle_workspace() {
	workspace="$1"
	state_file="$(state_file_for "$workspace")"

	if layout="$(selected_layout "$workspace")"; then
		if [ "$layout" = floating ]; then
			layout=tiling
		else
			layout=floating
		fi
	else
		window_layouts="$(aerospace list-windows --workspace "$workspace" --format '%{window-layout}')"
		if [ -n "$window_layouts" ] && ! printf '%s\n' "$window_layouts" | /usr/bin/grep -Fvxq floating; then
			layout=tiling
		else
			layout=floating
		fi
	fi

	printf '%s\n' "$layout" > "$state_file"
	apply_to_workspace "$workspace" "$layout"
}

case "${1:-toggle}" in
	apply)
		workspace="$(target_workspace)"
		if [ -n "$workspace" ] && layout="$(selected_layout "$workspace")"; then
			aerospace layout "$layout"
		fi
		;;
	toggle)
		toggle_workspace "$(focused_workspace)"
		;;
	*)
		printf 'Usage: %s [apply|toggle]\n' "$0" >&2
		exit 2
		;;
esac
