#!/bin/bash
set -euo pipefail

REPO="wavedevgit/discord-datamining_v2"
API="https://api.github.com/repos/$REPO/commits?path=data"

OUT_DIR="../data/changelogs_merged"
mkdir -p "$OUT_DIR"

PER_PAGE=100

AUTH_ARGS=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  AUTH_ARGS=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

process_commit() {
  local sha="$1"

  tmp=$(mktemp)

  # fetch file at commit
  curl -sS -L \
    -H "Accept: application/vnd.github+json" \
    "${AUTH_ARGS[@]}" \
    "https://raw.githubusercontent.com/$REPO/$sha/data/changelogs_desktop.json" > "$tmp.desktop" || true

  curl -sS -L \
    -H "Accept: application/vnd.github+json" \
    "${AUTH_ARGS[@]}" \
    "https://raw.githubusercontent.com/$REPO/$sha/data/changelogs_mobile.json" > "$tmp.mobile" || true

  # merge arrays + inject commit hash
  jq -s --arg sha "$sha" '
    map(select(type == "array"))   # keep only valid arrays
    | add                          # merge arrays
    | map(. + {commithash: $sha}) # inject commit hash
  ' "$tmp.desktop" "$tmp.mobile" > "$OUT_DIR/$sha.json"

  rm -f "$tmp.desktop" "$tmp.mobile"
}

export -f process_commit
export REPO OUT_DIR

page=1

while true; do
  echo "Fetching page $page..."

  response=$(curl -sS --fail \
    -H "Accept: application/vnd.github+json" \
    "${AUTH_ARGS[@]}" \
    "$API?per_page=$PER_PAGE&page=$page")

  count=$(echo "$response" | jq 'length')
  [[ "$count" -eq 0 ]] && break

  echo "$response" | jq -r '.[] | .sha' | while read -r sha; do
    process_commit "$sha" &

    # concurrency limit (8 workers)
    while [[ $(jobs -r | wc -l) -ge 8 ]]; do
      wait -n
    done
  done

  wait
  page=$((page + 1))
done