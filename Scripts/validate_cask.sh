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

if command -v brew >/dev/null 2>&1; then
    TAP_NAME="${HOMEBREW_TAP_NAME:-guyue55/macrightclick}"
    TAP_REPO="$(brew --repo "$TAP_NAME" 2>/dev/null || true)"

    if [[ -n "$TAP_REPO" && "$CASK_FILE" == "$TAP_REPO/"* ]]; then
        echo "🍺 [Cask] Cask 位于 Homebrew tap 中，运行 brew style..."
        brew style --cask "$CASK_FILE"

        echo "🍺 [Cask] 运行 brew audit..."
        brew audit --cask --strict --online "$CASK_FILE"
    else
        echo "⚠️ [Cask] Homebrew 要求 style/audit 的 Cask 位于 tap 中。"
        echo "⚠️ [Cask] 当前路径不是 $TAP_NAME tap，已跳过 brew style/audit。"
        echo "⚠️ [Cask] 可在发布后运行: brew tap $TAP_NAME https://github.com/guyue55/MacRightClick.git"
    fi
else
    echo "⚠️ [Cask] 未检测到 Homebrew，已跳过 brew style/audit。"
fi

echo "✅ [Cask] 校验完成"
