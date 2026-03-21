#!/usr/bin/env python3
"""
stage-media.py
Detects new AirDrop media in ~/Downloads, handles Live Photo pairs,
hard-links (or copies) files to ~/Movies/iMovie-Staged/<week>/ for iMovie import.

Usage:
  python3 stage-media.py status     # Print state + detected files, no staging
  python3 stage-media.py stage      # Stage new files and output JSON
"""

import os
import sys
import json
import shutil
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Tuple

DOWNLOADS = Path.home() / "Downloads"
STATE_FILE = Path(__file__).parent / "state.json"
STAGE_BASE = Path.home() / "Movies" / "iMovie-Staged"

# Keep only the last N processed paths to prevent unbounded state.json growth
MAX_PROCESSED_HISTORY = 3000

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
    # macOS birthtime (st_birthtime) > mtime fallback
    return getattr(stat, "st_birthtime", stat.st_mtime)


def find_new_media(processed_set: set) -> Dict[str, dict]:
    """
    Scan ~/Downloads for unprocessed media files.
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
        stem = item.stem.lower()
        ctime = get_creation_time(item)
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
    Live Photos from iPhone arrive as a .HEIC + .MOV pair with the same stem.
    For video projects: keep the .mov (the motion clip), discard the .heic still.
    Standalone HEICs and standalone MOVs are kept as-is.
    Returns flat list sorted oldest-first (chronological iMovie timeline).
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
    """
    Hard link first (instant, zero extra disk space on same filesystem).
    Falls back to full copy if hard link fails (different volume, permissions, etc.).
    """
    try:
        os.link(src, dst)
    except OSError:
        shutil.copy2(src, dst)


def stage_files(files: List[dict], week_label: str) -> Tuple[str, List[dict]]:
    """
    Hard-link (or copy) files into a dated staging folder.
    Returns (stage_dir_path, list of staged file info).
    """
    safe_label = week_label.replace(" ", "_").replace(",", "")
    stage_dir = STAGE_BASE / safe_label
    stage_dir.mkdir(parents=True, exist_ok=True)

    staged = []
    for f in files:
        src = Path(f["path"])
        dst = stage_dir / src.name
        # Avoid name collisions (e.g. two different batches with same filename)
        counter = 1
        while dst.exists():
            dst = stage_dir / f"{src.stem}_{counter}{src.suffix}"
            counter += 1
        link_or_copy(src, dst)
        staged.append({**f, "staged_path": str(dst)})

    return str(stage_dir), staged


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else "stage"
    state = load_state()
    processed_set = set(state.get("processed_files", []))
    week_label = get_week_label()

    by_stem = find_new_media(processed_set)
    files = resolve_live_photos(by_stem)

    if mode == "status":
        print(json.dumps({
            "current_project": state.get("current_project"),
            "current_week": state.get("current_week_start"),
            "week_label": week_label,
            "new_count": len(files),
            "files": files,
        }, indent=2))
        return

    if not files:
        print(json.dumps({
            "new_count": 0,
            "files": [],
            "week_label": week_label,
            "stage_dir": None,
        }))
        return

    # Stage files
    stage_dir, staged = stage_files(files, week_label)

    # Update state — trim processed list to prevent unbounded growth
    existing = state.get("processed_files", [])
    new_paths = [f["path"] for f in files]
    all_processed = existing + new_paths
    state["processed_files"] = all_processed[-MAX_PROCESSED_HISTORY:]
    state["last_processed_timestamp"] = datetime.now().isoformat()
    save_state(state)

    print(json.dumps({
        "new_count": len(staged),
        "files": staged,
        "week_label": week_label,
        "stage_dir": stage_dir,
    }))


if __name__ == "__main__":
    main()
