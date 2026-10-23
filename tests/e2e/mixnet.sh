#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
# SPDX-License-Identifier: AGPL-3.0-only
#
# Keeps each member's logs and state when a check fails, and says where.
set -eu
WORK=$(mktemp -d "${TMPDIR:-/tmp}/echo-chat-mixnet.XXXXXX")
export WORK
# ALSA's null device, as a speaker that needs no hardware.
printf 'pcm.!default { type null }\nctl.!default { type hw card 0 }\n' > "$WORK/asound.conf"
export ALSA_CONFIG_PATH="$WORK/asound.conf"
if env -u WAYLAND_DISPLAY xvfb-run -a -s "-screen 0 3200x2300x24" sh "$(dirname "$0")/mixnet-session.sh"; then
  rm -rf "$WORK"
else
  echo "logs kept in $WORK"
  exit 1
fi
