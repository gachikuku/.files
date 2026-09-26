#!/bin/sh

set -eu

lidcaffeinate=/Users/gachikuku/bin/lidcaffeinate
original=$(/usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/{print $2}')
controller_pid=

cleanup() {
  exit_code=$?
  trap - 0 1 2 15
  if [ -n "$controller_pid" ]; then
    /bin/kill -TERM "$controller_pid" 2>/dev/null || true
    wait "$controller_pid" 2>/dev/null || true
  fi
  /usr/bin/sudo -n -- /usr/bin/pmset -a disablesleep "$original" >/dev/null
  exit "$exit_code"
}

trap cleanup 0 1 2 15

if /usr/bin/pgrep -f "^/bin/sh $lidcaffeinate$" >/dev/null; then
  echo "FAIL: another lidcaffeinate controller is already running" >&2
  exit 2
fi

/usr/bin/sudo -n -- /usr/bin/pmset -a disablesleep 0
/bin/sh "$lidcaffeinate" >/dev/null 2>&1 &
controller_pid=$!

attempt=0
while [ "$attempt" -lt 20 ]; do
  current=$(/usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/{print $2}')
  [ "$current" = 1 ] && break
  attempt=$((attempt + 1))
  /bin/sleep 0.1
done

if [ "${current:-0}" != 1 ]; then
  echo "FAIL: controller did not enable lid-sleep protection" >&2
  exit 1
fi

# Reproduce the bug: another cleanup or power-setting update clears the global
# flag while the controller process remains alive.
/usr/bin/sudo -n -- /usr/bin/pmset -a disablesleep 0
/bin/sleep 3

current=$(/usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/{print $2}')
if [ "$current" != 1 ]; then
  echo "FAIL: live controller did not restore SleepDisabled (got $current)" >&2
  exit 1
fi

echo "PASS: live controller restored SleepDisabled=1"
