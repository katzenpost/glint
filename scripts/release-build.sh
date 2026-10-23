#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
#
# Builds the release binary so that anyone with the same toolchains gets the same bytes, and writes
# it with its SHA256SUMS to the directory given (dist/ by default).
set -eu

out=${1:-dist}
cd "$(dirname "$0")/.."

# As the Makefile sets it: Paw's toolchain, for all three Rust libraries.
export RUSTUP_TOOLCHAIN=1.99.0
export PATH="$HOME/.cargo/bin:$HOME/.elan/bin:$PATH"

# Panic messages carry the source path of every crate, and those live under the builder's
# CARGO_HOME; name them the same on every machine.
cargo_home=${CARGO_HOME:-$HOME/.cargo}
export RUSTFLAGS="--remap-path-prefix=$cargo_home=/cargo --remap-path-prefix=$PWD=/echo-chat"
export PKG_CONFIG="$PWD/scripts/pkg-config-no-libdir"
export SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)"
export LC_ALL=C TZ=UTC

# A cargo build left from before carries the unmapped paths.
for p in paw rustic_audio_lean lean_unix_socket; do
	rm -rf ".lake/packages/$p/rust/target"
done
rm -f .lake/build/bin/echo-chat

# FROM_SOURCE=1 builds Mathlib here too, instead of trusting its downloaded files.
[ -n "${FROM_SOURCE:-}" ] || lake exe cache get
lake build echo-chat

version="$(git describe --tags --always)"
mkdir -p "$out"
cp .lake/build/bin/echo-chat "$out/echo-chat-$version-x86_64-linux"
cd "$out"
sha256sum "echo-chat-$version-x86_64-linux" > SHA256SUMS
cat SHA256SUMS
