#!/bin/bash
# willow-trigger.sh
# Watches Willow transcript folder for new transcripts containing
# AirDrop/iMovie intent keywords, then fires the iMovie agent automatically.
#
# Run once as a background process:
#   bash willow-trigger.sh &
#
# Or wire into launchd for persistence across reboots (see README).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT="$SCRIPT_DIR/agent.sh"
WILLOW_DIR="$HOME/Library/Application Support/com.seewillow.WillowMac/Transcripts"
LAST_PROCESSED_FILE="$SCRIPT_DIR/.willow-last-processed"

# Keywords that signal "import to iMovie" intent
KEYWORDS=(
    "airdrop" "air drop"
    "imovie" "i movie"
    "import clips" "import video" "import footage"
    "add clips" "add to imovie" "update imovie"
    "new footage" "new clips" "new video"
    "sync clips" "sync video"
)

# Keywords that signal "create a new project" intent
NEW_PROJECT_KEYWORDS=(
    "new project" "new week" "start fresh"
    "fresh project" "brand new project"
)

log() { echo "[Willow→iMovie $(date '+%H:%M:%S')] $1"; }

if [ ! -d "$WILLOW_DIR" ]; then
    log "Willow transcripts not found at: $WILLOW_DIR"
    log "Is Willow installed? (https://www.seewillow.com)"
    exit 1
fi

log "Watching for AirDrop/iMovie intents in Willow transcripts..."

# Load last-processed epoch timestamp
LAST_TS=0
if [ -f "$LAST_PROCESSED_FILE" ]; then
    LAST_TS=$(cat "$LAST_PROCESSED_FILE")
fi

# Read a Willow transcript file safely (path via stdin to avoid injection)
read_transcript_text() {
    local filepath="$1"
    if [[ "$filepath" == *.json ]]; then
        # Pass path via stdin — no shell injection risk
        echo "$filepath" | python3 - << 'PYEOF'
import json, sys
path = sys.stdin.read().strip()
try:
    with open(path) as f:
        d = json.load(f)
    # Try common Willow JSON keys
    text = d.get("transcript", "") or d.get("text", "") or d.get("content", "") or ""
    if not text and isinstance(d, dict):
        text = " ".join(str(v) for v in d.values() if isinstance(v, str))
    print(text.lower())
except Exception:
    pass
PYEOF
    else
        cat "$filepath" 2>/dev/null | tr '[:upper:]' '[:lower:]'
    fi
}

# Get file creation/modification time via stdin (injection-safe)
get_file_ts() {
    local filepath="$1"
    echo "$filepath" | python3 - << 'PYEOF'
import os, sys
path = sys.stdin.read().strip()
try:
    s = os.stat(path)
    print(int(getattr(s, "st_birthtime", s.st_mtime)))
except Exception:
    print(0)
PYEOF
}

check_new_transcripts() {
    local now
    now=$(date +%s)
    local triggered=false
    local force_new=false

    while IFS= read -r -d '' transcript_file; do
        local file_ts
        file_ts=$(get_file_ts "$transcript_file")

        if [ "$file_ts" -le "$LAST_TS" ]; then
            continue
        fi

        local text
        text=$(read_transcript_text "$transcript_file")

        if [ -z "$text" ]; then
            continue
        fi

        # Check for import-intent keywords
        local match=false
        for kw in "${KEYWORDS[@]}"; do
            if echo "$text" | grep -qi "$kw"; then
                match=true
                log "Triggered by '$kw' in: $(basename "$transcript_file")"
                break
            fi
        done

        if [ "$match" = true ]; then
            triggered=true
            for kw in "${NEW_PROJECT_KEYWORDS[@]}"; do
                if echo "$text" | grep -qi "$kw"; then
                    force_new=true
                    log "Detected 'new project' intent"
                    break
                fi
            done
        fi

    done < <(find "$WILLOW_DIR" -type f \( -name "*.txt" -o -name "*.json" -o -name "*.md" \) -print0 2>/dev/null)

    # Always advance the timestamp so we don't re-process old transcripts
    echo "$now" > "$LAST_PROCESSED_FILE"

    if [ "$triggered" = true ]; then
        log "Firing iMovie agent..."
        if [ "$force_new" = true ]; then
            bash "$AGENT" --new
        else
            bash "$AGENT"
        fi
    fi
}

# Poll every 15 seconds
while true; do
    check_new_transcripts
    sleep 15
done
