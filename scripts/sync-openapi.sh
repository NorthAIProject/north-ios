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
WEB="${NORTH_WEB_APP:-$ROOT/../../north-web-app}"
SPEC_DEST="$ROOT/NorthKit/Sources/NorthAPI/openapi.yaml"
GOLDEN_DEST="$ROOT/NorthKit/Tests/NorthAPITests/Contract"

# Golden files that describe /api/v1 responses. mcpserver's are not API.
GOLDEN_SOURCES=(activity auth caffeine lifts stats calculator capture care checkins coach dashboard day decisions fasting milestones screentime soreness supplements documents exercises fitness goals health insights meals media memories mind news nudges onboarding reports settings workouts)

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp "$WEB/docs/api/openapi.yaml" "$stage/openapi.yaml"
mkdir -p "$stage/golden"
for pkg in "${GOLDEN_SOURCES[@]}"; do
  for f in "$WEB/internal/$pkg/testdata/"*.golden.json; do
    cp "$f" "$stage/golden/$(basename "$f")"
  done
done

if [[ "${1:-}" == "--check" ]]; then
  diff -q "$stage/openapi.yaml" "$SPEC_DEST" >/dev/null || { echo "openapi.yaml is stale; run scripts/sync-openapi.sh"; exit 1; }
  diff -rq "$stage/golden" "$GOLDEN_DEST" >/dev/null || { echo "contract golden files are stale; run scripts/sync-openapi.sh"; exit 1; }
  echo "API contract up to date"
  exit 0
fi

cp "$stage/openapi.yaml" "$SPEC_DEST"
rm -f "$GOLDEN_DEST"/*.golden.json
cp "$stage/golden/"*.golden.json "$GOLDEN_DEST/"
echo "synced spec and $(ls "$GOLDEN_DEST" | wc -l | tr -d ' ') golden files from $WEB"
