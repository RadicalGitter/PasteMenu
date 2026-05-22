# Script Runner Design (Folder + Multi-Language)

This document specifies how to add a script runner feature to the refactor architecture while preserving current behavior.

## Goal

Allow users to select a folder and run scripts from the PasteMenu root menu, with configurable interpreter mapping by file extension.

## Scope

- In scope:
  - Folder-based script discovery.
  - Extension-to-runner mapping (for example `.ps1`, `.py`, `.js`, `.ahk`, `.cmd`, `.bat`).
  - Menu integration in root context menu.
  - Settings integration and persistence in `settings.ini`.
  - Safe execution defaults and clear error reporting.
- Out of scope (initial release):
  - Passing custom runtime arguments per invocation.
  - Script output capture inside custom GUI.
  - Recursive folder browsing UI tree.

## Integration Points

- Entry script:
  - `PasteMenu.ahk`
  - Add globals and include: `#Include .\includes\script_runner.ahk`
- Menu wiring:
  - `includes/runtime_context_menu.ahk`
  - Add a root action/submenu for scripts.
- Settings and persistence:
  - `includes/core_storage.ahk`
  - Extend `LoadSettings()`, `SaveSettings()`, and `T(key)`.
  - `includes/ui_settings.ahk`
  - Add controls for enable/folder/refresh and optional mapping editor launch.
- Startup:
  - `includes/startup.ahk`
  - Initialize script runner state/cache.

## New Module

Create `includes/script_runner.ahk`.

### State

Use a single global object:

```ahk
_ScriptRunnerState := {
    enabled: false,
    folder: "",
    recursive: false,
    requireConfirm: true,
    showConsole: true,
    waitForExit: false,
    maxItems: 80,
    mapping: Map(),     ; ext -> {runnerExe, argsTemplate}
    cacheTick: 0,
    cacheItems: [],     ; [{name, path, ext, runnerExe, argsTemplate}]
    lastError: ""
}
```

### Functions (module API)

- `ScriptRunnerInitDefaults()`
- `ScriptRunnerLoadFromSettings()`
- `ScriptRunnerSaveToSettings()`
- `ScriptRunnerSetFolder(path)`
- `ScriptRunnerRefreshCache(force := false)`
- `ScriptRunnerGetMenuItems()`
- `ScriptRunnerBuildMenu(parentMenu)`
- `ScriptRunnerMenuRun(path, *)`
- `ScriptRunnerRun(path)`
- `ScriptRunnerResolveCommand(path, &exe, &args, &workDir)`
- `ScriptRunnerValidatePath(path)`
- `ScriptRunnerLog(text)`

### Function Responsibilities

- `ScriptRunnerInitDefaults()`:
  - Create default mapping table if missing.
  - Suggested defaults:
    - `.ps1 -> pwsh.exe | -NoProfile -ExecutionPolicy Bypass -File "{script}"`
    - `.py -> python.exe | "{script}"`
    - `.js -> node.exe | "{script}"`
    - `.ahk -> AutoHotkey64.exe | "{script}"`
    - `.cmd -> cmd.exe | /c "{script}"`
    - `.bat -> cmd.exe | /c "{script}"`
- `ScriptRunnerRefreshCache()`:
  - Enumerate folder files (optionally recursive).
  - Keep only mapped extensions.
  - Sort alphabetically.
  - Cap to `maxItems`.
- `ScriptRunnerResolveCommand()`:
  - Use extension mapping.
  - Replace `{script}` placeholder with quoted absolute path.
  - Use script parent folder as working directory.
- `ScriptRunnerValidatePath()`:
  - Require file exists.
  - Require extension is mapped.
  - Require target path is inside configured folder (canonicalized).
- `ScriptRunnerRun()`:
  - Optional confirm dialog.
  - `Run` or `RunWait` based on setting.
  - Log success/failure and show localized error on failure.

## Settings Schema

Persist in `settings.ini` (same file as current app settings):

```ini
[script_runner]
enabled=0
folder=
recursive=0
require_confirm=1
show_console=1
wait_for_exit=0
max_items=80

[script_runner_lang]
.ps1=pwsh.exe|-NoProfile -ExecutionPolicy Bypass -File "{script}"
.py=python.exe|"{script}"
.js=node.exe|"{script}"
.ahk=AutoHotkey64.exe|"{script}"
.cmd=cmd.exe|/c "{script}"
.bat=cmd.exe|/c "{script}"
```

Notes:
- Store each mapping as `runner|argsTemplate`.
- Unknown or malformed lines should be ignored safely.

## Menu UX

### Root Menu Placement

Add a new root-level action near existing non-category actions:
- Label: `Run script`
- Behavior:
  - If disabled/unconfigured: show tooltip or open settings.
  - If configured: open submenu with script items.

### Scripts Submenu

- Top utility items:
  - `Refresh scripts`
  - `Open scripts folder`
  - `Configure scripts...`
- Separator.
- Script items:
  - Display `filename.ext`.
  - Optional extension prefix when many mixed types.
- If no items:
  - `(no runnable scripts)`

## Settings UX

Add section in `OpenSettingsWindow()`:
- `Enable script runner` checkbox.
- `Scripts folder` text field.
- `Browse...` button (folder select).
- `Refresh` button.
- Optional advanced button: `Language mappings...` (phase 2).

Expected behavior:
- Save immediately on toggle/change, consistent with existing settings.
- If folder is invalid, disable run action and show clear message.

## Localization Keys

Add keys to `T(key)` (both `sv` and `en`):

- `settings_scripts`
- `settings_scripts_enable`
- `settings_scripts_folder`
- `settings_scripts_browse`
- `settings_scripts_refresh`
- `settings_scripts_configure`
- `menu_run_script`
- `menu_run_script_refresh`
- `menu_run_script_open_folder`
- `menu_run_script_empty`
- `msg_script_runner_disabled`
- `msg_script_folder_missing`
- `msg_script_run_confirm`
- `msg_script_run_failed`
- `msg_script_no_mapping`

## Safety Model

Defaults should be conservative:

- Feature disabled by default.
- Confirmation required by default.
- Only run files under configured folder.
- Only run mapped extensions.
- No inline command concatenation from file name.
- Always quote script path.
- Log all run attempts to `DataRootDir\script_runner.log`.

## Performance

- Cache script list with short TTL (for example 2-3 seconds).
- Re-scan on explicit refresh.
- Hard cap displayed items (`maxItems`) to keep menu responsive.
- For very large folders, show first N and include `Open scripts folder`.

## Error Handling

Handle and surface:
- Missing folder.
- Missing mapping for extension.
- Runner executable unavailable.
- Script path invalid/outside allowed root.
- `Run`/`RunWait` failure.

Errors should use localized `MsgBox` or transient tooltip, consistent with current module style.

## Implementation Sequence

1. Add `script_runner.ahk` with state, mapping parser, cache, command resolver, runner.
2. Extend `core_storage.ahk` with load/save fields and new translation keys.
3. Add settings controls in `ui_settings.ahk` for enable/folder/refresh.
4. Add root-menu/submenu wiring in `runtime_context_menu.ahk`.
5. Optional tray shortcut in `runtime_hotkeys.ahk` (`Run script...`).
6. Update `SMOKE_CHECKLIST.md` with script-runner checks.

## Smoke Checks (Additions)

- Enable script runner, set valid folder, refresh.
- Confirm scripts appear in root menu.
- Run one script per enabled extension mapping.
- Validate path guard by trying a symlink/out-of-root path scenario.
- Disable runner and confirm menu action is blocked with clear message.
- Confirm settings persist after restart.
