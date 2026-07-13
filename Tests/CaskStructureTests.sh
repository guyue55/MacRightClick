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
grep -q 'version "1.1.1"' "$CASK_FILE" || fail "Cask 必须使用明确版本"
grep -q 'sha256 "6c548dc44b675f0c3d650c1c9179c861b3dbd19817adbc222f488a216cc8776a"' "$CASK_FILE" || fail "Cask 必须校验稳定制品"
grep -q 'download/v#{version}/RightClickAssistant-v#{version}-macOS-Universal.dmg' "$CASK_FILE" || fail "Cask URL 必须不可变"
grep -q 'livecheck do' "$CASK_FILE" || fail "Cask 必须提供版本检查策略"
grep -q 'app "RightClickAssistant.app"' "$CASK_FILE" || fail "Cask 必须安装 RightClickAssistant.app"
grep -q 'depends_on macos: ">= :ventura"' "$CASK_FILE" || fail "Cask 必须声明 macOS 13+"
grep -q '/usr/bin/pluginkit' "$CASK_FILE" || fail "Cask 卸载时必须反注册 FinderSync 扩展"
grep -q 'guyue.RightClickAssistant.Extension' "$CASK_FILE" || fail "Cask 必须包含 FinderSync 扩展 bundle id"
grep -q 'caveats <<~EOS' "$CASK_FILE" || fail "Cask 必须在安装后说明社区签名状态"
grep -q 'Ad-hoc signed, not notarized community build' "$CASK_FILE" || fail "Cask 必须披露 Ad-hoc 与未公证状态"

if grep -q 'version :latest\|sha256 :no_check' "$CASK_FILE"; then
  fail "Cask 必须使用明确版本和真实 SHA-256"
fi

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
