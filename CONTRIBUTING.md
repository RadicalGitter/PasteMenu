# Contributing (Short Guide)

This is the practical guide for making safe changes quickly.

## 1) Use Main
- Develop in: `PasteMenu.ahk` and `includes/`.
- The old single-file script is archived on `legacy-single-file-obsolete`.

## 2) Keep Changes Scoped
- Change one area at a time (for example: settings UI, backup logic, editor drag/drop).
- Prefer editing one include file in `includes/` instead of many files at once.

## 3) Validate Before Commit
Run:
- `tools/smoke_check.bat`

Then do quick manual checks:
- Open menu and paste in a text field.
- Add/edit/delete/move one entry in editor.
- Test restore + undo once.

Manual checklist:
- `docs/SMOKE_CHECKLIST.md`

## 4) Preserve Behavior First
- Refactor for readability/structure without changing user behavior unless explicitly intended.
- If behavior changes are intentional, document them in your PR/commit message.

## 5) Commenting Standard
- Every function should keep a short header comment.
- Add inline comments only where logic is not obvious.
- Prefer clear naming over excessive comments.

## 6) Backup/Restore Safety
- Be careful when changing:
  - `core_snippets_backup.ahk`
  - `ui_settings.ahk`
- Always re-test per-change restore and undo after those changes.

## 7) Suggested Commit Style
- `refactor: ...` for structural cleanup
- `fix: ...` for behavior bugs
- `feat: ...` for new user-visible functionality

## 8) If You Are Unsure
- Keep the change small.
- Run smoke checks.
- Ask for review before stacking more changes.
