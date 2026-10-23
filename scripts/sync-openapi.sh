#!/usr/bin/env bash
# Copy the API contract from the web app into NorthKit.
#
# The web app owns docs/api/openapi.yaml and the golden response files its
# tests pin. The generated Swift client is built from the spec, and NorthKit's
# contract tests decode every golden file with the generated types, so both
# sides are held to the same bytes.
#
#   scripts/sync-openapi.sh           copy
#   scripts/sync-openapi.sh --check   fail if the copies are stale (CI)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB="${NORTH_WEB_APP:-$ROOT/../../north-client}"
SPEC_DEST="$ROOT/NorthKit/Sources/NorthAPI/openapi.yaml"
GOLDEN_DEST="$ROOT/NorthKit/Tests/NorthAPITests/Contract"
# docs/medals/medals.json is the one source of every coin medal's colours,
# geometry and glyph paths; NorthKit draws from this copy.
MEDALS_DEST="$ROOT/NorthKit/Sources/NorthKit/Resources/medals.json"

# Golden files that describe /api/v1 responses. mcpserver's are not API.
GOLDEN_SOURCES=(activity auth caffeine lifts stats calculator capture care checkins coach dashboard day decisions fasting milestones screentime soreness supplements documents exercises fitness goals health insights meals media memories mind news nudges onboarding reports settings workouts social achievements crews xp weekly inbox lighterday recaps outreach progresschecks dailyposts profiles awards)

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp "$WEB/docs/api/openapi.yaml" "$stage/openapi.yaml"
cp "$WEB/docs/medals/medals.json" "$stage/medals.json"
mkdir -p "$stage/golden"
for pkg in "${GOLDEN_SOURCES[@]}"; do
  # internal/profiles/testdata/profile.golden.json has the same name as
  # settings' (a different schema), so profiles' files get a prefix.
  prefix=""
  [[ "$pkg" == "profiles" ]] && prefix="profiles-"
  for f in "$WEB/internal/$pkg/testdata/"*.golden.json; do
    cp "$f" "$stage/golden/$prefix$(basename "$f")"
  done
done

if [[ "${1:-}" == "--check" ]]; then
  diff -q "$stage/openapi.yaml" "$SPEC_DEST" >/dev/null || { echo "openapi.yaml is stale; run scripts/sync-openapi.sh"; exit 1; }
  diff -q "$stage/medals.json" "$MEDALS_DEST" >/dev/null || { echo "medals.json is stale; run scripts/sync-openapi.sh"; exit 1; }
  diff -rq "$stage/golden" "$GOLDEN_DEST" >/dev/null || { echo "contract golden files are stale; run scripts/sync-openapi.sh"; exit 1; }
  echo "API contract up to date"
  exit 0
fi

cp "$stage/openapi.yaml" "$SPEC_DEST"
cp "$stage/medals.json" "$MEDALS_DEST"
rm -f "$GOLDEN_DEST"/*.golden.json
cp "$stage/golden/"*.golden.json "$GOLDEN_DEST/"
echo "synced spec, medals.json and $(ls "$GOLDEN_DEST" | wc -l | tr -d ' ') golden files from $WEB"
