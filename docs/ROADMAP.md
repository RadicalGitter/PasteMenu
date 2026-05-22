# PasteMenu Roadmap

This is a running long-horizon scope list. It is not a release promise; it is a place to keep good ideas visible while keeping day-to-day changes focused.

## Near-Term 1.0 Focus

- Polish the core text/snippet workflow before expanding script-runner behavior.
- Make the UI feel more deliberate and professional:
  - consistent spacing and button sizing
  - clearer labels
  - fewer mixed Swedish/English strings in the same surface
  - less crowded settings/editor layouts
  - predictable keyboard/mouse cancellation behavior
- Keep the root menu fast and low-friction.
- Keep storage, backup, restore, undo, and editor behavior stable.
- Add manual QA notes for the most important workflows before tagging 1.0.

## UI And Interaction Polish

- Review every user-facing window for:
  - stable dimensions
  - readable grouping
  - clear primary/secondary actions
  - disabled controls when unavailable
  - predictable Escape/Close behavior
- Consider a more visual quick selector for frequent actions. See `docs/HOTWHEEL_DESIGN.md`.
- Hotwheel direction is press-and-hold on the existing hotkey, with a fast configurable threshold.
- Consider a denser, more polished Entry Editor layout after behavior is stable.
- Reduce generated-style comments and replace them with fewer useful notes.
- Standardize terminology:
  - entry vs snippet
  - text vs paste
  - scripts vs script functionality

## Refactor Candidates

- Split `includes/core_storage.ahk`:
  - storage/path resolution
  - settings persistence
  - localization strings
  - migration helpers
- Split `includes/ui_editor.ahk`:
  - editor window construction
  - editor CRUD actions
  - inline rename
  - drag/drop logic
- Centralize path helpers:
  - one path normalization helper
  - one path comparison helper
  - shared canonicalization strategy for safety checks
- Replace broad `SaveSettings()` calls with smaller section-specific saves where practical.
- Keep script-runner work parked unless it blocks settings/menu quality.

## Script Runner Parking Lot

Script functionality exists but is not the current priority. Future improvements:

- Make disabled script functionality disappear fully from normal app flow, including Explorer folder-context activation.
- Improve default runner resolution:
  - PowerShell: prefer `pwsh.exe`, fallback to `powershell.exe`
  - Python: prefer `py.exe -3`, fallback to `python.exe`
- Show clearer missing-runner errors.
- Add `{files}` placeholder support for selected Explorer files.
- Consider optional per-run argument prompts.
- Consider a simpler mapping editor for common Python/PowerShell use before exposing advanced mappings.
- Harden path validation around symlinks and canonical paths if scripts become a major feature.

## Release Hygiene

- Keep generated files ignored:
  - `dist/`
  - `build/`
  - `*.exe`
  - `*.lnk`
- Prefer GitHub Releases for user-facing binaries instead of committing executables.
- Before 1.0:
  - run `tools/smoke_check.bat`
  - run the manual checklist in `docs/SMOKE_CHECKLIST.md`
  - manually verify install/run/build from a clean checkout
