# Changelog

All notable changes to PasteMenu will be documented in this file.

This project follows the structure of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Version numbers are provisional until the first tagged release, but entries should be grouped as if the project follows semantic versioning.

## [Unreleased]

### Added

- Added per-LLM-call example linking backed by `llm_example_links.tsv`.
- Added an `Examples...` manager in the LLM call editor for linking normal paste entries as examples for a specific LLM prompt.
- Added a configurable LLM example preface so linked examples can be framed as style/structure examples.
- Added Anthropic model/pricing cache support, including pricing refresh, model refresh, stale-pricing notice, and estimated request cost display.
- Added document-context capture for LLM calls from Word and PDF windows, with a pending-document indicator beside the root menu.
- Added deferred Word extraction via COM with markdown-style conversion for headings, lists, links, tables, and inserted-image placeholders.
- Added PDF text extraction via clipboard fallback when sending an LLM call.
- Added browser-hosted PDF detection for common browsers when the window title includes a `.pdf` filename.
- Added local `file:///...pdf` extraction for browser PDF tabs by resolving the address bar URL and converting the local PDF through Word when available.
- Added optional `pdftotext.exe` extraction for local browser PDF tabs, detected from the browser address bar and run only when sending an LLM request.
- Bundled `pdftotext.exe` from Xpdf tools with GPL license/source notes and build-copy support into `dist/tools`.
- Added the response budget suffix: `Your full response must fit within <max_tokens - 5> tokens.`

### Changed

- Moved LLM examples out of the normal entry editor and into per-call links from the LLM editor.
- Deferred Word COM binding from menu-open time to LLM-send time to reduce root menu latency.
- Changed PDF clipboard fallback to reject copied PDF URLs as document text.
- Changed PDF LLM payload resolution to prefer highlighted text before full-document extraction.
- Disabled PDF text normalization in the active send path; the helper remains available for later refinement.
- Changed root menu invocation to snapshot active window, focused control, cursor, and mouse position before the tap/hold delay and before dropdown menus open.
- Removed owner-drawn bolding from the normal entry/category listboxes now that examples are no longer global entry flags.
- Changed LLM prompt construction to include only examples linked to the selected LLM call.
- Changed the LLM settings model field from a plain edit box to a model combo populated from cached/fetched model IDs.
- Renamed the LLM example storage path from `llm_examples.tsv` to `llm_example_links.tsv`.
- Renamed the active project progress tracker from `docs/PROJECT_PROGRESS.md` to `docs/HOTWHEEL_PROGRESS.md`.

### Fixed

- Fixed cramped vertical spacing in the normal entry editor by removing custom owner-drawn listbox row handling.
- Fixed the LLM editor delete button label to read `Delete` because it applies to both categories and entries.
- Fixed the LLM editor `Examples...` button width so it aligns with the surrounding action buttons.
- Fixed Ctrl+Backspace in editor fields inserting a raw delete glyph by swallowing the follow-up `WM_CHAR(127)`.

## [0.3.0] - 2026-05-28

### Added

- Added preliminary Anthropic-only LLM calls from the root menu.
- Added an LLM call editor for prompt categories and prompt entries.
- Added Anthropic request execution, response window, copy/paste actions, cancellation, and response logging.
- Added `apikey.ini` creation/lookup support for storing the Anthropic API key outside committed source.
- Added selected-text capture for LLM calls with clipboard sentinels and API-key leak protection.
- Added root-local `llmlogs/LLMresponselog.md` response logging.
- Added GDI+ fan-rendering groundwork for the hotwheel selector.
- Added error logging support.

### Changed

- Kept LLM support provider-shaped internally while exposing only Anthropic in the UI.
- Changed build bootstrap behavior to create missing local support files needed by LLM calls.
- Updated hotwheel rendering work toward the fan design instead of the temporary rectangular panel.

### Fixed

- Fixed LLM API-key lookup when running from `dist/` by searching the project root first.
- Fixed menu-opening latency introduced by eager selected-text capture by moving expensive clipboard reads to the actual LLM action.
- Fixed unsafe clipboard fallback behavior that could treat `apikey.ini` contents as selected text.

## [0.2.0] - 2026-05-25

### Added

- Added hotwheel backend scaffolding behind the existing hotkey.
- Added successful-paste usage tracking with recent decayed scoring.
- Added tap-versus-hold hotkey dispatch where tap opens the root menu and hold opens the hotwheel.
- Added configurable hotwheel hold threshold in Settings.
- Added hotwheel geometry helpers for DPI scaling, fan placement, slice layout, and hit testing.
- Added hotwheel state/view-model helpers for center actions, categories, entries, hover state, and click outcomes.
- Added a plain prototype renderer and input lifecycle for hover, click, Escape, right-click, and cancellation behavior.
- Added automated smoke-check coverage for the new hotwheel include modules.

### Changed

- Kept paste execution outside the hotwheel renderer so the renderer can be replaced without rewriting behavior.
- Documented the need to harden lifecycle and rendering before visual polish.

## [0.1.0] - 2026-05-22

### Added

- Promoted the modular AutoHotkey v2 codebase to `main`.
- Added project structure for storage, snippet backup, runtime context menu, hotkeys, settings, editor, script runner, and paste markup modules.
- Added build output conventions for `dist/` and `build/`.
- Added project documentation, behavior parity notes, smoke checklist, and contribution guidance.
- Added script-runner settings improvements and clearer script-related settings UI.

### Changed

- Archived the old single-file script on `legacy-single-file-obsolete`.
- Organized roadmap material into dedicated project and hotwheel planning documents.
