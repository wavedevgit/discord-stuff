#!/bin/bash
set -euo pipefail

REPO="Discord-Datamining/Discord-Datamining"
API="https://api.github.com/repos/$REPO/commits"

OUT_DIR="../data/dp"
mkdir -p "$OUT_DIR"

PER_PAGE=100

AUTH_ARGS=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  AUTH_ARGS=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

process_commit() {
  local sha="$1"
  local msg="$2"

  # extract build info directly in jq-compatible regex
  parsed=$(jq -Rn --arg msg "$msg" '
    $msg
    | capture("Build\\s*(?<build>[0-9]+)\\s*\\((?<hash>[a-f0-9]{40})\\)")?
  ')

  [[ -z "$parsed" || "$parsed" == "null" ]] && return

  build=$(echo "$parsed" | jq -r '.build')
  hash=$(echo "$parsed" | jq -r '.hash')

  out="$OUT_DIR/$sha"
  mkdir -p "$out"

  echo "$parsed" > "$out/info.json"

  url="https://canary.discord.com/overlay?build_id=$hash"
  tmp=$(mktemp)

  code=$(curl -sS -L \
    -o "$tmp" \
    -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) Chrome/120" \
    "$url") || true

  if [[ "$code" == "200" ]]; then
    mv "$tmp" "$out/index.html"
  elif [[ "$code" == "404" ]]; then
    echo "no_html_found_here" > "$out/index.html"
    rm -f "$tmp"
  else
    echo "error $code" > "$out/index.html"
    rm -f "$tmp"
  fi
}

export -f process_commit
export OUT_DIR

page=1

while true; do
  echo "Fetching page $page..."

  response=$(curl -sS --fail \
    -H "Accept: application/vnd.github+json" \
    "${AUTH_ARGS[@]}" \
    "$API?per_page=$PER_PAGE&page=$page")

  count=$(echo "$response" | jq 'length')
  [[ "$count" -eq 0 ]] && break

  # extract everything in ONE jq pass (this is where speed comes from)
  echo "$response" | jq -r '
    .[] |
    [
      .sha,
      (.commit.message | capture("Build\\s*(?<build>[0-9]+)\\s*\\((?<hash>[a-f0-9]{40})\\)")? // empty | @json)
    ] |
    @tsv
  ' | while IFS=$'\t' read -r sha msg; do
    [[ -z "$msg" ]] && continue

    # parallelize per commit (8 workers)
    process_commit "$sha" "$msg" &
    
    # limit concurrency (cheap worker pool)
    while [[ $(jobs -r | wc -l) -ge 8 ]]; do
      wait -n
    done
  done

  wait
  page=$((page + 1))
done