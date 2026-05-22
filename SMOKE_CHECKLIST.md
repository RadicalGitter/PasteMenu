# Refactor Smoke Checklist

Run automated checks first:
- `smoke_check.bat`

Then run these manual checks against `PasteMenu.ahk`:

1. Menu open/paste
- Focus a text field.
- Trigger hotkey.
- Paste plain entry and rich entry.
- Confirm paste targets caret (not mouse).

2. Root menu behavior
- Confirm selected-entry section placement near click.
- Confirm outside left-click closes menu.
- Confirm flip behavior near top/bottom screen edges.

3. Editor flows
- Open `Entry editor`.
- Add entry, edit entry, delete entry.
- Move entry with `Move...`.
- Drag to reorder inside category.
- Drag to another category via category list.
- Switch category and confirm editor window stays open.

4. Backup/restore/undo
- Make a few entry changes.
- Open Settings and confirm `Restore backup` enables.
- Restore one per-change item and confirm only that entry state changes.
- Confirm restored per-change item is removed from restore list.
- Press `Undo` and confirm change is reverted and per-change item reappears.
- Test full backup restore and undo.

5. Storage migration
- Change storage mode and run `Migrate`.
- Confirm snippets/settings/backups moved and paths update in settings.

6. Hotkey capture
- Open hotkey dialog.
- Capture keyboard combo and mouse button combo.
- Confirm hotkey updates and menu still opens in text context.

7. Script runner (folder + mappings)
- Open Settings and enable `Script runner`.
- Select a scripts folder with at least one mapped extension (`.ps1`, `.py`, `.js`, `.ahk`, `.cmd`, `.bat`).
- In Explorer (folder context), open root menu and verify only script entries appear.
- Run one script from folder context and confirm it launches.
- In a text field, open root menu and verify `Paste script as text` appears.
- Choose one script there and confirm the file content is pasted as plain text (not executed).
- Disable script runner and verify submenu shows disabled/configure state.
