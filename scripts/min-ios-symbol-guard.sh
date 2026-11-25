#!/usr/bin/env bash
# Fails when an app binary needs a Swift runtime symbol that the oldest iOS it
# claims to support does not have.
#
# Usage: scripts/min-ios-symbol-guard.sh path/to/Khepri.app
#
# Checks the executable and every other Mach-O in the bundle: extensions,
# embedded frameworks, and the khepri.debug.dylib that Debug builds put the
# app's code in.
#
# Why: 1.0.1 (14) and 1.0.2 (22) were built with Xcode 27 while the app still
# supports iOS 26.2. swift-collections, compiled by the Xcode 27 toolchain,
# referenced `_swift_initBorrow`, which only iOS 27's libswiftCore exports.
# dyld refused to load the app on every iOS 26 iPhone ("Symbol not found",
# terminated at launch), before any of our code or crash reporting ran. The
# tests could not catch it: they ran on Xcode 26 while uploads used Xcode 27.
#
# How: every strong (non-weak) undefined symbol the binary imports from a
# system Swift library must be exported by that library in the oldest
# installed iOS simulator runtime that is at least MinimumOSVersion and has the
# same major version. Without such a runtime, it falls back to the list of
# symbols known to have broken a release, and says so.
set -euo pipefail

app="${1:?usage: $0 path/to/App.app}"
[ -d "$app" ] || { echo "::error::$app is not an app bundle"; exit 2; }
min_os="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app/Info.plist")"

binaries=()
while IFS= read -r -d '' f; do
  file -b "$f" | grep -q 'Mach-O' && binaries+=("$f")
done < <(find "$app" -type f \( -perm -u+x -o -name '*.dylib' \) -print0)
[ "${#binaries[@]}" -gt 0 ] || { echo "::error::no Mach-O files in $app"; exit 2; }
echo "Checking ${#binaries[@]} Mach-O file(s) in $(basename "$app") (MinimumOSVersion $min_os)"

# "(undefined) external _sym (from libswiftCore)"; weak imports say "weak
# external" and are allowed to be missing.
imports="$(for b in "${binaries[@]}"; do xcrun nm -m "$b" 2>/dev/null; done \
  | sed -nE 's/^ *\(undefined\) external ([^ ]+) \(from (libswift[^)]*)\)$/\2 \1/p' | sort -u)"

known_bad=(_swift_initBorrow)

runtime_root="$(xcrun simctl list runtimes -j 2>/dev/null | MIN_OS="$min_os" python3 -I -c '
import json, os, sys
want = tuple(int(x) for x in os.environ["MIN_OS"].split("."))
best = None
for r in json.load(sys.stdin).get("runtimes", []):
    if r.get("platform") != "iOS" or not r.get("isAvailable", True):
        continue
    v = tuple(int(x) for x in r["version"].split("."))
    if v < want or v[0] != want[0]:
        continue
    root = os.path.join(r["bundlePath"], "Contents/Resources/RuntimeRoot")
    if os.path.isfile(os.path.join(root, "usr/lib/swift/libswiftCore.dylib")) and (best is None or v < best[0]):
        best = (v, root)
print(best[1] if best else "")
' || true)"

failures=0
if [ -n "$runtime_root" ]; then
  echo "Against runtime: $runtime_root"
  while read -r lib; do
    [ -n "$lib" ] || continue
    dylib="$runtime_root/usr/lib/swift/$lib.dylib"
    # Libraries the runtime does not ship (embedded in the app, or newer than
    # the OS) cannot be checked this way.
    [ -f "$dylib" ] || { echo "  skip $lib: not in this runtime"; continue; }
    # Overlays such as libswiftCoreGraphics are stubs that re-export their
    # framework; their own table is empty, so they cannot be checked here.
    if xcrun otool -l "$dylib" | grep -q LC_REEXPORT_DYLIB; then
      echo "  skip $lib: re-exports another library"; continue
    fi
    exports="$(xcrun nm -gU "$dylib" 2>/dev/null | awk '{print $NF}' | sort -u)"
    [ -n "$exports" ] || { echo "  skip $lib: exports nothing"; continue; }
    missing="$(awk -v l="$lib" '$1==l {print $2}' <<<"$imports" | comm -23 - <(printf '%s\n' "$exports"))"
    if [ -n "$missing" ]; then
      while read -r sym; do
        echo "::error::$sym (from $lib) is not in iOS $min_os's runtime: the app would not launch there"
      done <<<"$missing"
      failures=$((failures + $(wc -l <<<"$missing")))
    fi
  done < <(awk '{print $1}' <<<"$imports" | sort -u)
else
  echo "::warning::No iOS $min_os+ simulator runtime with the same major version is installed; checking only symbols known to have broken a release."
  for sym in "${known_bad[@]}"; do
    if awk '{print $2}' <<<"$imports" | grep -qx "$sym"; then
      echo "::error::$sym is not available before iOS 27: the app would not launch on iOS $min_os"
      failures=$((failures + 1))
    fi
  done
fi

if [ "$failures" -gt 0 ]; then
  echo "Build with the Xcode the tests use, or raise the deployment target. See CHANGELOG 1.0.3."
  exit 1
fi
echo "OK: every Swift runtime symbol the app needs exists on iOS $min_os"
