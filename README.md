# PasteMenu

PasteMenu is an AutoHotkey v2 utility for fast snippet insertion with:
- categorized entries
- quick entry creation and editing
- rich-text/link markup support
- backup/restore with undo

## Attribution

This project was developed cooperatively by the project owner and ChatGPT Codex 5.3.

The modular refactor is now the main codebase. The old single-file script is archived on the `legacy-single-file-obsolete` branch.

## Start Here

Use this file for active development:
- `PasteMenu.ahk`

## Requirements

- Windows
- AutoHotkey v2 (64-bit recommended)

## Run

1. Install AutoHotkey v2
2. Launch:
   - `PasteMenu.ahk`

## Build

If your compiler setup is ready, use:
- `build_pastemenu.bat`

## Validation

Automated smoke checks:
- `smoke_check.bat`

Manual checklist:
- `SMOKE_CHECKLIST.md`

Behavior parity overview:
- `BEHAVIOR_PARITY.md`

## Project Structure

- `includes/core_storage.ahk`  
  Storage detection/migration (Dropbox/OneDrive/AppData)
- `includes/script_runner.ahk`  
  Script-folder discovery, extension mapping, and safe script execution
- `includes/core_snippets_backup.ahk`  
  Snippet parsing/saving, tiered backups, restore metadata
- `includes/runtime_hotkeys.ahk`  
  Hotkey registration and capture
- `includes/runtime_context_menu.ahk`  
  Text-context checks, root menu behavior
- `includes/ui_settings.ahk`  
  Settings window and actions (restore/undo/migrate)
- `includes/ui_editor.ahk`  
  Category/entry editor, move/reorder, drag/drop
- `includes/paste_markup.ahk`  
  Rich/plain paste and markup conversion
- `includes/startup.ahk`  
  Startup initialization flow

## Contributing

Short contributor guide:
- `CONTRIBUTING_SHORT.md`

Refactor notes and phased plan:
- `REFACTOR_NOTES.md`

## Notes

- `main` is the intended path forward for new work.
- `legacy-single-file-obsolete` preserves the old single-file script for reference.
