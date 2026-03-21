Update iMovie with recently AirDropped media. Run immediately — no clarifying questions.

## Step 1: Find the agent and check status

Locate the agent directory (wherever you cloned this repo):
```
AGENT=$(find ~ -maxdepth 6 -name "agent.sh" -path "*/imovie-agent/*" 2>/dev/null | head -1)
bash "$AGENT" --status
```

Parse output: file count, target project, whether it's a first run.

## Step 2: Import based on what the user said

- Default / "yo I AirDropped clips" / "update iMovie" → no flags (auto mode)
- "add to current project" → `--import-only`
- "new project" / "start fresh" / new week → `--new`
- "add to [name]" → `--project "Name"`
- "just last N days" → `--since-days N`
- "import everything" → `--all`

```
bash "$AGENT" [flags]
```

## Step 3: Report back
- Files imported, project name, any Live Photos auto-converted to MOV
- Staged folder path, any errors + manual fallback instructions

## Notes
- First run auto-limits to last 14 days — use `--all` to override
- Files are staged to `~/Movies/iMovie-Staged/<week>/` before import — safe to run twice
- State in `state.json` persists across chat sessions
- Willow daemon (`willow-trigger.sh`) can auto-fire this on voice command
