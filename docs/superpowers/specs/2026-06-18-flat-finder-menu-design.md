# Flat Finder Menu Design

## Goal

Add a Windows-style Finder context menu layout where enabled and currently available actions appear directly in the first-level right-click menu. This flat layout is the new default.

## Requirements

- Keep the existing grouped layout available as an optional mode.
- Default new installs and missing configs to the flat layout.
- In flat layout, favorite actions appear first, sorted by localized title.
- If there are both favorites and non-favorite actions, keep favorites first but render all flat items continuously without a separator.
- Do not duplicate favorite actions in the non-favorite list.
- Non-favorite actions appear in the current category order, preserving each category's localized-title sort.
- Disabled, unavailable, or uninstalled-dependent actions remain hidden exactly as they are today.
- High-risk actions remain disabled by default and only appear after the user enables them.
- The setting is shared through the existing config channel and refreshes FinderSync through the existing `configChanged` notification.

## Architecture

Introduce a small pure menu-layout module in `Sources/RightClickAssistant/Core/MenuLayout.swift`.

The module owns:

- `MenuLayoutMode`: `flat` and `grouped`, with `flat` as the default.
- `FinderMenuLayoutBuilder`: a pure builder that receives registered `MenuAction` values plus closures for enabled, favorite, and availability checks.
- `FinderMenuLayoutSection`: a renderer-neutral plan: direct items, submenus, and optional separators for future layouts.

`FinderSync.menu(for:)` will ask the builder for a plan, then render `NSMenuItem`s from that plan. The existing `makeMenuItem(for:)` stays responsible for assigning tags, targets, icons, and selectors.

`SharedStorageManager` stores the mode under a new key, `menu_layout_mode`, and exposes `menuLayoutMode`. `ActionConfigCache` caches the mode alongside favorites and enabled states so the right-click hot path stays memory-backed.

## UI

Add a segmented picker in the Actions settings page:

- `直接显示`
- `分类显示`

Changing the picker writes `SharedStorageManager.shared.menuLayoutMode`, posts `configChanged`, and shows a short HUD.

## Testing

Add focused tests for the pure builder and storage defaults:

- Missing config defaults to `.flat`.
- Flat layout puts favorites first, keeps items continuous, and omits duplicates.
- Grouped layout preserves category submenus.
- Disabled/unavailable actions are excluded by the injected closures.

`swift test` currently fails in this local environment while compiling the package manifest due to a `PackageDescription` link error, so verification may be blocked before tests execute unless the local SwiftPM toolchain is repaired.
