#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# echo-chat showing a saved state, with no daemon, driven with xdotool. Run by offline.sh inside Xvfb.
set -u
cd "$(dirname "$0")/../.."
. tests/e2e/lib.sh

.lake/build/bin/echo-chat-test --fixture "$WORK/state"
start_echo_chat alice --offline --state "$WORK/state"
W=$(xdotool search --sync --name "^echo-chat$" | head -n 1)
xdotool windowfocus --sync "$W"
wait_for "$WORK/alice.layout" '^group:second ' || { fail "echo-chat reported its layout"; exit 1; }
sleep 1

click() {
  set -- $(center alice "$1")
  xdotool mousemove --window "$W" "$1" "$2" click 1
  sleep 0.7
}

expect alice 'selected=g ' "the saved state's first group is selected"
expect alice 'lines=\[—:~alice added ~bob, ~bob:hello alice\]' "its lines are shown"
expect_idle alice "an idle echo-chat does not wake"
set -- $(center alice talk)
xdotool mousemove --window "$W" "$1" "$2" mousedown 1
expect alice 'voice=recording ' "holding Hold to talk records"
sleep 1
xdotool mouseup 1
expect alice 'voice=draft:[1-9]' "letting go keeps a voice note to send" 20
wait_for "$WORK/alice.layout" '^draft-play ' || fail "the voice note can be played"
click draft-play
click draft-discard
expect alice 'voice=idle ' "Discard throws it away"
if ls "$WORK/state/audio/drafts/"*.opus >/dev/null 2>&1; then fail "and its file"; else ok "and its file"; fi
xdotool keydown ctrl+space
expect alice 'voice=recording ' "holding Ctrl+Space records"
sleep 1
xdotool keyup space keyup ctrl
expect alice 'voice=draft:[1-9]' "letting go keeps a voice note" 20
click draft-discard
click group:second
expect alice 'selected=second ' "a click selects another group"
xdotool key ctrl+q
sleep 1
if kill -0 "$PID_alice" 2>/dev/null; then fail "Ctrl+Q quits"; kill "$PID_alice"; else ok "Ctrl+Q quits"; fi
exit $FAILED
