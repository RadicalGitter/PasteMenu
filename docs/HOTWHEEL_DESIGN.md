# Hotwheel Selector Design

## Goal

Add a fast visual selector for frequent paste actions without replacing the existing root menu. The current menu remains the dependable fallback and full editor/settings surface. The hotwheel is optimized for quick, repeated paste selection.

## Concept

Pressing a dedicated hotkey, or holding the existing hotkey, opens a fan-shaped selector near the cursor.

The fan is not a full circle. It should align in an available cardinal direction so it can avoid screen edges more naturally than a radial menu. Corner cases can be handled later; the first version can use a simple best-fit direction.

## Invocation

Open questions:

- Dedicated second hotkey, or press-and-hold on the existing hotkey?
- If press-and-hold is used, what hold threshold feels right? A starting point is 250-350 ms.
- Should a quick tap of the original hotkey keep opening the current menu?

Recommended first implementation:

- Keep the existing hotkey as-is.
- Add an optional second hotkey for the hotwheel.
- Consider press-and-hold after the hotwheel behavior is stable.

Reasoning: press-and-hold is attractive, but it adds timing ambiguity to the app's most important interaction.

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

Open questions:

- Should "most-used paste" be all-time usage, recent usage, or a decaying score?
- Should "last used paste" update only after successful paste, or after menu selection even if paste target fails?
- Should the center labels show category + title, or title only?

## Outer Fan

Outside the center zone, the fan displays categories.

Category behavior:

- Categories are arranged automatically into equal-size slices.
- Moving the mouse over a category highlights that slice.
- Hovering a category expands it into entry slices for that category.
- Clicking an entry pastes it and closes the hotwheel.
- The hotwheel does not expose add/edit/delete actions.

Entry fan behavior:

- Entry slices should appear inside or just beyond the selected category slice.
- Entry labels should be readable and clipped gracefully.
- If a category has too many entries, v1 can show the first N and leave overflow for the normal menu/editor.

Open questions:

- How many category slices should be allowed before the fan becomes too dense?
- Should category order follow the snippet file order, usage frequency, or a hybrid?
- Should entry order follow snippet order, usage frequency, or recent use?
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
