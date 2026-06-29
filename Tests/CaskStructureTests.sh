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

users_prefix="/""Users/"
if grep -q "$users_prefix" "$README_ZH" "$README_EN"; then
  fail "README 不应包含开发者本机绝对路径"
fi

echo "✅ Cask 结构校验通过"
