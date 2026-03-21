-- imovie-gui.applescript
-- GUI automation for iMovie 10.x via System Events.
-- iMovie 10.x has no AppleScript import/project commands — everything via UI.
--
-- Requires: System Settings > Privacy & Security > Accessibility > Terminal ✓
--
-- Called by agent.sh:
--   osascript imovie-gui.applescript create-project "Week of Mar 17, 2026"
--   osascript imovie-gui.applescript import "/Users/.../iMovie-Staged/Week_of_Mar_17_2026"
--   osascript imovie-gui.applescript create-and-import "Week of Mar 17, 2026" "/path/to/staged"

on run argv
    set theAction to item 1 of argv

    if theAction is "create-project" then
        set projectName to item 2 of argv
        my createProject(projectName)

    else if theAction is "import" then
        set stagingPath to item 2 of argv
        my importFromFolder(stagingPath)

    else if theAction is "create-and-import" then
        set projectName to item 2 of argv
        set stagingPath to item 3 of argv
        my createProject(projectName)
        delay 2
        my importFromFolder(stagingPath)
    end if

    return "done"
end run


-- ─────────────────────────────────────────────────────────────────────────────
-- createProject
-- Creates a new iMovie project and renames it from the default "My Movie".
-- Tries four strategies in order until one succeeds.
-- ─────────────────────────────────────────────────────────────────────────────
on createProject(projectName)
    tell application "iMovie" to activate
    delay 2

    my clickMenuItem("File", "New Movie")
    delay 3

    tell application "System Events"
        tell process "iMovie"
            set renamed to false

            -- Strategy 1: text field in the toolbar containing "Movie"
            repeat with attempt from 1 to 4
                try
                    set toolbarElems to UI elements of toolbar 1 of window 1
                    repeat with elem in toolbarElems
                        try
                            if class of elem is text field then
                                set fieldVal to value of elem as text
                                if fieldVal contains "Movie" or fieldVal contains "movie" then
                                    set focused of elem to true
                                    delay 0.2
                                    keystroke "a" using {command down}
                                    delay 0.1
                                    keystroke projectName
                                    keystroke return
                                    delay 0.4
                                    set renamed to true
                                    exit repeat
                                end if
                            end if
                        end try
                    end repeat
                end try
                if renamed then exit repeat
                delay 0.8
            end repeat

            -- Strategy 2: double-click a static text element containing "Movie"
            if not renamed then
                try
                    repeat with st in every static text of window 1
                        try
                            set stVal to value of st as text
                            if stVal contains "My Movie" or stVal contains "Movie" then
                                double click st
                                delay 0.5
                                keystroke "a" using {command down}
                                delay 0.1
                                keystroke projectName
                                keystroke return
                                delay 0.4
                                set renamed to true
                                exit repeat
                            end if
                        end try
                    end repeat
                end try
            end if

            -- Strategy 3: File > Rename Movie… (available in some iMovie versions)
            if not renamed then
                try
                    my clickMenuItem("File", "Rename Movie\u2026")
                    delay 0.5
                    keystroke "a" using {command down}
                    delay 0.1
                    keystroke projectName
                    keystroke return
                    delay 0.4
                    set renamed to true
                end try
            end if

            -- Strategy 4: click the approximate title area at top-center of window
            if not renamed then
                try
                    set winPos  to position of window 1
                    set winSize to size of window 1
                    set centerX to (item 1 of winPos) + ((item 1 of winSize) / 2)
                    set titleY  to (item 2 of winPos) + 50
                    click at {centerX, titleY}
                    delay 0.5
                    keystroke "a" using {command down}
                    delay 0.1
                    keystroke projectName
                    keystroke return
                    delay 0.4
                end try
            end if

        end tell
    end tell

    delay 0.5
end createProject


-- ─────────────────────────────────────────────────────────────────────────────
-- importFromFolder
-- Opens File > Import Media, navigates to the staging folder via Shift+Cmd+G,
-- selects all files, clicks Import, then WAITS for iMovie to finish importing
-- by polling for progress indicators instead of sleeping a fixed duration.
-- ─────────────────────────────────────────────────────────────────────────────
on importFromFolder(stagingFolderPosix)
    tell application "iMovie" to activate
    delay 1.5

    my clickMenuItem("File", "Import Media\u2026")
    delay 3

    tell application "System Events"
        tell process "iMovie"

            -- Navigate to staging folder via Shift+Cmd+G (Go to Folder).
            -- Paste path instead of typing — handles spaces and special chars.
            keystroke "g" using {command down, shift down}
            delay 0.8

            set the clipboard to stagingFolderPosix
            keystroke "v" using {command down}
            delay 0.3
            keystroke return
            delay 1.5

            -- Click the scroll area (file list) to guarantee keyboard focus
            -- before Cmd+A — otherwise Cmd+A might hit a search field instead.
            try
                click scroll area 1 of sheet 1 of window 1
            end try
            try
                click scroll area 1 of window 2
            end try
            delay 0.3

            -- Select all files in the staging folder
            keystroke "a" using {command down}
            delay 0.5

            -- Click the import confirmation button.
            -- iMovie uses "Import All" or "Import Selected" depending on state.
            set importClicked to false

            repeat with winRef in windows
                if importClicked then exit repeat
                try
                    set sheetRef to sheet 1 of winRef
                    repeat with btnRef in buttons of sheetRef
                        set btnName to name of btnRef
                        if btnName is "Import All" or btnName is "Import Selected" or btnName is "Open" then
                            click btnRef
                            set importClicked to true
                            exit repeat
                        end if
                    end repeat
                end try
            end repeat

            if not importClicked then
                repeat with winRef in windows
                    if importClicked then exit repeat
                    try
                        repeat with btnRef in buttons of winRef
                            set btnName to name of btnRef
                            if btnName is "Import All" or btnName is "Import Selected" or btnName is "Open" then
                                click btnRef
                                set importClicked to true
                                exit repeat
                            end if
                        end repeat
                    end try
                end repeat
            end if

            if not importClicked then
                keystroke return
            end if

        end tell
    end tell

    -- ── Wait for import to finish ─────────────────────────────────────────────
    -- Poll for progress indicators (spinning wheels) in the iMovie window.
    -- When they disappear, import is complete. Cap at 3 minutes.
    set maxSeconds to 180
    set elapsed to 0

    -- Give iMovie a moment to start the import before we start polling
    delay 3

    repeat
        delay 2
        set elapsed to elapsed + 2
        if elapsed >= maxSeconds then exit repeat

        try
            tell application "System Events"
                tell process "iMovie"
                    set progCount to count of every progress indicator
                    if progCount is 0 then exit repeat
                end tell
            end tell
        on error
            -- If we can't read UI elements, assume done
            exit repeat
        end try
    end repeat

    -- Final buffer for iMovie to finish writing/indexing
    delay 1
end importFromFolder


-- ─────────────────────────────────────────────────────────────────────────────
-- clickMenuItem
-- Uses `menu 1` (not `menu menuName`) — more reliable across iMovie versions.
-- ─────────────────────────────────────────────────────────────────────────────
on clickMenuItem(menuName, itemName)
    tell application "System Events"
        tell process "iMovie"
            tell menu bar 1
                tell menu bar item menuName
                    tell menu 1
                        click menu item itemName
                    end tell
                end tell
            end tell
        end tell
    end tell
end clickMenuItem
