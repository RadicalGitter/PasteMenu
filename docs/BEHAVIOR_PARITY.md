# Behavior Parity Guide (Legacy vs Main)

This document is written for practical verification, not deep code theory.

## Quick Summary
- Goal: `PasteMenu.ahk` should behave the same as the old single-file script, but with cleaner internal structure.
- Result: Core features are preserved, and code is split into modules for easier maintenance.
- The old single-file script is archived on the `legacy-single-file-obsolete` branch.

## What This Means in Plain Language
- **Legacy branch** = archival reference only.
- **Main** = the version intended for ongoing development.
- Use this file for new work:
  - `PasteMenu.ahk`

## Side-by-Side Feature Status
Legend:
- `Same` = behavior intended to match
- `Improved` = same feature, cleaner/safer internals
- `Known issue` = baseline issue in locked original snapshot

| Feature | Legacy | Main | Status |
|---|---|---|---|
| Open menu in text context | Intended | Present | Same |
| Paste at caret target | Intended | Present | Same |
| Close menu on outside click | Intended | Present | Same |
| Category editor opens and edits entries | Intended | Present | Same |
| Switch category without reopening editor window | Intended | Present | Same |
| Move entry via button | Intended | Present | Same |
| Drag reorder in category | Intended | Present | Same |
| Drag entry to another category | Intended | Present | Same |
| Backup creation with retention tiers | Intended | Present | Same |
| Per-change restore (entry-level) | Intended | Present | Same |
| Undo restore (full + per-change) | Intended | Present | Same |
| Storage migration + show files | Intended | Present | Same |
| Hotkey capture/settings integration | Intended | Present | Same |
| Script load/parse health | Historical reference | Passes | Same target behavior |

## Where Things Moved (Easy Map)
- `includes/core_storage.ahk`
  - storage location logic, Dropbox/OneDrive/AppData, migration helpers
- `includes/core_snippets_backup.ahk`
  - snippet parsing/saving, backup tiers, change-backup metadata, restore helpers
- `includes/runtime_hotkeys.ahk`
  - hotkey registration and capture
- `includes/runtime_context_menu.ahk`
  - text-context detection, root popup behavior, menu close behavior
- `includes/ui_settings.ahk`
  - settings window, restore/undo buttons, settings events
- `includes/ui_editor.ahk`
  - category/entry editor, quick entry, drag/drop, entry actions
- `includes/paste_markup.ahk`
  - plain/rich paste conversion and clipboard HTML helpers
- `includes/startup.ahk`
  - startup flow

## How To Verify Quickly (Non-Programmer Friendly)
1. Run:
   - `tools\smoke_check.bat`
2. Start:
   - `PasteMenu.ahk`
3. Try these in order:
   - open menu in a text field and paste a snippet
   - open editor, add/edit/delete one entry
   - move one entry to another category
   - drag one entry to reorder
   - open Settings -> restore one per-change backup
   - click `Undo` and verify it reverts
4. If all those work, parity is functionally good for normal use.

## Why This Refactor Helps
- Easier to find code by purpose
- Safer to change one area without breaking unrelated parts
- Better for public repository collaboration

## Recommended Next Step
- Use `PasteMenu.ahk` as your active development file.
- Use `legacy-single-file-obsolete` only for historical comparison.
