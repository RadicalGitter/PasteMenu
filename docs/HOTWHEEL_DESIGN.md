# Hotwheel Selector Design

## Goal

Add a fast visual selector for frequent paste actions without replacing the existing root menu. The current menu remains the dependable fallback and full editor/settings surface. The hotwheel is optimized for quick, repeated paste selection.

The main implementation priority is backend scaffolding that can host a polished graphical design later. The first working version may look plain, but the data, geometry, input, and rendering boundaries should be clean enough that visual design can be improved without rewriting behavior.

## Concept

Holding the existing hotkey opens a fan-shaped selector near the cursor. A quick tap keeps opening the current root menu.

The fan is not a full circle. It should align in an available cardinal direction so it can avoid screen edges more naturally than a radial menu. Corner cases can be handled later; the first version can use a simple best-fit direction.

## Architecture Priority

Build the feature as a small interaction system, not as one large drawing function.

Core boundaries:

- Usage data decides last-used and most-used entries.
- Geometry decides fan direction, center point, ring radii, slice angles, and hit testing.
- State decides open/hover/selected/closing behavior.
- Rendering consumes prepared slices, labels, hover states, and style tokens.
- Input handling dispatches hotkey/tap/hold, mouse hover, left-click, right-click, Escape, and cancellation.
- Paste execution reuses existing paste functions and does not live inside the renderer.

Desired module shape:

- `includes/core_usage_stats.ahk`
  - last-used and decayed most-used tracking
  - usage persistence
- `includes/ui_hotwheel_geometry.ahk`
  - placement
  - slice layout
  - DPI scaling
  - polar hit testing
- `includes/ui_hotwheel_state.ahk`
  - open state
  - hover state
  - selected category/entry
  - close reasons
- `includes/ui_hotwheel_render.ahk`
  - GDI+/GUI drawing
  - style tokens
  - label rendering
- `includes/ui_hotwheel.ahk`
  - public entry points
  - lifecycle orchestration

This can be fewer files at first, but those boundaries should remain visible in the code.

## Invocation

The trigger is shared with the root menu: a quick tap opens the root menu, a hold opens the hotwheel. The key design problem is separating those two cleanly without making either feel sluggish.

Use an appears-after-commit model:

- On press, start waiting; show nothing yet.
- If the button is released before the threshold, it was a tap and opens the root menu.
- If the button is still held at the threshold, it was a hold and opens the hotwheel.
- After the hotwheel opens, releasing the hotkey does not close it.

Threshold settings:

- Default: around 200 ms.
- Configurable in Settings.
- Suggested range: 100-500 ms.
- Values below roughly 100-120 ms risk turning normal taps into hotwheel opens.

Implementation idiom:

```ahk
; triggerKey is the configured trigger; thresholdSeconds is e.g. 0.20.
if KeyWait(triggerKey, "T" thresholdSeconds)
    ShowSnippetMenu()
else
    ShowHotwheel()
```

Macro-mouse caveat:

- Some macro mice do not emit reliable button-up events.
- Test release detection on the actual trigger hardware.
- Sticky hotwheel behavior degrades better than release-to-cancel if button-up events are unreliable.

## Placement

The fan should appear so the cursor starts near the interaction center, not at an outer edge.

Initial placement heuristic:

- Treat the hotwheel as a semicircle or fan sector with a base.
- Put the cursor around the central lower control area, roughly one fifth of the fan diameter above the flat side of the semicircle.
- Choose fan direction based on available screen space:
  - prefer upward fan if there is room above the cursor
  - otherwise use downward, rightward, or leftward fan
  - ignore complex corner optimization in v1
- Directional language such as above/left/right is relative to the fan orientation, not the screen.

Suggested sizing:

- Center zone diameter: 96-112 px at 100% scaling.
- Outer fan radius: 260-340 px at 100% scaling.
- Multiply all dimensions by `A_ScreenDPI / 96` from day one.
- Minimum category slice angle/width should preserve readable labels.
- Hovered category slice can balloon to roughly three fifths of the total fan width/arc to create room for entries.

## Center Zone

The center zone is the high-confidence area for the most common actions.

Suggested layout:

- Center: last used paste.
- Left of center: most-used paste.
- Right of center: settings.
- Angular widths are weighted so the center last-used action is the largest/easiest target, tapering to the flanks.

Behavior:

- Hover highlights an item.
- Left-click activates the highlighted item.
- Releasing the hotkey does not close the hotwheel.
- Any unrelated key input cancels.
- Clicking settings opens Settings and closes the hotwheel.
- Clicking a paste item pastes and closes the hotwheel.
- Left-clicking an unavailable/empty area closes the hotwheel without pasting.
- Right-clicking anywhere closes the hotwheel without pasting.

## Usage Scoring

Requirements:

- Use recent decaying usage, not pure all-time count.
- Default scoring window should feel like the last 2 hours.
- More recent usage should matter more than older usage.
- A long-time leader should be easy to overtake.
- All-time mode can be a future option, but it is not the default.

Recommended model:

- Store per entry:
  - `score`
  - `lastUsed`
- Evaluate decay lazily; do not run a background timer.
- Use exponential decay with a half-life.

Formula:

