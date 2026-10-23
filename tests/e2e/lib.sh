# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# Helpers for driving echo-chat in a real window. Sourced with WORK set to a scratch directory.

ECHO_CHAT=$PWD/.lake/build/bin/echo-chat
FAILED=0

ok() { echo "ok   $1"; }
fail() { echo "FAIL $1"; FAILED=1; }

# Starts echo-chat as member $1 with the test hooks; the rest are echo-chat's arguments.
start_echo_chat() {
  who=$1; shift
  : > "$WORK/$who.log"
  env PAW_TEST_LOG="$WORK/$who.log" PAW_TEST_LAYOUT="$WORK/$who.layout" "$ECHO_CHAT" "$@" \
    > "$WORK/$who.out" 2>&1 &
  eval "PID_$who=\$!"
}

# Waits up to $3 seconds (default 10) for a file to hold a line matching a pattern.
wait_for() {
  i=0
  limit=$(( ${3:-10} * 10 ))
  while ! grep -q -- "$2" "$1" 2>/dev/null; do
    i=$((i + 1))
    if [ $i -gt $limit ]; then return 1; fi
    sleep 0.1
  done
}

# The middle of member $1's widget keyed $2, in logical pixels from the window's top left.
center() {
  awk -v k="$2" '$1 == k { printf "%d %d\n", ($2 + $4) / 2, ($3 + $5) / 2 }' "$WORK/$1.layout"
}

# Checks that member $1's model log comes, within $4 seconds (default 10), to match a pattern.
expect() {
  i=0
  limit=$(( ${4:-10} * 10 ))
  while ! tail -n 1 "$WORK/$1.log" | grep -q -- "$2"; do
    i=$((i + 1))
    if [ $i -gt $limit ]; then fail "$3 (last: $(tail -n 1 "$WORK/$1.log" | cut -c1-300))"; return 1; fi
    sleep 0.1
  done
  ok "$3"
}

# Checks that member $1, left alone, uses no CPU: its loop sleeps until there is an event.
expect_idle() {
  pid=$(eval echo "\$PID_$1")
  t0=$(awk '{ print $14 + $15 }' "/proc/$pid/stat")
  sleep 2
  t1=$(awk '{ print $14 + $15 }' "/proc/$pid/stat")
  if [ $((t1 - t0)) -le 2 ]; then ok "$2"; else fail "$2 ($((t1 - t0)) ticks in 2 s)"; fi
}
