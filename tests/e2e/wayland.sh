#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# echo-chat showing a saved state under a headless sway.
set -eu
cd "$(dirname "$0")/../.."
WORK=$(mktemp -d)
export WORK
trap 'rm -rf "$WORK"' EXIT
mkdir -m 700 "$WORK/run"
cat > "$WORK/config" <<CONF
output HEADLESS-1 resolution 1280x800
xwayland disable
default_border none
default_floating_border none
for_window [title="echo-chat"] floating enable
exec sh $PWD/tests/e2e/wayland-session.sh > $WORK/session.log 2>&1
CONF
env -u DISPLAY -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$WORK/run" WLR_BACKENDS=headless \
  WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman timeout 60 sway -c "$WORK/config" > "$WORK/sway.log" 2>&1 || true
grep -E '^(ok|FAIL)' "$WORK/session.log" 2>/dev/null || true
if [ ! -f "$WORK/result" ]; then
  echo "FAIL the session did not finish"
  tail -n 20 "$WORK/sway.log"
  exit 1
fi
exit "$(cat "$WORK/result")"
