#!/bin/bash
set -euo pipefail

OUT_DIR="../data/wayback_changelogs"
mkdir -p "$OUT_DIR/desktop" "$OUT_DIR/mobile"

DESKTOP_URL="https://cdn.discordapp.com/changelogs/config_0.json"
MOBILE_URL="https://cdn.discordapp.com/changelogs/config_1.json"

get_snapshots() {
    local url="$1"
    echo "Fetching snapshots for $url..."
    # Get all snapshots from Wayback CDX API
    curl -s "https://web.archive.org/cdx/search/cdx?url=${url}&output=json&fl=timestamp,statuscode&filter=statuscode:200" | \
        jq -r 'if .[0] == ["timestamp","statuscode"] then .[1:] else . end | .[][0]' 2>/dev/null | \
        grep -E '^[0-9]{14}$' || true
}

fetch_snapshot() {
    local url="$1"
    local timestamp="$2"
    local platform="$3"
    
    # Use the id_ prefix to get raw content without Wayback wrapper
    local wayback_url="https://web.archive.org/web/${timestamp}id_/${url}"
    local output_file="$OUT_DIR/$platform/${timestamp}.json"
    
    # Skip if already downloaded
    if [[ -f "$output_file" ]]; then
        echo "  Skipping $timestamp (already exists)"
        return 0
    fi
    
    echo "  Fetching $timestamp..."
    local content
    content=$(curl -s --max-time 30 "$wayback_url" 2>/dev/null || echo "")
    
    if [[ -n "$content" && "$content" != *"error"* && "$content" != *"Access Denied"* ]]; then
        echo "$content" > "$output_file"
        # Validate it's valid JSON
        if jq empty "$output_file" 2>/dev/null; then
            echo "  Saved: $output_file"
        else
            echo "  Invalid JSON, removing..."
            rm -f "$output_file"
        fi
    else
        echo "  Failed to fetch or empty response"
    fi
    
    # Be nice to Wayback Machine
    sleep 1
}

# Process desktop config
echo "=== Processing desktop config ==="
desktop_timestamps=$(get_snapshots "$DESKTOP_URL")
count=0
for ts in $desktop_timestamps; do
    count=$((count + 1))
    echo "Desktop snapshot $count: $ts"
    fetch_snapshot "$DESKTOP_URL" "$ts" "desktop"
done

# Process mobile config
echo "=== Processing mobile config ==="
mobile_timestamps=$(get_snapshots "$MOBILE_URL")
count=0
for ts in $mobile_timestamps; do
    count=$((count + 1))
    echo "Mobile snapshot $count: $ts"
    fetch_snapshot "$MOBILE_URL" "$ts" "mobile"
done

echo "Done! Files saved to $OUT_DIR"
ls -la "$OUT_DIR/desktop" "$OUT_DIR/mobile"
