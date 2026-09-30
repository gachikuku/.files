#!/bin/dash

# Print the local day of the month when the weekly Codex allowance resets.
# Cache the result because tmux redraws the status bar every second.

cache_dir=${XDG_CACHE_HOME:-"$HOME/.cache"}/tmux
cache_file=$cache_dir/codex-weekly-reset
lock_dir=$cache_file.lock
cache_ttl=3600
now=$(/bin/date '+%s') || exit 1

read_cache()
{
    [ -r "$cache_file" ] || return 1
    read -r fetched_at resets_at < "$cache_file" || return 1
    case $fetched_at:$resets_at in
        *[!0-9:]*|:*) return 1 ;;
    esac
    [ "$resets_at" -gt "$now" ] || return 1
    return 0
}

print_reset_day()
{
    /bin/date -r "$resets_at" '+%-d'
}

if read_cache && [ $((now - fetched_at)) -lt "$cache_ttl" ]; then
    print_reset_day
    exit
fi

/bin/mkdir -p "$cache_dir" || exit 1
if /bin/mkdir "$lock_dir" 2>/dev/null; then
    trap '/bin/rmdir "$lock_dir" 2>/dev/null' EXIT HUP INT TERM

    reset_timestamp=$(
        {
            printf '%s\n' \
                '{"method":"initialize","id":0,"params":{"clientInfo":{"name":"tmux_rate_limit_status","title":"tmux Rate Limit Status","version":"1.0.0"}}}' \
                '{"method":"initialized","params":{}}' \
                '{"method":"account/rateLimits/read","id":1}'
            /bin/sleep 2
        } |
            /run/current-system/sw/bin/codex app-server 2>/dev/null |
            /run/current-system/sw/bin/jq -r '
                select(.id == 1)
                | [
                    .result.rateLimitsByLimitId.codex.primary?,
                    .result.rateLimitsByLimitId.codex.secondary?,
                    .result.rateLimits.primary?,
                    .result.rateLimits.secondary?
                  ]
                | map(select(
                    . != null
                    and .windowDurationMins >= 10000
                    and .windowDurationMins <= 10200
                  ))
                | .[0].resetsAt // empty
            '
    )

    case $reset_timestamp in
        ''|*[!0-9]*) ;;
        *)
            if [ "$reset_timestamp" -gt "$now" ]; then
                temporary_file=$cache_file.$$
                if printf '%s %s\n' "$now" "$reset_timestamp" > "$temporary_file"; then
                    /bin/mv "$temporary_file" "$cache_file"
                else
                    /bin/rm -f "$temporary_file"
                fi
            fi
            ;;
    esac
fi

read_cache && print_reset_day
