# iMovie Agent

AirDrop clips, photos, and Live Photos to your Mac, then say the word and they're in iMovie. Automatically creates weekly projects, imports in chronological order, and handles Live Photos correctly.

## What it does

- Scans `~/Downloads` for new media files (photos, videos, Live Photos)
- Stages them into `~/Movies/iMovie-Staged/<week>/` in chronological order
- Opens iMovie, creates a weekly project if needed, and imports everything
- Tracks what's already been imported so re-runs are safe
- Listens to Willow voice transcripts and triggers automatically when you say "AirDrop" or "import clips"

## Requirements

- macOS with iMovie 10.x installed
- Python 3.8+
- **Accessibility permissions** for your terminal app:
  `System Settings > Privacy & Security > Accessibility > add Terminal ✓`

## Setup

```bash
git clone https://github.com/calebnewtonusc/imovie-agent
cd imovie-agent
chmod +x agent.sh willow-trigger.sh stage-media.py
```

## Usage

```bash
# Detect new AirDrop media and import into this week's project
./agent.sh

# Check what would be imported without doing anything
./agent.sh --status

# Force a new weekly project even mid-week
./agent.sh --new

# Import into a specific named project
./agent.sh --project "Summer Trip 2026"

# Import into whatever project is currently open, skip create step
./agent.sh --import-only
```

## Claude Code command

If you use [Claude Code](https://claude.ai/code), add the `/imovie` command by copying `imovie.md` to `~/.claude/commands/imovie.md`. Then in any chat:

> "yo I just AirDropped some clips"

Claude will run the agent automatically.

## Willow voice trigger

If you use [Willow](https://www.seewillow.com) for voice notes, run the trigger daemon once:

```bash
bash willow-trigger.sh &
```

Say anything like **"AirDrop some clips to iMovie"** or **"import new footage"** and it fires automatically. Say **"new project"** to force a fresh weekly project.

To run it persistently across reboots, add to launchd:

```xml
<!-- ~/Library/LaunchAgents/com.imovieagent.willow.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>            <string>com.imovieagent.willow</string>
    <key>ProgramArguments</key> <array><string>/bin/bash</string><string>/path/to/willow-trigger.sh</string></array>
    <key>RunAtLoad</key>        <true/>
    <key>KeepAlive</key>        <true/>
    <key>StandardOutPath</key>  <string>/tmp/imovie-willow.log</string>
    <key>StandardErrorPath</key><string>/tmp/imovie-willow.log</string>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.imovieagent.willow.plist
```

## How Live Photos work

iPhones AirDrop Live Photos as two files: `IMG_xxxx.HEIC` (still) + `IMG_xxxx.MOV` (motion). The agent automatically detects these pairs by matching filenames and imports only the `.MOV`, so you get the motion clip in your timeline, not a static photo.

## File structure

```
imovie-agent/
├── agent.sh              # Main orchestrator
├── stage-media.py        # Media detection + staging (Python)
├── imovie-gui.applescript# iMovie GUI automation via System Events
├── willow-trigger.sh     # Willow voice transcript watcher
├── state.json            # Tracks current project + processed files
└── .claude/commands/
    └── imovie.md         # Claude Code slash command
```

## State

`state.json` tracks which files have been imported so you can safely re-run the agent (e.g. AirDrop more clips mid-week). It also remembers the current project name so any new Claude chat session can pick up where you left off.

## Notes on iMovie automation

iMovie 10.x has no AppleScript dictionary for importing or creating projects, the agent uses `System Events` GUI automation (click-level scripting). This means:

- **Accessibility permission is required**: the agent will tell you if it's missing
- iMovie must be accessible and not locked behind another full-screen app
- Import waits 5 seconds after clicking, large batches may need a moment longer before iMovie finishes; the clips will all be there
- If the automation fails, your files are always safely staged in `~/Movies/iMovie-Staged/`, just open iMovie > File > Import Media and point it there

## License

MIT

All glory to God! ✝️❤️
