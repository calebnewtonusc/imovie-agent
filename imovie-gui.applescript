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
-- Creates a new iMovie project, then renames it from the default "My Movie".
-- Strategy: File > New Movie, then rename via the title field in the toolbar.
-- ─────────────────────────────────────────────────────────────────────────────
on createProject(projectName)
    tell application "iMovie" to activate
    delay 2

    -- File > New Movie
    my clickMenuItem("File", "New Movie")
    delay 3

    -- iMovie creates the project open in timeline view, title "My Movie" in the toolbar.
    -- We look for the editable title text field in the toolbar and rename it.
    tell application "System Events"
        tell process "iMovie"
            set renamed to false

            -- Strategy 1: find a text field in the toolbar whose value contains "Movie"
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

            -- Strategy 2: look for a static text "My Movie" and double-click it to make editable
            if not renamed then
                try
                    set allStaticTexts to every static text of window 1
                    repeat with st in allStaticTexts
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

            -- Strategy 3: File > Rename Movie… (exists in some iMovie versions)
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

            -- Strategy 4: click the project name area at the top-center of window 1
            -- As a last resort, click ~center-top of the window to hit the title area
            if not renamed then
                try
                    set winPos to position of window 1
                    set winSize to size of window 1
                    set centerX to (item 1 of winPos) + ((item 1 of winSize) / 2)
                    set titleY to (item 2 of winPos) + 50
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
-- selects all files, and clicks Import.
-- ─────────────────────────────────────────────────────────────────────────────
on importFromFolder(stagingFolderPosix)
    tell application "iMovie" to activate
    delay 1.5

    -- File > Import Media…
    my clickMenuItem("File", "Import Media\u2026")
    delay 3

    tell application "System Events"
        tell process "iMovie"

            -- Open "Go to Folder" sheet to navigate directly to staging folder.
            -- Pasting the path is more reliable than typing (handles spaces, unicode).
            keystroke "g" using {command down, shift down}
            delay 0.8

            set the clipboard to stagingFolderPosix
            keystroke "v" using {command down}
            delay 0.3
            keystroke return
            delay 1.5

            -- Ensure the file list (scroll area) has keyboard focus before Cmd+A.
            -- Without this, Cmd+A might select text in a search field instead.
            try
                -- The file browser is scroll area 1 of the open panel (sheet or window)
                set panelRef to sheet 1 of window 1
                click scroll area 1 of panelRef
            end try
            try
                -- Fallback: open panel may be a standalone window
                set panelRef to window 2
                click scroll area 1 of panelRef
            end try
            delay 0.3

            -- Select all files in the staging folder
            keystroke "a" using {command down}
            delay 0.5

            -- Click the import confirmation button.
            -- iMovie uses "Import All" or "Import Selected" depending on selection state.
            set importClicked to false

            -- Check sheets first (panel attached to main window)
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

            -- Check standalone windows (panel not attached as sheet)
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

            -- Last resort: Return key to confirm
            if not importClicked then
                keystroke return
            end if

            -- Wait for import — scale with number of files but cap at 30s
            delay 5

        end tell
    end tell
end importFromFolder


-- ─────────────────────────────────────────────────────────────────────────────
-- clickMenuItem
-- Clicks a top-level menu item. Uses `menu 1` (not `menu menuName`) for
-- reliability — the inner menu object's name can differ from the bar item label.
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
