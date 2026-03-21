#!/usr/bin/env python3
"""
stage-media.py
Detects new AirDrop media in ~/Downloads, handles Live Photo pairs,
hard-links (or copies) files to ~/Movies/iMovie-Staged/<week>/ for iMovie import.

Usage:
  python3 stage-media.py status                # Print state + queued files, no staging
  python3 stage-media.py stage                 # Stage new files (14-day filter on first run)
  python3 stage-media.py stage --since-days 7  # Only files from last 7 days
  python3 stage-media.py stage --all           # All unprocessed files regardless of age
"""

import os
import sys
import json
import shutil
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple

DOWNLOADS   = Path.home() / "Downloads"
STATE_FILE  = Path(__file__).parent / "state.json"
STAGE_BASE  = Path.home() / "Movies" / "iMovie-Staged"

# Keep only the last N processed paths to prevent unbounded state.json growth
MAX_PROCESSED_HISTORY = 3000

# On first run (empty history), default to files from the last N days.
# Prevents importing every photo ever downloaded.
FIRST_RUN_DEFAULT_DAYS = 14

PHOTO_EXTS = {".jpg", ".jpeg", ".png", ".heic", ".gif", ".tiff", ".webp"}
VIDEO_EXTS = {".mov", ".mp4", ".m4v", ".avi", ".mkv"}
ALL_MEDIA_EXTS = PHOTO_EXTS | VIDEO_EXTS


def load_state() -> dict:
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {
            "current_project": None,
            "current_week_start": None,
            "last_processed_timestamp": "2020-01-01T00:00:00",
            "processed_files": [],
            "mode": "auto",
        }


def save_state(state: dict) -> None:
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


def get_week_label() -> str:
    today = datetime.now()
    monday = today - timedelta(days=today.weekday())
    return monday.strftime("Week of %b %d, %Y")


def get_creation_time(path: Path) -> float:
    stat = path.stat()
    return getattr(stat, "st_birthtime", stat.st_mtime)


def find_new_media(processed_set: set, since_ts: Optional[float] = None) -> Dict[str, dict]:
    """
    Scan ~/Downloads for unprocessed media files.
    since_ts: epoch float — skip files created before this time.
    Returns dict keyed by lowercase stem -> {ext: file_info}.
    """
    by_stem: Dict[str, dict] = {}
    for item in DOWNLOADS.iterdir():
        if not item.is_file():
            continue
        if str(item) in processed_set:
            continue
        ext = item.suffix.lower()
        if ext not in ALL_MEDIA_EXTS:
            continue
        ctime = get_creation_time(item)
        if since_ts is not None and ctime < since_ts:
            continue
        stem = item.stem.lower()
        if stem not in by_stem:
            by_stem[stem] = {}
        by_stem[stem][ext] = {
            "path": str(item),
            "name": item.name,
            "stem": stem,
            "ext": ext,
            "created": ctime,
            "created_str": datetime.fromtimestamp(ctime).strftime("%Y-%m-%d %H:%M:%S"),
        }
    return by_stem


def resolve_live_photos(by_stem: Dict[str, dict]) -> List[dict]:
    """
    Live Photos from iPhone: .HEIC + .MOV pair, same stem.
    For video projects: keep the .mov (motion clip), drop the .heic still.
    Sorted oldest-first for chronological iMovie timeline.
    """
    result = []
    for stem, exts in by_stem.items():
        is_live_photo = ".heic" in exts and ".mov" in exts
        if is_live_photo:
            result.append({**exts[".mov"], "source": "live_photo"})
        else:
            for ext, info in exts.items():
                result.append({**info, "source": "standard"})
    result.sort(key=lambda x: x["created"])
    return result


def link_or_copy(src: Path, dst: Path) -> None:
    """Hard link first (instant, zero extra disk space). Copy fallback."""
    try:
        os.link(src, dst)
    except OSError:
        shutil.copy2(src, dst)


def stage_files(files: List[dict], week_label: str) -> Tuple[str, List[dict]]:
    safe_label = week_label.replace(" ", "_").replace(",", "")
    stage_dir  = STAGE_BASE / safe_label
    stage_dir.mkdir(parents=True, exist_ok=True)

    staged = []
    for f in files:
        src = Path(f["path"])
        dst = stage_dir / src.name
        counter = 1
        while dst.exists():
            dst = stage_dir / f"{src.stem}_{counter}{src.suffix}"
            counter += 1
        link_or_copy(src, dst)
        staged.append({**f, "staged_path": str(dst)})

    return str(stage_dir), staged


def parse_args() -> Tuple[str, Optional[int], bool]:
    """Returns (mode, since_days_override, force_all)."""
    mode = "stage"
    since_days = None
    force_all  = False

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        a = args[i]
        if a == "status":
            mode = "status"
        elif a == "--all":
            force_all = True
        elif a == "--since-days" and i + 1 < len(args):
            since_days = int(args[i + 1])
            i += 1
        i += 1
    return mode, since_days, force_all


def main() -> None:
    mode, since_days_override, force_all = parse_args()
    state         = load_state()
    processed_set = set(state.get("processed_files", []))
    week_label    = get_week_label()
    is_first_run  = len(processed_set) == 0

    # Determine the age cutoff
    if force_all:
        since_ts = None
    elif since_days_override is not None:
        since_ts = (datetime.now() - timedelta(days=since_days_override)).timestamp()
    elif is_first_run:
        # First run: automatically limit to last 14 days to avoid mass-importing old files
        since_ts = (datetime.now() - timedelta(days=FIRST_RUN_DEFAULT_DAYS)).timestamp()
    else:
        since_ts = None

    by_stem = find_new_media(processed_set, since_ts=since_ts)
    files   = resolve_live_photos(by_stem)

    if mode == "status":
        print(json.dumps({
            "current_project": state.get("current_project"),
            "current_week":    state.get("current_week_start"),
            "week_label":      week_label,
            "new_count":       len(files),
            "is_first_run":    is_first_run,
            "since_ts":        since_ts,
            "files":           files,
        }, indent=2))
        return

    if not files:
        print(json.dumps({
            "new_count":    0,
            "files":        [],
            "week_label":   week_label,
            "stage_dir":    None,
            "is_first_run": is_first_run,
        }))
        return

    stage_dir, staged = stage_files(files, week_label)

    # Update state — trim to prevent unbounded growth
    existing     = state.get("processed_files", [])
    new_paths    = [f["path"] for f in files]
    all_processed = existing + new_paths
    state["processed_files"]          = all_processed[-MAX_PROCESSED_HISTORY:]
    state["last_processed_timestamp"] = datetime.now().isoformat()
    save_state(state)

    print(json.dumps({
        "new_count":    len(staged),
        "files":        staged,
        "week_label":   week_label,
        "stage_dir":    stage_dir,
        "is_first_run": is_first_run,
    }))


if __name__ == "__main__":
    main()
