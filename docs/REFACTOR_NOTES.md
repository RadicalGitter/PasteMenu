# PasteMenu Refactor Notes

## Current State
- Single-file script (`PasteMenu.ahk`) with mixed concerns:
  - storage detection/migration
  - settings and tray UI
  - editor UI and drag/drop
  - snippet parsing/serialization
  - backup/restore/undo
  - hotkey capture and runtime hooks

## Recommended Split (Behavior-Preserving)
1. `core_storage.ahk`
- data root resolution
- provider detection (Dropbox/OneDrive/AppData)
- migration helpers

2. `core_snippets.ahk`
- snippet parse/load/save
- text normalization and atomic writes

3. `core_backup.ahk`
- tiered backup creation/prune
- change metadata serialization
- restore/undo operations

4. `ui_settings.ahk`
- settings window
- settings actions and button state updates

5. `ui_editor.ahk`
- category/entry editor
- drag/drop visuals
- quick entry flows

6. `runtime_hotkeys.ahk`
- hotkey registration/capture
- context detection
- menu open/close hooks

## Refactor Order (Low Risk to Higher Risk)
1. Move pure helpers first (string/date/path formatting, encoding, base64).
2. Move storage and snippet I/O.
3. Move backup/restore with no behavior changes.
4. Move settings UI and actions.
5. Move editor UI and drag/drop.
6. Final pass for global-state reduction.

## Testing Checklist After Each Step
- Script parses with `/ErrorStdOut`.
- Open menu and paste plain/rich text.
- Editor actions: add/edit/delete/move/drag.
- Category switching in-place still works.
- Backup creation appears in `backups` folder.
- Per-change restore removes item from list.
- Undo restores previous state and reinserts per-change item.
- Storage migrate preserves snippets/settings/backups.

## Performance Notes
- Keep backup directory scans bounded (already pruned by tier limits).
- Avoid full backup list refresh on every UI event unless needed.
- Keep expensive file reads behind explicit actions (`Restore` dialogs).
