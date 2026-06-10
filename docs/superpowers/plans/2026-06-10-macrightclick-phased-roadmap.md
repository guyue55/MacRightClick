# MacRightClick Phased Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the five-phase product, safety, UX, diagnostics, and distribution hardening roadmap for the open-source free macOS right-click assistant.

**Architecture:** Keep FinderSync menu rendering thin, route shared state through `SharedStorageManager`, and isolate user-facing safety, diagnostics, and distribution decisions behind small focused APIs. Each phase ends with build/test verification and one Chinese commit.

**Tech Stack:** Swift 6, AppKit, SwiftUI, FinderSync, shell build scripts, GitHub/GitHub Releases documentation.

---

### Task 1: Phase 1 Safety, Logging, And Trust Copy

**Files:**
- Modify: `Sources/RightClickAssistant/AppDelegate.swift`
- Modify: `Sources/RightClickAssistant/Core/SharedStorageManager.swift`
- Modify: `Sources/RightClickAssistantExtension/FinderSync.swift`
- Modify: `Sources/RightClickAssistant/Core/SharedHUDManager.swift`
- Modify: `Sources/RightClickAssistant/Views/ContentView.swift`
- Modify: `README.md`
- Modify: `README_EN.md`
- Modify: `Scripts/uninstall.sh`
- Test: `Tests/RightClickAssistantTests.swift`

- [ ] **Step 1: Write failing tests**
  Add tests that assert high-risk actions are hidden from the tray unless explicitly enabled, debug logging defaults off, and production copy avoids absolute claims.

- [ ] **Step 2: Verify red**
  Run `swift test` if the local toolchain allows it; if SwiftPM is blocked by the known CLT manifest linker issue, run the custom build verifier commands and document the failure.

- [ ] **Step 3: Implement minimal behavior**
  Gate tray hidden-file switching behind the same shared advanced-action toggle, add production/debug log levels to `SharedStorageManager`, reduce noisy FinderSync logs, and rewrite in-app/README/uninstall copy to measured open-source language.

- [ ] **Step 4: Verify green**
  Run `bash -n Scripts/build.sh Scripts/uninstall.sh`, `git diff --check`, `./Scripts/build.sh`, and targeted source scans for banned absolute phrases.

- [ ] **Step 5: Commit**
  Commit with a Chinese message such as `feat: 完成第一阶段安全入口和信任文案收敛`.

### Task 2: Phase 2 Settings Information Architecture

**Files:**
- Modify: `Sources/RightClickAssistant/Views/ContentView.swift`
- Modify: `Sources/RightClickAssistant/Core/MenuAction.swift`
- Modify: `Sources/RightClickAssistant/Core/SharedStorageManager.swift`
- Test: `Tests/RightClickAssistantTests.swift`

- [ ] **Step 1: Write failing tests**
  Add tests for default section membership, advanced grouping, and action state persistence through `SharedStorageManager`.

- [ ] **Step 2: Verify red**
  Run the test or build command and confirm the missing APIs fail.

- [ ] **Step 3: Implement minimal behavior**
  Reorganize settings into Overview, Actions, Permissions, Diagnostics, and Advanced; hide raw action IDs outside diagnostics; add reset defaults, open logs, reveal shared folder, check extension status, and run diagnostics controls.

- [ ] **Step 4: Verify green**
  Run tests/build and inspect the settings source for native concise labels.

- [ ] **Step 5: Commit**
  Commit with a Chinese message such as `feat: 重构设置页信息架构`.

### Task 3: Phase 3 Finder Menu Favorites And Watched Directories

**Files:**
- Modify: `Sources/RightClickAssistantExtension/FinderSync.swift`
- Modify: `Sources/RightClickAssistant/Views/ContentView.swift`
- Modify: `Sources/RightClickAssistant/Core/MenuAction.swift`
- Modify: `Sources/RightClickAssistant/Core/SharedStorageManager.swift`
- Test: `Tests/RightClickAssistantTests.swift`

- [ ] **Step 1: Write failing tests**
  Add tests that defaults expose a small safe action set, favorites persist, and watched directories round-trip without auto-creating `~/GitProject`.

- [ ] **Step 2: Verify red**
  Run the test/build command and confirm missing storage/menu APIs fail.

- [ ] **Step 3: Implement minimal behavior**
  Add favorite action storage, default compact menu rules, and user-configurable watched directories with no implicit project folder creation.

- [ ] **Step 4: Verify green**
  Run tests/build and inspect FinderSync menu rendering paths.

- [ ] **Step 5: Commit**
  Commit with a Chinese message such as `feat: 支持访达菜单收藏和自定义监听目录`.

### Task 4: Phase 4 Reliability And Diagnostics

**Files:**
- Modify: `Sources/RightClickAssistant/Core/Actions/UtilityAction.swift`
- Modify: `Sources/RightClickAssistant/Core/SharedStorageManager.swift`
- Modify: `Sources/RightClickAssistant/Views/ContentView.swift`
- Test: `Tests/RightClickAssistantTests.swift`

- [ ] **Step 1: Write failing tests**
  Add tests for streaming hash output, failed queue quarantine, bounded queue cleanup, and config write locking.

- [ ] **Step 2: Verify red**
  Run the test/build command and confirm missing APIs fail.

- [ ] **Step 3: Implement minimal behavior**
  Stream MD5/SHA256 calculation, preserve malformed or failed queue events in diagnostics storage, serialize config writes, and surface diagnostic counts/status in the UI.

- [ ] **Step 4: Verify green**
  Run tests/build and manually inspect queue behavior with generated malformed JSON.

- [ ] **Step 5: Commit**
  Commit with a Chinese message such as `feat: 增强队列可靠性和诊断能力`.

### Task 5: Phase 5 Mac App Store Architecture Branch

**Files:**
- Modify: `Scripts/build.sh`
- Create: `docs/distribution/mac-app-store-architecture.md`
- Modify: `README.md`
- Modify: `README_EN.md`

- [ ] **Step 1: Write failing checks**
  Add shell checks or documentation scans that require MAS route documentation to mention App Sandbox, formal App Group, and security-scoped bookmarks.

- [ ] **Step 2: Verify red**
  Run the check and confirm missing MAS architecture details fail.

- [ ] **Step 3: Implement minimal behavior**
  Keep website-release as the active route; create a dedicated MAS architecture document and build-script guard explaining the separate branch requirements.

- [ ] **Step 4: Verify green**
  Run `bash -n Scripts/build.sh`, `DISTRIBUTION_ROUTE=mac-app-store ./Scripts/build.sh` expecting the documented guard, and scan docs for the three MAS requirements.

- [ ] **Step 5: Commit**
  Commit with a Chinese message such as `docs: 补充 Mac App Store 架构路线`.

## Completion Review

- Phase 1 is complete only when high-risk tray behavior, production logging, and trust copy are all verified and committed.
- Phase 2 is complete only when the settings UI has the new information architecture and diagnostics controls.
- Phase 3 is complete only when Finder menu density and observed directories are user-controlled.
- Phase 4 is complete only when large-file hashing, failed event handling, locked config writes, and diagnostics are implemented.
- Phase 5 is complete only when the MAS path is explicitly documented as a separate architecture route while website distribution remains shippable.
