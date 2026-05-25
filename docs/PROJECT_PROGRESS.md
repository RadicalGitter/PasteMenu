# Project Progress Tracker

This file is optimized for LLM handoff. Keep entries explicit, stable, and easy to update.

Update this tracker after each completed phase or meaningful task. Notes can be brief and pragmatic; future contributors may choose what details are worth preserving.

## Status Legend

- `todo`: not started
- `active`: currently being worked on
- `blocked`: blocked by a decision or external dependency
- `done`: completed and verified
- `parked`: intentionally deferred

## Current Objective

```yaml
objective_id: hotwheel_backend_scaffold
status: active
priority: high
summary: Build backend scaffolding for a future polished hotwheel selector without coupling UI rendering to business logic.
primary_design_doc: docs/HOTWHEEL_DESIGN.md
current_branch: main
last_updated: 2026-05-22
```

## Global Constraints

```yaml
constraints:
  - Keep existing root menu behavior unchanged unless explicitly noted.
  - Keep script-runner work parked unless it blocks Settings or hotwheel architecture.
  - Do not store usage metadata in pastemenu.txt.
  - Keep hotwheel rendering replaceable.
  - Prefer small verified commits.
  - Run tools/smoke_check.bat after AHK code changes.
  - Do not commit dist/, build/, *.exe, or *.lnk files.
```

## Decisions

```yaml
decisions:
  invocation:
    mode: press_and_hold_existing_hotkey
    tap_behavior: open_existing_root_menu
    hold_behavior: open_hotwheel
    default_hold_threshold_ms: 200
    threshold_setting: required
    release_after_open: keep_hotwheel_open
  close_behavior:
    left_click_valid_target: select_and_close
    left_click_empty: close_without_action
    right_click_anywhere: close_without_action
    escape: close_without_action
    unrelated_key: close_without_action
  ordering:
    categories: file_editor_order
    entries: file_editor_order
    empty_categories: hidden_in_hotwheel_v1
  usage:
    ranking: exponential_decay
    default_half_life_minutes: 30
    default_recent_window_feel_hours: 2
    update_on: successful_paste_only
    all_time_mode: future_option
  geometry:
    hit_testing: polar_angle_radius
    dpi_scale: A_ScreenDPI / 96
    center_zone_diameter_px_100pct: 96_to_112
    outer_radius_px_100pct: 260_to_340
    hovered_category_balloon: about_three_fifths_of_fan
```

## Phase Plan

