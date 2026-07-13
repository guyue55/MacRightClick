# Homebrew Cask Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users install RightClickAssistant with Homebrew using a maintained Cask file from this repository, while documenting the current local/raw-file flow and the future tap flow clearly.

**Architecture:** Keep Homebrew packaging separate from app runtime code. Add one Cask under `Casks/`, one shell validator under `Tests/`, one optional validation wrapper under `Scripts/`, then update README/README_EN/CHANGELOG. The Cask uses GitHub Releases latest DMG because the current release assets expose `RightClickAssistant-Latest.dmg`.

**Tech Stack:** Homebrew Cask Ruby DSL, bash validation scripts, Markdown docs.

---

### Task 1: Add Cask Structure Test

**Files:**
- Create: `Tests/CaskStructureTests.sh`

- [ ] **Step 1: Write the failing test**

Create a shell test that checks the expected Cask file and the README install command references exist:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASK_FILE="$ROOT_DIR/Casks/rightclickassistant.rb"
README_ZH="$ROOT_DIR/README.md"
README_EN="$ROOT_DIR/README_EN.md"

fail() {
  echo "❌ $1" >&2
  exit 1
}

[[ -f "$CASK_FILE" ]] || fail "缺少 Cask 文件: $CASK_FILE"

grep -q 'cask "rightclickassistant"' "$CASK_FILE" || fail "Cask token 必须是 rightclickassistant"
grep -q 'version :latest' "$CASK_FILE" || fail "当前 Latest DMG 流程必须使用 version :latest"
grep -q 'sha256 :no_check' "$CASK_FILE" || fail "Latest DMG URL 必须使用 sha256 :no_check"
grep -q 'RightClickAssistant-Latest.dmg' "$CASK_FILE" || fail "Cask 必须指向 GitHub Releases latest DMG"
grep -q 'app "RightClickAssistant.app"' "$CASK_FILE" || fail "Cask 必须安装 RightClickAssistant.app"
grep -q 'depends_on macos: ">= :ventura"' "$CASK_FILE" || fail "Cask 必须声明 macOS 13+"

if grep -q 'curl .*|.*sh' "$CASK_FILE"; then
  fail "Cask 不允许执行远程安装脚本"
fi

grep -q 'brew tap guyue55/macrightclick https://github.com/guyue55/MacRightClick.git' "$README_ZH" || fail "中文 README 缺少当前可用的 brew tap 命令"
grep -q 'brew install --cask rightclickassistant' "$README_ZH" || fail "中文 README 缺少当前可用的 brew 安装命令"
grep -q 'brew tap guyue55/macrightclick https://github.com/guyue55/MacRightClick.git' "$README_EN" || fail "英文 README 缺少当前可用的 brew tap 命令"
grep -q 'brew install --cask rightclickassistant' "$README_EN" || fail "英文 README 缺少当前可用的 brew 安装命令"

echo "✅ Cask 结构校验通过"
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash Tests/CaskStructureTests.sh
```

Expected: FAIL because `Casks/rightclickassistant.rb` does not exist yet.

### Task 2: Add Homebrew Cask

**Files:**
- Create: `Casks/rightclickassistant.rb`

- [ ] **Step 1: Add the Cask**

Create a cask with latest-release DMG URL, no automatic scripts, app install target, uninstall quit hints, and zap cleanup for app preferences/containers.

- [ ] **Step 2: Run structure test**

Run:

```bash
bash Tests/CaskStructureTests.sh
```

Expected: still fail until README is updated.

### Task 3: Add Optional Homebrew Validation Wrapper

**Files:**
- Create: `Scripts/validate_cask.sh`

- [ ] **Step 1: Add validator**

Create a script that always runs `ruby -c` and `Tests/CaskStructureTests.sh`; if `brew` exists and the Cask file is already inside the configured Homebrew tap checkout, also run `brew style --cask` and `brew audit --cask --strict --online`. If the current repository is not tapped yet, print the tap command and skip those Homebrew developer checks.

- [ ] **Step 2: Run validator**

Run:

```bash
./Scripts/validate_cask.sh
```

Expected: PASS for local checks; if Homebrew audit has network policy warnings, report them explicitly.

### Task 4: Update Docs

**Files:**
- Modify: `README.md`
- Modify: `README_EN.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Document current install**

Add a Homebrew install section using:

```bash
brew tap guyue55/macrightclick https://github.com/guyue55/MacRightClick.git
brew install --cask guyue55/macrightclick/rightclickassistant
```

For the current Ad-hoc signed and unnotarized community build, document the preferred Gatekeeper UI approval first. If a verified download remains blocked, provide the exact single-app fallback:

```bash
sudo /usr/bin/xattr -dr com.apple.quarantine "/Applications/RightClickAssistant.app"
open "/Applications/RightClickAssistant.app"
```

- [ ] **Step 2: Document future tap command**

Document the recommended future tap shape:

```bash
brew tap guyue55/macrightclick
brew install --cask rightclickassistant
```

Clarify that omitting the tap URL requires publishing a separate `homebrew-macrightclick` tap repository or equivalent standard tap setup.

- [ ] **Step 3: Update changelog**

Add an Unreleased entry for Homebrew Cask packaging.

### Task 5: Verify And Commit

**Files:**
- All changed files

- [ ] **Step 1: Run verification**

Run:

```bash
git diff --check
bash Tests/CaskStructureTests.sh
./Scripts/validate_cask.sh
./Scripts/build.sh
swift test
```

Expected: `git diff --check`, Cask structure test, validator local checks, and build pass. `swift test` may remain blocked by the known local SwiftPM manifest link error; record the exact error if it happens.

- [ ] **Step 2: Commit**

Run:

```bash
git add -A
git commit -m "新增 Homebrew Cask 安装支持"
```
