# SPDX-License-Identifier: AGPL-3.0-only

export PATH := $(HOME)/.cargo/bin:$(HOME)/.elan/bin:$(PATH)

# Paw's Rust crate pins this toolchain; the daemon socket's crate pins none. Both static libraries
# carry Rust's std, so they must be built by the same rustc or the link finds it twice.
export RUSTUP_TOOLCHAIN := 1.99.0

katzenpost_ref?=2405aa1119404b1e27cce0566729141102d769f0
katzenpost_dir?=.katzenpost

.PHONY: build release test run shots screenshot e2e e2e-offline e2e-wayland test-integration ci

build:
	lake exe cache get && lake build echo-chat

# The binary and its SHA256SUMS in dist/, the same bytes on every machine.
release:
	sh scripts/release-build.sh dist

# In one process, with no daemon or window.
test:
	lake exe cache get && lake build echo-chat-test && lake exe echo-chat-test

run:
	lake exe echo-chat

# Pictures of the window, drawn offscreen, in shots/.
shots:
	lake build echo-chat-test && lake exe echo-chat-test --shot shots

# The README's picture: Alice's window after a conversation over the simulated Pigeonhole.
screenshot:
	lake build echo-chat-test && lake exe echo-chat-test --readme docs/screenshot.png

e2e: e2e-offline e2e-wayland

# A saved state shown in a real window on Xvfb, driven with xdotool.
e2e-offline:
	lake build echo-chat echo-chat-test && sh tests/e2e/offline.sh

# The same under a headless sway, driven with Paw's virtual pointer and wtype.
e2e-wayland:
	lake build echo-chat echo-chat-test
	cd .lake/packages/paw/rust && cargo build --quiet --release --example vpointer
	sh tests/e2e/wayland.sh

# Two windows over the docker mixnet's client daemon, as test-integration.sh starts it.
test-integration:
	lake build echo-chat && DAEMON=127.0.0.1:33399 N=3 MINUTES=30 sh tests/e2e/mixnet.sh

ci: test e2e
