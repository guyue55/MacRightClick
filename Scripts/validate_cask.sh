#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASK_FILE="${1:-$ROOT_DIR/Casks/rightclickassistant.rb}"

if [[ ! -f "$CASK_FILE" ]]; then
    echo "❌ Cask 文件不存在: $CASK_FILE" >&2
    exit 1
fi

echo "🔎 [Cask] 检查 Ruby 语法..."
ruby -c "$CASK_FILE"

echo "🔎 [Cask] 检查项目结构约束..."
bash "$ROOT_DIR/Tests/CaskStructureTests.sh"

if [[ "${CASK_VERIFY_DOWNLOAD:-1}" == "1" ]]; then
    VERSION_VALUE="$(sed -nE 's/^  version "([^"]+)"/\1/p' "$CASK_FILE")"
    EXPECTED_SHA="$(sed -nE 's/^  sha256 "([0-9a-f]{64})"/\1/p' "$CASK_FILE")"
    [[ -n "$VERSION_VALUE" && -n "$EXPECTED_SHA" ]] || {
        echo "❌ [Cask] 无法解析版本或 SHA-256" >&2
        exit 1
    }

    DOWNLOAD_URL="https://github.com/guyue55/MacRightClick/releases/download/v${VERSION_VALUE}/RightClickAssistant-v${VERSION_VALUE}-macOS-Universal.dmg"
    TEMP_DMG="$(mktemp -t rightclickassistant-cask).dmg"
    trap 'rm -f "$TEMP_DMG"' EXIT
    echo "🌐 [Cask] 下载不可变制品并核对 SHA-256..."
    curl --fail --location --retry 3 --silent --show-error "$DOWNLOAD_URL" --output "$TEMP_DMG"
    ACTUAL_SHA="$(LC_ALL=C LANG=C shasum -a 256 "$TEMP_DMG" | awk '{print $1}')"
    if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
        echo "❌ [Cask] 制品 SHA-256 不匹配：$ACTUAL_SHA" >&2
        exit 1
    fi
    echo "✅ [Cask] 远程制品 SHA-256 已验证"
fi

if command -v brew >/dev/null 2>&1; then
    TAP_NAME="${HOMEBREW_TAP_NAME:-guyue55/macrightclick}"
    TAP_REPO="$(brew --repo "$TAP_NAME" 2>/dev/null || true)"

    if [[ -n "$TAP_REPO" && "$CASK_FILE" == "$TAP_REPO/"* ]]; then
        echo "🍺 [Cask] Cask 位于 Homebrew tap 中，运行 brew style..."
        brew style --cask "$CASK_FILE"

        echo "🍺 [Cask] 运行 brew audit..."
        brew audit --cask --strict --online "$TAP_NAME/rightclickassistant"
    else
        echo "⚠️ [Cask] Homebrew 要求 style/audit 的 Cask 位于 tap 中。"
        echo "⚠️ [Cask] 当前路径不是 $TAP_NAME tap，已跳过 brew style/audit。"
        echo "⚠️ [Cask] 可在发布后运行: brew tap $TAP_NAME https://github.com/guyue55/MacRightClick.git"
    fi
else
    echo "⚠️ [Cask] 未检测到 Homebrew，已跳过 brew style/audit。"
fi

echo "✅ [Cask] 校验完成"
