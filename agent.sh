#!/bin/bash
# _System/imovie-agent/agent.sh
# iMovie Agent — detects AirDrop media, stages it, imports into iMovie.
#
# Usage:
#   ./agent.sh                          # Auto: add to this week's project (create if new week)
#   ./agent.sh --status                 # Show state + detected media, no import
#   ./agent.sh --new                    # Force create new project even mid-week
#   ./agent.sh --project "Name"         # Import into a specific named project
#   ./agent.sh --import-only            # Import to existing open project, skip create
#   ./agent.sh --since-days 7           # Only consider files from last 7 days
#   ./agent.sh --all                    # Import ALL unprocessed files (no age limit)

set -uo pipefail   # -e intentionally omitted: osascript failures handled manually

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
        error "Accessibility permissions required.
  → System Settings > Privacy & Security > Accessibility
  → Add Terminal (or your terminal app) and enable it
  → Re-run this script"
    fi
}

# ── Parse args ────────────────────────────────────────────────────────────────
FORCE_PROJECT=""
FORCE_NEW=false
STATUS_ONLY=false
IMPORT_ONLY=false
SINCE_DAYS_ARG=""
FORCE_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --project)     FORCE_PROJECT="$2"; shift 2 ;;
        --new)         FORCE_NEW=true; shift ;;
        --status)      STATUS_ONLY=true; shift ;;
        --import-only) IMPORT_ONLY=true; shift ;;
        --since-days)  SINCE_DAYS_ARG="$2"; shift 2 ;;
        --all)         FORCE_ALL=true; shift ;;
        *)             shift ;;
    esac
done

# Build extra args to pass through to stage-media.py
STAGE_EXTRA_ARGS=()
if [ -n "$SINCE_DAYS_ARG" ]; then
    STAGE_EXTRA_ARGS+=(--since-days "$SINCE_DAYS_ARG")
elif [ "$FORCE_ALL" = true ]; then
    STAGE_EXTRA_ARGS+=(--all)
fi

# ── Status mode ───────────────────────────────────────────────────────────────
if [ "$STATUS_ONLY" = true ]; then
    log "Checking status..."
    STATUS_JSON=$(python3 "$STAGE_PY" status ${STAGE_EXTRA_ARGS[@]+"${STAGE_EXTRA_ARGS[@]}"})
    IS_FIRST=$(echo "$STATUS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if d.get('is_first_run') else 'no')")
    NEW_COUNT=$(echo "$STATUS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['new_count'])")
    WEEK=$(echo "$STATUS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['week_label'])")
    PROJECT=$(echo "$STATUS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('current_project') or '(none)')")
    echo ""
    echo "  Week:     $WEEK"
    echo "  Project:  $PROJECT"
    echo "  Queued:   $NEW_COUNT file(s)"
    [ "$IS_FIRST" = "yes" ] && echo "  Note:     First run — showing last 14 days only (use --all to see everything)"
    if [ "$NEW_COUNT" -gt 0 ]; then
        echo ""
        echo "$STATUS_JSON" | python3 -c "
import json, sys
files = json.load(sys.stdin)['files']
for f in files[:20]:
    tag = ' [Live Photo]' if f.get('source') == 'live_photo' else ''
    print(f'  [{f[\"created_str\"]}]  {f[\"name\"]}{tag}')
if len(files) > 20:
    print(f'  ... and {len(files) - 20} more')
"
    fi
    echo ""
    exit 0
fi

check_accessibility

# ── Detect + stage new media ──────────────────────────────────────────────────
log "Scanning ~/Downloads for new AirDrop media..."
RESULT=$(python3 "$STAGE_PY" stage ${STAGE_EXTRA_ARGS[@]+"${STAGE_EXTRA_ARGS[@]}"})

NEW_COUNT=$(echo "$RESULT"   | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['new_count'])")
WEEK_LABEL=$(echo "$RESULT"  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['week_label'])")
STAGE_DIR=$(echo "$RESULT"   | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('stage_dir') or '')")
IS_FIRST=$(echo "$RESULT"    | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if d.get('is_first_run') else 'no')")

if [ "$NEW_COUNT" -eq 0 ]; then
    warn "No new media found in ~/Downloads."
    [ "$IS_FIRST" = "yes" ] && warn "First run: only checked last 14 days. Use --all to import everything."
    exit 0
fi

[ "$IS_FIRST" = "yes" ] && log "First run — only importing files from last 14 days (use --all for everything)"
log "Found $NEW_COUNT new file(s) — staged to: $STAGE_DIR"
echo ""
echo "$RESULT" | python3 -c "
import json, sys
files = json.load(sys.stdin)['files']
for f in files[:20]:
    tag = ' [Live Photo → MOV]' if f.get('source') == 'live_photo' else ''
    print(f'  [{f[\"created_str\"]}]  {f[\"name\"]}{tag}')
if len(files) > 20:
    print(f'  ... and {len(files) - 20} more')
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

# ── Determine target project ──────────────────────────────────────────────────
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
log "Launching iMovie..."
IMOVIE_OK=true

if [ "$APPLESCRIPT_ACTION" = "create-and-import" ]; then
    osascript "$APPLESCRIPT" "create-and-import" "$TARGET_PROJECT" "$STAGE_DIR" || IMOVIE_OK=false
elif [ "$APPLESCRIPT_ACTION" = "import" ]; then
    osascript "$APPLESCRIPT" "import" "$STAGE_DIR" || IMOVIE_OK=false
fi

if [ "$IMOVIE_OK" = false ]; then
    warn "iMovie automation hit an error."
    warn "Files are staged and ready — manual fallback:"
    warn "  iMovie > File > Import Media > navigate to: $STAGE_DIR > Import All"
fi

# ── Update state (injection-safe: values via env, not string interpolation) ───
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
PYEOF

echo ""
success "Done! $NEW_COUNT file(s) imported into '$TARGET_PROJECT'"
echo ""
echo "  Staged:  $STAGE_DIR"
echo "  Next:    open '$TARGET_PROJECT' in iMovie, drag clips from the"
echo "           Events browser to your timeline. Already chronological."
