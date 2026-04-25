#!/bin/bash
set -e

# Credits: https://github.com/Discord-Datamining/Discord-Datamining/

REPO="Discord-Datamining/Discord-Datamining"
API="https://api.github.com/repos/$REPO/commits"

mkdir -p ../data/dp

# GitHub Actions token support (or manual export)
AUTH_HEADER=""
if [ -n "$GITHUB_TOKEN" ]; then
  AUTH_HEADER="Authorization: Bearer $GITHUB_TOKEN"
fi

per_page=100
page=1

while true; do
  echo "Fetching page $page..."

  response=$(curl -s \
    -H "Accept: application/vnd.github+json" \
    -H "$AUTH_HEADER" \
    "$API?per_page=$per_page&page=$page")

  count=$(echo "$response" | jq 'length')

  if [ "$count" -eq 0 ]; then
    break
  fi

  echo "$response" | jq -c '.[]' | while read -r commit; do
    commit_hash=$(echo "$commit" | jq -r '.sha')
    message=$(echo "$commit" | jq -r '.commit.message')

    export name="$message"

    parsed=$(node -e '
      const m = process.env.name.match(/Build\s*(\d+)\s*\(([a-f0-9]{40})\)/i);
      if (!m) process.exit(0);
      console.log(JSON.stringify({
        buildNumber: m[1],
        versionHash: m[2]
      }));
    ')

    if [ -z "$parsed" ]; then
      continue
    fi

    versionHash=$(node -e "console.log($parsed.versionHash)")
    buildNumber=$(node -e "console.log($parsed.buildNumber)")

    out_dir="../data/dp/$commit_hash"
    mkdir -p "$out_dir"

    echo "$parsed" > "$out_dir/info.json"

    url="https://canary.discord.com/overlay?build_id=$versionHash"

    response_file=$(mktemp)

    http_code=$(curl -s -w "%{http_code}" -o "$response_file" \
      -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
      "$url")

    if [ "$http_code" -eq 200 ]; then
      mv "$response_file" "$out_dir/index.html"

    elif [ "$http_code" -eq 404 ]; then
      echo "no_html_found_here" > "$out_dir/index.html"
      rm -f "$response_file"

    else
      body=$(cat "$response_file")
      echo "error failed to get html: $http_code, $body" > "$out_dir/index.html"
      rm -f "$response_file"
    fi

    sleep $((RANDOM % 2))
  done

  page=$((page + 1))
done
