# Flat Finder Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Finder context menu default to a flat Windows-style layout while keeping the current grouped layout available.

**Architecture:** Add a pure `MenuLayout` core module that turns actions and config predicates into renderer-neutral sections. FinderSync renders those sections into `NSMenuItem`s, while `SharedStorageManager` and `ActionConfigCache` own shared persistence and hot-path caching.

**Tech Stack:** Swift 6, AppKit FinderSync, SwiftUI settings, XCTest.

---

### Task 1: Add Pure Menu Layout Tests

**Files:**
- Modify: `Tests/RightClickAssistantTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests for default flat mode, flat favorite-first ordering, grouped compatibility, and filtering.

- [ ] **Step 2: Run tests**

Run: `swift test --filter RightClickAssistantTests`

Expected in a healthy toolchain: tests fail because `MenuLayoutMode`, `FinderMenuLayoutBuilder`, and storage accessors do not exist.

### Task 2: Implement Menu Layout Core

**Files:**
- Create: `Sources/RightClickAssistant/Core/MenuLayout.swift`
- Modify: `Sources/RightClickAssistant/Core/SharedStorageManager.swift`
- Modify: `Sources/RightClickAssistant/Core/ActionConfigCache.swift`
- Modify: `Package.swift` only if needed by SwiftPM auto-discovery; expected no change.
- Modify: `Scripts/build.sh`

- [ ] **Step 1: Add `MenuLayoutMode`, `FinderMenuLayoutSection`, and `FinderMenuLayoutBuilder`**

The builder must output flat direct items with favorites first, grouped submenus for compatibility, and no duplicate favorite actions.

- [ ] **Step 2: Add shared storage and cache support**

Add `SharedStorageManager.Keys.menuLayoutMode`, `menuLayoutMode`, and `ActionConfigCache.menuLayoutMode`.

- [ ] **Step 3: Include the new file in manual build source lists**

Add `Sources/RightClickAssistant/Core/MenuLayout.swift` to both `HOST_SOURCES` and `EXT_SOURCES` in `Scripts/build.sh`.

### Task 3: Render Layout Plan In FinderSync

**Files:**
- Modify: `Sources/RightClickAssistantExtension/FinderSync.swift`

- [ ] **Step 1: Replace hard-coded menu construction with builder plan rendering**

Use `ActionConfigCache.shared.menuLayoutMode`, enabled/favorite cache checks, and each action's availability check.

- [ ] **Step 2: Keep `makeMenuItem(for:)` as the single item factory**

Render `.directItems` as first-level items, `.submenu` as child menus, and keep `.separator` support only for layouts that explicitly request it.

### Task 4: Add Settings UI

**Files:**
- Modify: `Sources/RightClickAssistant/Views/ContentView.swift`

- [ ] **Step 1: Add segmented picker to `ActionsHubView`**

Expose `直接显示` and `分类显示`, load from `SharedStorageManager.shared.menuLayoutMode`, save on change, post `configChanged`, and show a HUD.

- [ ] **Step 2: Refresh UI on appear**

Ensure the picker reflects changes persisted from previous launches.

### Task 5: Verify

**Files:**
- Test: `Tests/RightClickAssistantTests.swift`

- [ ] **Step 1: Run `swift test --filter RightClickAssistantTests`**

Expected in a healthy toolchain: PASS.

- [ ] **Step 2: Run `swift test`**

Expected in a healthy toolchain: PASS. In the current local environment this may fail before test execution with the known `PackageDescription` manifest link error.

- [ ] **Step 3: Optional app build**

Run: `./Scripts/build.sh`

Expected: app, extension, verifier, zip, and dmg are produced under `build/`.

## Self-Review

- Spec coverage: flat default, grouped compatibility, favorite handling, filtering, settings, cache, and build script inclusion are covered.
- Placeholder scan: no TBD or open-ended implementation gaps remain.
- Type consistency: names match the intended Swift symbols: `MenuLayoutMode`, `FinderMenuLayoutSection`, `FinderMenuLayoutBuilder`, `menuLayoutMode`.
