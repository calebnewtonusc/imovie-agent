#!/bin/bash
# _System/imovie-agent/agent.sh
# iMovie Agent — detects AirDrop media, stages it, imports into iMovie.
#
# Usage:
#   ./agent.sh                       # Auto: add to this week's project (create if new week)
#   ./agent.sh --status              # Show state + detected media, no import
#   ./agent.sh --new                 # Force create new project even mid-week
#   ./agent.sh --project "Name"      # Import into a specific named project
#   ./agent.sh --import-only         # Import to existing open project, skip create step

set -uo pipefail   # -e intentionally omitted: osascript errors are handled manually

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/state.json"
STAGE_PY="$SCRIPT_DIR/stage-media.py"
APPLESCRIPT="$SCRIPT_DIR/imovie-gui.applescript"

# ── Colors ────────────────────────────────────────────────────────────────────
BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()     { echo -e "${BLUE}[iMovie]${NC} $1"; }
success() { echo -e "${GREEN}[iMovie]${NC} $1"; }
warn()    { echo -e "${YELLOW}[iMovie]${NC} $1"; }
error()   { echo -e "${RED}[iMovie]${NC} $1"; exit 1; }

# ── Accessibility permissions check ───────────────────────────────────────────
check_accessibility() {
    if ! osascript -e 'tell application "System Events" to return name of first process' &>/dev/null; then
        echo ""
        error "Accessibility permissions required for GUI automation.
  → Open: System Settings > Privacy & Security > Accessibility
  → Add Terminal (or iTerm / your terminal app) and enable it
  → Re-run this script"
    fi
}

# ── Parse args ────────────────────────────────────────────────────────────────
FORCE_PROJECT=""
FORCE_NEW=false
STATUS_ONLY=false
IMPORT_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --project)     FORCE_PROJECT="$2"; shift 2 ;;
        --new)         FORCE_NEW=true; shift ;;
        --status)      STATUS_ONLY=true; shift ;;
        --import-only) IMPORT_ONLY=true; shift ;;
        *)             shift ;;
    esac
done

# ── Status mode (no accessibility check needed) ───────────────────────────────
if [ "$STATUS_ONLY" = true ]; then
    log "Checking status..."
    python3 "$STAGE_PY" status
    exit 0
fi

check_accessibility

# ── Detect + stage new media ──────────────────────────────────────────────────
log "Scanning ~/Downloads for new AirDrop media..."
RESULT=$(python3 "$STAGE_PY" stage)

NEW_COUNT=$(echo "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['new_count'])")
WEEK_LABEL=$(echo "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['week_label'])")
STAGE_DIR=$(echo "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('stage_dir') or '')")

if [ "$NEW_COUNT" -eq 0 ]; then
    warn "No new media found in ~/Downloads."
    exit 0
fi

log "Found $NEW_COUNT new file(s) — staged to: $STAGE_DIR"
echo ""
echo "$RESULT" | python3 -c "
import json, sys
files = json.load(sys.stdin)['files']
for f in files:
    tag = ' [Live Photo → MOV]' if f.get('source') == 'live_photo' else ''
    print(f'  [{f[\"created_str\"]}]  {f[\"name\"]}{tag}')
"
echo ""

# ── Read current state ────────────────────────────────────────────────────────
CURRENT_PROJECT=$(python3 -c "
import json
try:
    with open('$STATE_FILE') as f: d = json.load(f)
    print(d.get('current_project') or '')
except: print('')
")

CURRENT_WEEK=$(python3 -c "
import json
try:
    with open('$STATE_FILE') as f: d = json.load(f)
    print(d.get('current_week_start') or '')
except: print('')
")

# ── Determine project mode ────────────────────────────────────────────────────
if [ -n "$FORCE_PROJECT" ]; then
    TARGET_PROJECT="$FORCE_PROJECT"
    APPLESCRIPT_ACTION="import"

elif [ "$IMPORT_ONLY" = true ]; then
    TARGET_PROJECT="${CURRENT_PROJECT:-$WEEK_LABEL}"
    APPLESCRIPT_ACTION="import"

elif [ "$FORCE_NEW" = true ] || [ -z "$CURRENT_PROJECT" ] || [ "$CURRENT_WEEK" != "$WEEK_LABEL" ]; then
    TARGET_PROJECT="$WEEK_LABEL"
    APPLESCRIPT_ACTION="create-and-import"
    log "Creating new weekly project: $TARGET_PROJECT"

else
    TARGET_PROJECT="$CURRENT_PROJECT"
    APPLESCRIPT_ACTION="import"
    log "Adding to existing project: $TARGET_PROJECT"
fi

# ── Run iMovie GUI automation ──────────────────────────────────────────────────
log "Launching iMovie automation..."
IMOVIE_OK=true

if [ "$APPLESCRIPT_ACTION" = "create-and-import" ]; then
    osascript "$APPLESCRIPT" "create-and-import" "$TARGET_PROJECT" "$STAGE_DIR" || IMOVIE_OK=false
elif [ "$APPLESCRIPT_ACTION" = "import" ]; then
    osascript "$APPLESCRIPT" "import" "$STAGE_DIR" || IMOVIE_OK=false
fi

if [ "$IMOVIE_OK" = false ]; then
    warn "iMovie automation hit an error."
    warn "Your files are staged and ready at: $STAGE_DIR"
    warn "Manual fallback: open iMovie > File > Import Media > navigate to that folder > Import All"
fi

# ── Update state (injection-safe: pass values via env, not string interpolation) ──
TARGET_PROJECT="$TARGET_PROJECT" \
WEEK_LABEL="$WEEK_LABEL" \
STATE_FILE="$STATE_FILE" \
python3 << 'PYEOF'
import json, os
from datetime import datetime
from pathlib import Path

target_project = os.environ["TARGET_PROJECT"]
week_label     = os.environ["WEEK_LABEL"]
state_file     = Path(os.environ["STATE_FILE"])

try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    state = {"processed_files": []}

state["current_project"]       = target_project
state["current_week_start"]    = week_label
state["last_import_timestamp"] = datetime.now().isoformat()

with open(state_file, "w") as f:
    json.dump(state, f, indent=2)

print(f"State saved. Project: {target_project}")
PYEOF

echo ""
success "Done! $NEW_COUNT file(s) imported into '$TARGET_PROJECT'"
echo ""
echo "  Staged folder: $STAGE_DIR"
echo "  Next: open '$TARGET_PROJECT' in iMovie and drag clips from the"
echo "        Events browser onto your timeline. Already in chronological order."
