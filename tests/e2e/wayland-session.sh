#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# echo-chat showing a saved state, driven with Paw's virtual pointer and wtype's keyboard. Run by
# wayland.sh as sway's startup command; writes its result to $WORK/result and stops sway.
set -u
cd "$(dirname "$0")/../.."
. tests/e2e/lib.sh

finish() {
  kill "$PID_alice" 2>/dev/null
  echo "$FAILED" > "$WORK/result"
  swaymsg exit > /dev/null 2>&1
  exit 0
}

mkfifo "$WORK/pointer"
.lake/packages/paw/rust/target/release/examples/vpointer 1280 800 < "$WORK/pointer" > "$WORK/pointer.out" 2>&1 &
exec 3> "$WORK/pointer"
wait_for "$WORK/pointer.out" '^ready' || { fail "a virtual pointer"; finish; }
.lake/build/bin/echo-chat-test --fixture "$WORK/state"
start_echo_chat alice --offline --state "$WORK/state"
wait_for "$WORK/alice.layout" '^group:second ' || { fail "echo-chat reported its layout"; finish; }
sleep 1
ORIGIN=$(swaymsg -t get_tree | jq -r '.. | objects | select(.name? == "echo-chat") |
  "\(.rect.x + .window_rect.x) \(.rect.y + .window_rect.y)"' | head -n 1)
set -- $ORIGIN
OX=$1
OY=$2

click() {
  set -- $(center alice "$1")
  echo "move $((OX + $1)) $((OY + $2))" >&3
  echo "click" >&3
  sleep 0.7
}

expect alice 'selected=g ' "the saved state's first group is selected"
expect_idle alice "an idle echo-chat does not wake"
click group:second
expect alice 'selected=second ' "a click selects another group"
click draft
wtype -s 200 -d 30 "hi"
expect alice 'draft=hi ' "typing reaches the message box"
wtype -s 200 -M ctrl -k Next -m ctrl
expect alice 'selected=g ' "Ctrl+PageDown selects the next group"
wtype -s 200 -M ctrl q -m ctrl
sleep 1
if kill -0 "$PID_alice" 2>/dev/null; then fail "Ctrl+Q quits"; else ok "Ctrl+Q quits"; fi
finish
