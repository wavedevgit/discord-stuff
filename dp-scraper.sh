#!/bin/bash

# Credits: https://github.com/Discord-Datamining/Discord-Datamining/

set -e

git clone --no-checkout --mirror https://github.com/Discord-Datamining/Discord-Datamining dp
cd dp

mkdir -p ../data/dp

git log --pretty=format:"%H|%s" | while IFS='|' read -r commit_hash name; do

  export name="$name"

  parsed=$(node -e '
    const m = process.env.name.match(/Build\s*(\d+)\s*\(([a-f0-9]{40})\)/i);
    if (!m) process.exit(0);
    console.log(JSON.stringify({ buildNumber: m[1], versionHash: m[2] }));
  ')

  # skip if not a build commit
  if [ -z "$parsed" ]; then
    continue
  fi

  versionHash=$(node -e "console.log($parsed.versionHash)")
  buildNumber=$(node -e "console.log($parsed.buildNumber)")

  out_dir="../data/dp/$commit_hash"
  mkdir -p "$out_dir"

  echo "$parsed" > "$out_dir/info.json"

  url="http://canary.discord.com/overlay?build_id=$versionHash"

  response_file=$(mktemp)

  http_code=$(curl -s -w "%{http_code}" -o "$response_file" \
    -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
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
  
  sleep $((RANDOM % 3))

done

cd ..
rm -rf dp