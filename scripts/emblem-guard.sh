#!/bin/sh
# Fails when this repository's copies of the emblem motion data drift from
# north-web-app's design/ (the canonical files; ADR 0005 there).
#
#   scripts/emblem-guard.sh                      # compare with north-web-app main on GitHub
#   scripts/emblem-guard.sh ../north-web-app     # compare with a local checkout
#
# north-web-app is public, so CI needs no token. Change the web side first,
# merge it, then copy the files here.
set -eu
cd "$(dirname "$0")/.."
source="${1:-}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for name in emblem-motion.json emblem-motion.fixtures.json; do
	if [ -n "$source" ]; then
		cp "$source/design/$name" "$tmp/$name"
	else
		curl -fsSL "https://raw.githubusercontent.com/NorthAIProject/north-web-app/main/design/$name" -o "$tmp/$name"
	fi
done
fail=0
check() {
	if ! cmp -s "$tmp/$1" "$2"; then
		echo "::error::$2 differs from north-web-app design/$1. Copy it from there." >&2
		fail=1
	fi
}
check emblem-motion.json khepri/Resources/emblem-motion.json
check emblem-motion.fixtures.json khepriTests/emblem-motion.fixtures.json
exit $fail
