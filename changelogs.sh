#!/bin/bash
set -euo pipefail

MERGED_FILE="../data/changelogs_merged.json"
TEMP_DIR="./data/changelogs_merged"
mkdir -p "$TEMP_DIR"

FILE1="data/changelogs_desktop.json"
FILE2="data/changelogs_mobile.json"

# Clear temp directory
rm -f "$TEMP_DIR"/*.json

# Process each commit
git log --format="%H" -- "$FILE1" | while read -r sha; do
  echo "processing $sha"

  desktop=$(git show "$sha:$FILE1" 2>/dev/null || echo "[]")
  mobile=$(git show "$sha:$FILE2" 2>/dev/null || echo "[]")

  printf "%s\n%s\n" "$desktop" "$mobile" | jq -s --arg sha "$sha" '
    .[0] as $desktop | .[1] as $mobile |
    ($desktop // [] | map(. + {platform: "desktop"})) +
    ($mobile // [] | map(. + {platform: "mobile"})) |
    map(. + {commithash: $sha})
  ' > "$TEMP_DIR/$sha.json" 2>/dev/null || {
    echo "failed $sha"
    continue
  }

done

# Merge all files into one
if ls "$TEMP_DIR"/*.json 1>/dev/null 2>&1; then
  jq -s 'add' "$TEMP_DIR"/*.json > "$MERGED_FILE"
  echo "Merged file generated at $MERGED_FILE"
else
  echo "No temp files found, skipping merge"
fi