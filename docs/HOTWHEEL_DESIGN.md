# Hotwheel Selector Design

## Goal

Add a fast visual selector for frequent paste actions without replacing the existing root menu. The current menu remains the dependable fallback and full editor/settings surface. The hotwheel is optimized for quick, repeated paste selection.

## Concept

Holding the existing hotkey opens a fan-shaped selector near the cursor. A quick tap keeps opening the current root menu.

The fan is not a full circle. It should align in an available cardinal direction so it can avoid screen edges more naturally than a radial menu. Corner cases can be handled later; the first version can use a simple best-fit direction.

## Invocation

Chosen first implementation:

- Quick tap of the configured hotkey opens the current root menu.
- Press-and-hold of the configured hotkey opens the hotwheel.
- Initial hold threshold: 50 ms.
- Add a setting for the hold threshold so this can be tuned if 50 ms is too eager.

Reasoning:

- The hotwheel should feel immediate.
- The existing root menu remains available through a quick tap.
- A setting gives an escape hatch if keyboard repeat timing or mouse-button behavior differs by device.

## Placement

The fan should appear so the cursor starts near the interaction center, not at an outer edge.

Initial placement heuristic:

- Treat the hotwheel as a semicircle or fan sector with a base.
- Put the cursor around the central lower control area, roughly one fifth of the fan diameter above the flat side of the semicircle.
- Choose fan direction based on available screen space:
  - prefer upward fan if there is room above the cursor
  - otherwise use downward, rightward, or leftward fan
  - ignore complex corner optimization in v1

Suggested sizing:

- Center zone diameter: 96-112 px.
- Outer fan radius: 260-340 px depending on category count.
- Minimum category slice angle/width should preserve readable labels.
- Use fixed pixel defaults first; relative scaling can come later after it feels good.
- Hovered category slice can balloon to roughly three fifths of the total fan width/arc to create room for entries.

## Center Zone

The center zone is the high-confidence area for the most common actions.

Suggested layout:

- Center: last used paste.
- Left of center: most-used paste.
- Right of center: settings.

Behavior:

- Hover highlights an item.
- Left-click activates the highlighted item.
- Releasing the hotkey cancels if nothing has been clicked.
- Any other key input cancels.
- Clicking settings opens Settings and closes the hotwheel.
- Clicking a paste item pastes and closes the hotwheel.
- Clicking an unavailable/empty item closes the hotwheel without pasting.

Usage scoring:

- "Most-used paste" should use recent decaying usage, not pure all-time count.
- Default scoring window: last 2 hours.
- More recent usage should matter more than older usage.
- The leader should be easy to overtake; one item should not stay dominant just because it was used many times earlier.
- Keep all-time usage available as a possible future option, but do not use it as the default.

Proposed scoring heuristic:

- Store each paste use as count + last-used timestamp.
- For ranking, compute a decayed score from recent events.
- Start with an exponential decay half-life around 30 minutes inside a 2-hour lookback.
- A paste used recently once or twice should be able to overtake an older leader.

Open questions:

- Should "last used paste" update only after successful paste, or after menu selection even if paste target fails?
- Should the center labels show category + title, or title only?

## Outer Fan

Outside the center zone, the fan displays categories.

Category behavior:

- Categories are arranged automatically into equal-size slices.
- Category order follows file/editor order.
- Moving the mouse over a category highlights that slice.
- Hovering a category expands/balloons that category to roughly three fifths of the fan, then shows entries inside that larger area.
- Clicking an entry pastes it and closes the hotwheel.
- The hotwheel does not expose add/edit/delete actions.

Entry fan behavior:

- Entry slices should appear inside or just beyond the selected category slice.
- Entry order follows file/editor order.
- Entry labels should be readable and clipped gracefully.
- If a category has too many entries, v1 can show the first N and leave overflow for the normal menu/editor.

Open questions:

- How many category slices should be allowed before the fan becomes too dense?
- How should empty categories appear, if at all?

## Visual Style

Target feel:

- quiet, fast, and purposeful
- no decorative effects that slow recognition
- clear hover state
- readable labels
- stable geometry while moving the mouse

Suggested style:

- subtle translucent background
- category slices with restrained color variation
- strong highlight on hovered slice
- center actions visually distinct from category slices
- avoid animation until the interaction model is correct

## Data Needed

To support last-used and most-used paste:

- Track last successful paste:
  - category
  - title
  - timestamp
- Track usage counts:
  - category/title key
  - count
  - last used timestamp
- Persist this separately from `pastemenu.txt`, probably in `settings.ini` or a small usage metadata file under `DataRootDir`.

Recommended storage:

- Use a separate `usage.ini` or `usage.json`-like text file under `DataRootDir`.
- Do not embed usage metadata inside `pastemenu.txt`.

## Implementation Notes

Likely module split:

- `includes/ui_hotwheel.ahk`
  - window construction
  - drawing
  - hit testing
  - interaction lifecycle
- `includes/core_usage_stats.ahk`
  - last-used and most-used tracking
  - persistence

Likely technical approach:

- Use an always-on-top borderless GUI near the cursor.
- Draw fan sectors manually or with GDI+ if needed.
- Start with coarse rectangular/polygon hit regions if that is simpler.
- Keep the existing menu path untouched until hotwheel behavior is proven.

## Cancellation Rules

- Releasing the held hotkey cancels if press-and-hold invocation is used.
- Escape cancels.
- Any unrelated key input cancels.
- Left-click on valid target selects and closes.
- Left-click on invalid/empty target closes without action.
- Losing focus should close the hotwheel.

## Validation Checklist

- Opens near cursor without covering the cursor awkwardly.
- Picks a sensible fan direction near screen edges.
- Hover highlight tracks the correct slice.
- Click on last-used paste works.
- Click on most-used paste works.
- Click on settings opens Settings.
- Category hover expands entries.
- Entry click pastes into the original target.
- Escape cancels.
- Unrelated key input cancels.
- Normal root menu behavior is unchanged.
