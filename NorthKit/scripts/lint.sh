#!/bin/sh
# Check formatting, SwiftLint, and unused code. Does not rewrite files.
set -eu
cd "$(dirname "$0")/.."
# Pass --config because `swiftformat .` starts looking in the parent directory,
# and khepri/.swiftformat excludes this package.
swiftformat . --lint --config .swiftformat
swiftlint
periphery scan