```yaml
phases:
  - id: phase_0_design_lock
    status: done
    goal: Capture hotwheel design and backend-first architecture.
    artifacts:
      - docs/HOTWHEEL_DESIGN.md
      - docs/ROADMAP.md
      - docs/PROJECT_PROGRESS.md
    acceptance:
      - Design includes invocation, usage scoring, geometry, rendering boundaries, and cancellation rules.

  - id: phase_1_usage_stats_backend
    status: done
    goal: Add usage tracking independent of hotwheel rendering.
    proposed_files:
      - includes/core_usage_stats.ahk
    dependencies:
      - existing paste success path in includes/ui_editor.ahk or paste modules
      - DataRootDir from storage startup
    tasks:
      - Add usage state object.
      - Add usage metadata file path under DataRootDir.
      - Implement load/save.
      - Implement record successful paste.
      - Implement decayed ranking.
      - Expose get last-used and most-used APIs.
      - Handle duplicate last-used/most-used by returning second-ranked most-used.
    acceptance:
      - Existing paste behavior unchanged.
      - Usage file created only after successful paste.
      - Smoke check passes.
    notes:
      - Implemented usage.ini under DataRootDir with base64-encoded category/title fields.
      - Successful paste is defined as PasteSnippet reaching a successful FocusPasteTarget call.
      - Public APIs blank out orphaned recent entries by checking currently loaded snippets.
      - Last-used and most-used APIs avoid showing the same category/title in both center slots.
      - Usage cache is keyed by usage file path so storage-root changes reload from the active DataRootDir.
      - Verified with tools/smoke_check.bat and a temporary AHK usage-stats harness.

  - id: phase_2_hotkey_tap_hold_backend
    status: done
    goal: Split configured hotkey into tap=root menu and hold=hotwheel placeholder.
    proposed_files:
      - includes/runtime_hotkeys.ahk
      - includes/ui_settings.ahk
      - includes/core_storage.ahk
    dependencies:
      - placeholder ShowHotwheel function may exist before rendering is complete
    tasks:
      - Add hold threshold setting with default 200 ms.
      - Add Settings UI control for threshold.
      - Implement tap/hold dispatch.
      - Ensure quick tap still opens existing root menu.
      - Ensure hold calls placeholder hotwheel entry point.
    acceptance:
      - Tap opens existing menu.
      - Hold calls placeholder without breaking hotkey registration.
      - Threshold persists.
      - Smoke check passes.
    notes:
      - Configured hotkey now dispatches through tap/hold detection using the physical trigger key stripped from the configured hotkey string.
      - Hold threshold persists as general.hotwheel_hold_threshold_ms with a clamped 100-500 ms range and 200 ms default.
      - Settings exposes the threshold inside the Hotkey group.
      - ShowHotwheel exists as a placeholder lifecycle entry point in includes/ui_hotwheel.ahk.
      - Verified with tools/smoke_check.bat; manual tap/hold hardware feel still needs checking.

  - id: phase_3_geometry_backend
    status: done
    goal: Compute hotwheel geometry independent of drawing.
    proposed_files:
      - includes/ui_hotwheel_geometry.ahk
    dependencies:
      - category and entry data loaded from snippets
    tasks:
      - Define hotwheel geometry config object.
      - Implement DPI scale helper.
      - Implement fan direction selection.
      - Implement center/fan placement.
      - Implement category slice layout in file order.
      - Implement hovered category balloon layout.
      - Implement polar hit testing.
    acceptance:
      - Geometry functions can be exercised without opening a GUI.
      - Hit-test returns stable target descriptors.
      - Smoke check passes.
    notes:
      - Implemented DPI-scaled default geometry config, cardinal fan direction selection, and bounds.
      - Category slices preserve file/editor order and hide empty categories.
      - Hovered category can balloon to 60 percent of the fan; entry slices preserve entry order when entryOrderByCategory is supplied.
      - Hit testing returns center, category, entry, more, or empty descriptors without invoking paste/rendering code.
      - Verified with tools/smoke_check.bat and a temporary AHK geometry harness.

  - id: phase_4_hotwheel_state_backend
    status: done
    goal: Define hotwheel state and view model consumed by renderer.
    proposed_files:
      - includes/ui_hotwheel_state.ahk
    dependencies:
      - phase_1_usage_stats_backend
      - phase_3_geometry_backend
    tasks:
      - Define state object.
      - Define target descriptors.
      - Define view model structure.
      - Map center actions to last-used, most-used, settings.
      - Map category/entry slices to paste actions.
      - Define close reasons.
    acceptance:
      - Renderer can consume view model without reading snippets/settings directly.
      - Click dispatch can be tested from target descriptors.
      - Smoke check passes.
    notes:
      - Implemented state creation, hover updates, view-model generation, close reasons, target descriptors, and left-click outcome mapping.
      - Center actions use usage stats and title-only labels; orphaned/empty recent actions become disabled blank slots.
      - Category/entry/more/center hit targets are mapped to renderer-independent action descriptors.
      - Left-click resolution returns paste/settings/root-menu/none outcomes without executing paste or opening UI.
      - Verified with tools/smoke_check.bat and a temporary AHK state harness.

  - id: phase_5_plain_renderer_prototype
    status: done
    goal: Draw a basic but replaceable hotwheel UI.
    proposed_files:
      - includes/ui_hotwheel_render.ahk
      - includes/ui_hotwheel.ahk
    dependencies:
      - phase_3_geometry_backend
      - phase_4_hotwheel_state_backend
      - decision on GDI+ vendoring
    tasks:
      - Decide drawing approach: vendored GDI+ or simple GUI fallback.
      - Create borderless always-on-top GUI.
      - Render center actions.
      - Render category slices.
      - Render hovered entry expansion.
      - Render hover highlight.
    acceptance:
      - Visual style can be changed without touching usage/geometry/input logic.
      - Opens and closes reliably.
      - Smoke check passes.
    notes:
      - Implemented a plain always-on-top borderless GUI renderer in includes/ui_hotwheel_render.ahk.
      - Renderer consumes only the prepared view model plus geometry objects; it does not load snippets, score usage, or execute actions.
      - ShowHotwheel now performs text-context validation, snippet load, paste-target capture, state creation, and renderer open.
      - Renderer supports center actions, category labels, hovered-category highlighting, and entry labels when the state supplies entry slices.
      - Live hover/click lifecycle is still phase_6_input_and_action_lifecycle.
      - Verified with tools/smoke_check.bat and a temporary AHK renderer harness.

  - id: phase_6_input_and_action_lifecycle
    status: done
    goal: Wire mouse/keyboard interactions to state and paste actions.
    proposed_files:
      - includes/ui_hotwheel.ahk
      - includes/runtime_hotkeys.ahk
    dependencies:
      - phase_5_plain_renderer_prototype
    tasks:
      - Track hover.
      - Left-click valid target selects and closes.
      - Left-click empty closes.
      - Right-click closes.
      - Escape closes.
      - Unrelated key closes.
      - Losing focus closes.
      - Successful entry click pastes to original target.
      - Successful paste updates usage stats.
    acceptance:
      - Normal root menu still works.
      - Hotwheel can paste entries.
      - Hotwheel closes by required actions.
      - Usage stats update only on success.
      - Smoke check passes.
    notes:
      - Added hover timer, left/right mouse hotkeys, Escape handling, unrelated-key cancellation, and focus-lost close handling.
      - Hover updates rebuild state/view model and refresh the plain renderer so category highlighting and entry expansion are visible.
      - Left-click outcomes dispatch outside the renderer: paste reuses PasteSnippet, settings opens Settings, More falls back to the root menu.
      - Right-click, Escape, unrelated key input, focus loss, and empty clicks close without pasting.
      - Renderer refresh is guarded against timer reentrancy so redraw cannot destroy controls while labels are being created.
      - Plain renderer now uses a compact bounded panel with visual hit-target rectangles, avoiding the earlier full fan bounding-box flash on high-DPI ultrawide displays.
      - Focus-loss auto-close is disabled in the prototype, and startup keyboard handling ignores trigger/modifier keys so the held hotkey does not immediately cancel the hotwheel.
      - Verified with tools/smoke_check.bat and a temporary AHK lifecycle harness.
      - Manual external-target paste verification is still recommended before visual polish.
      - Known issue as of 2026-05-25: on real use, holding the hotkey briefly flashes stacked white rectangles/text for one or a few frames and then the hotwheel disappears. The normal quick-tap root menu still opens and normal app usage remains intact.
      - Do not continue visual polish until the hotwheel disappearance is diagnosed. Recommended next debug step: instrument/log close reason and input path firing immediately after ShowHotwheel.

  - id: phase_7_visual_polish
    status: todo
    goal: Improve appearance after backend behavior is stable.
    dependencies:
      - phase_6_input_and_action_lifecycle
    tasks:
      - Tune colors.
      - Tune typography.
      - Tune slice spacing.
      - Tune label clipping.
      - Tune hover contrast.
      - Verify 100/150/200 percent display scale.
    acceptance:
      - UI feels purposeful and readable.
      - No text overlap in common cases.
      - No behavioral regressions.

  - id: script_runner_future
    status: parked
    goal: Improve script runner when it becomes active priority.
    tasks:
      - Gate Explorer folder context behind script-enabled state.
      - Improve Python and PowerShell runner detection.
      - Add selected-file placeholder support.
      - Improve missing-runner errors.
```

## Next Recommended Action

```yaml
next_action:
  id: diagnose_hotwheel_immediate_close
  reason: Hotwheel backend scaffolding is committed, but real hold invocation currently flashes briefly and closes; diagnose lifecycle/input close path before phase_7_visual_polish.
  first_files_to_read:
    - PasteMenu.ahk
    - includes/ui_hotwheel.ahk
    - includes/ui_hotwheel_render.ahk
    - includes/ui_hotwheel_geometry.ahk
    - includes/ui_hotwheel_state.ahk
  first_files_to_create:
    - none
```
