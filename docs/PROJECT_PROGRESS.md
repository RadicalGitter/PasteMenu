# Project Progress Tracker

This file is optimized for LLM handoff. Keep entries explicit, stable, and easy to update.

## Status Legend

- `todo`: not started
- `active`: currently being worked on
- `blocked`: blocked by a decision or external dependency
- `done`: completed and verified
- `parked`: intentionally deferred

## Current Objective

```yaml
objective_id: hotwheel_backend_scaffold
status: todo
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
    status: todo
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

  - id: phase_2_hotkey_tap_hold_backend
    status: todo
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

  - id: phase_3_geometry_backend
    status: todo
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

  - id: phase_4_hotwheel_state_backend
    status: todo
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

  - id: phase_5_plain_renderer_prototype
    status: todo
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

  - id: phase_6_input_and_action_lifecycle
    status: todo
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
  id: phase_1_usage_stats_backend
  reason: Usage stats are independent, low-risk, and needed by the hotwheel center actions.
  first_files_to_read:
    - PasteMenu.ahk
    - includes/paste_markup.ahk
    - includes/ui_editor.ahk
    - includes/runtime_context_menu.ahk
    - includes/core_storage.ahk
  first_files_to_create:
    - includes/core_usage_stats.ahk
```