```text
on successful paste at time now:
    score = score * 0.5 ^ ((now - lastUsed) / halfLife)
    score = score + 1
    lastUsed = now

ranking at time now:
    effective = score * 0.5 ^ ((now - lastUsed) / halfLife)
```

Starting values:

- Half-life: around 30 minutes.
- Lookback feel: around 2 hours.
- With a 30-minute half-life, an unused leader decays to roughly 6% after 2 hours.

Rules:

- Update usage stats only after successful paste, not on attempted selection.
- Last-used is the entry with the latest successful paste timestamp.
- Most-used is the entry with the highest decayed effective score.
- If last-used and most-used are the same entry, show the second-ranked entry in the most-used slot.

Open question:

- Should center labels show category + title, or title only?

## Outer Fan

Outside the center zone, the fan displays categories.

Category behavior:

- Categories are arranged automatically into equal-size slices.
- Category order follows file/editor order for stable muscle memory.
- Moving the mouse over a category highlights that slice.
- Hovering a category expands/balloons that category to roughly three fifths of the fan, then shows entries inside that larger area.
- Clicking an entry pastes it and closes the hotwheel.
- The hotwheel does not expose add/edit/delete actions.

Entry behavior:

- Entry order follows file/editor order.
- Entry labels should be readable and clipped gracefully.
- If a category has too many entries, v1 can show the first N and leave overflow for the normal menu/editor.

Capacity guidance:

- A 180-degree fan comfortably holds about 5-6 labeled categories.
- 8 categories is a reasonable upper squeeze limit.
- Beyond that, prefer a `More...` slice that opens/falls back to the root menu.
- A ballooned category of roughly three fifths of the fan comfortably holds about 5-6 entries.

Ballooning caveat:

- Expanding a slice in place can push neighboring slices and cause targets to move under the cursor.
- Prototype this before committing to it.
- If neighbor shift feels slippery, expand the hovered category outward into a concentric entry ring instead of pushing siblings sideways.

Empty categories:

- Recommended v1 behavior: hide empty categories in the hotwheel.

## Visual Style

Target feel:

- quiet, fast, and purposeful
- no decorative effects that slow recognition
- clear hover state
- readable labels
- stable geometry while moving the mouse

Suggested style:

- subtle translucent background
- restrained color variation for category slices
- strong highlight on hovered slice
- center actions visually distinct from category slices
- no animation until the interaction model is correct

Renderer rule:

- The renderer should consume a prepared view model of slices, labels, states, and actions.
- The renderer should not decide what is most-used, how snippets load, or what a click means.

## Prior Art And Libraries

GDI+ is likely the pragmatic drawing layer. Before vendoring anything, verify license and current AutoHotkey v2 compatibility.

Candidates to inspect:

- `marius-sucan/AHK-GDIp-Library-Compilation`
- `mmikeww/AHKv2-Gdip`
- `buliasz/AHKv2-Gdip`

Radial menu references are useful for ideas but should not drive the architecture directly:

- `dmtr99/Radial_Menu_V2`
- `pa-0/radialmenu-ah2`
- `dumbeau/AutoHotPie`

Implementation preference:

- Vendor only a drawing library if needed.
- Build the hotwheel geometry and interaction model locally.

## Technical Approach

Likely approach:

- Use an always-on-top borderless GUI near the cursor.
- Use a layered window/GDI+ for per-pixel alpha if practical.
- Fall back to a plain GUI if layered rendering slows the first implementation.
- Draw fan sectors with GDI+ paths/pies/arcs.
- Hit-test in polar coordinates:
  - cursor position relative to fan center
  - angle selects slice
  - radius selects ring/zone
- Keep the existing menu path untouched until hotwheel behavior is proven.

## Cancellation Rules

- Releasing the held hotkey leaves the hotwheel open.
- Escape cancels.
- Any unrelated key input cancels.
- Left-click on valid target selects and closes.
- Left-click on invalid/empty target closes without action.
- Right-click anywhere closes without action.
- Losing focus should close the hotwheel.

## Persistence

Usage metadata should be stored separately from `pastemenu.txt`.

Recommended storage:

- `DataRootDir\usage.ini` or a simple text/JSON-like file.
- Do not embed usage metadata inside the snippet file.

Data needed:

- last successful paste:
  - category
  - title
  - timestamp
- usage scores:
  - category/title key
  - decayed score
  - last used timestamp

## Validation Checklist

- Quick tap opens the root menu.
- Hold opens the hotwheel.
- Tap/hold threshold is configurable.
- Release detection works on the actual trigger mouse.
- Releasing the hotkey does not close the hotwheel.
- Hotwheel opens near cursor without covering it awkwardly.
- Hotwheel renders correctly at 100%, 150%, and 200% display scaling.
- Fan direction is sensible near screen edges.
- Hover highlight tracks the correct slice.
- Left-click on last-used paste works.
- Left-click on most-used paste works.
- Last-used and most-used do not show the same entry in both hub slots.
- Usage ranking decays and can be overtaken.
- Settings hub action opens Settings.
- Category hover expands entries.
- Entry click pastes into the original target.
- Stats update only after successful paste.
- Escape cancels.
- Unrelated key input cancels.
- Right-click closes without pasting.
- Normal root menu behavior is unchanged.
