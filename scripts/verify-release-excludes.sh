#!/bin/sh
# Proves the App Store (Release) build contains none of the Debug/Beta-only
# experiments: no 3D emblem or mascot model, no motion data, no 3D view symbol
# (DESIGN.md, 3D Emblem and 3D Mascot; RELEASE_EXCLUDED in configure-build-variants.rb).
#
#   scripts/verify-release-excludes.sh [derived-data-dir]
#
# Builds Release for the simulator, unsigned, then inspects the .app.
set -eu
cd "$(dirname "$0")/.."
dd="${1:-build/ReleaseCheck}"
xcodebuild build \
	-project khepri.xcodeproj -scheme khepri -configuration Release \
	-destination 'generic/platform=iOS Simulator' \
	-derivedDataPath "$dd" -skipPackagePluginValidation \
	CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO -quiet
app="$dd/Build/Products/Release-iphonesimulator/khepri.app"
[ -d "$app" ] || { echo "::error::no Release app at $app" >&2; exit 1; }

fail=0
for file in Emblem.usdz emblem-motion.json Mascot.usdz mascot-motion.json; do
	if find "$app" -name "$file" | grep -q .; then
		echo "::error::Release app contains $file" >&2
		fail=1
	fi
done
# Symbols and strings in every executable and dylib (a Debug-style build puts
# the code in khepri.debug.dylib): a type that was compiled in leaves its
# mangled name or metadata string behind even when stripped.
for binary in "$app/khepri" "$app"/*.dylib; do
	[ -f "$binary" ] || continue
	for symbol in Emblem3DView EmblemStage EmblemMotion Mascot3DView MascotStage MascotMotion; do
		if strings -a "$binary" | grep -q "$symbol"; then
			echo "::error::$(basename "$binary") contains $symbol" >&2
			fail=1
		fi
	done
done
[ "$fail" = 0 ] && echo "Release app has no 3D emblem or mascot model, motion data or symbols ($app)"
exit $fail
