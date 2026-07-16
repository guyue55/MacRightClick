#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASK_FILE="$ROOT_DIR/Casks/rightclickassistant.rb"
README_ZH="$ROOT_DIR/README.md"
README_EN="$ROOT_DIR/README_EN.md"
VALIDATOR_FILE="$ROOT_DIR/Scripts/validate_cask.sh"
QUARANTINE_COMMAND='sudo /usr/bin/xattr -dr com.apple.quarantine "/Applications/RightClickAssistant.app"'

fail() {
  echo "❌ $1" >&2
  exit 1
}

[[ -f "$CASK_FILE" ]] || fail "缺少 Cask 文件: $CASK_FILE"

grep -q 'cask "rightclickassistant"' "$CASK_FILE" || fail "Cask token 必须是 rightclickassistant"
grep -q 'version "1.2.1"' "$CASK_FILE" || fail "Cask 必须使用明确版本"
grep -q 'sha256 "9230f3db5684f537a00c15141e6dac746092ea4fef59e2ab37538d64dba46e37"' "$CASK_FILE" || fail "Cask 必须校验稳定制品"
grep -q 'download/v#{version}/RightClickAssistant-v#{version}-macOS-Universal.dmg' "$CASK_FILE" || fail "Cask URL 必须不可变"
grep -q 'livecheck do' "$CASK_FILE" || fail "Cask 必须提供版本检查策略"
grep -q 'app "RightClickAssistant.app"' "$CASK_FILE" || fail "Cask 必须安装 RightClickAssistant.app"
grep -q 'depends_on macos: :ventura' "$CASK_FILE" || fail "Cask 必须使用当前语法声明 macOS 13+"
grep -q 'Library/Services/RightClickAssistantQuickActions.service' "$CASK_FILE" || fail "Cask 卸载时必须清理动态服务"
grep -q 'NSUpdateDynamicServices' "$CASK_FILE" || fail "Cask 卸载后必须刷新系统服务缓存"
grep -q 'caveats <<~EOS' "$CASK_FILE" || fail "Cask 必须在安装后说明社区签名状态"
grep -q 'Ad-hoc signed, not notarized community build' "$CASK_FILE" || fail "Cask 必须披露 Ad-hoc 与未公证状态"
grep -Fq "$QUARANTINE_COMMAND" "$CASK_FILE" || fail "Cask 安装后提示必须提供精确的 quarantine 移除命令"
grep -Fq 'rm -rf "$(brew --caskroom)/rightclickassistant"' "$CASK_FILE" || fail "Cask 必须提供 v1.2.0 升级故障恢复命令"

if grep -q 'version :latest\|sha256 :no_check' "$CASK_FILE"; then
  fail "Cask 必须使用明确版本和真实 SHA-256"
fi

if grep -q 'depends_on macos: "' "$CASK_FILE"; then
  fail "Cask 不应使用已弃用的 macOS 字符串比较语法"
fi

if grep -q 'curl .*|.*sh' "$CASK_FILE"; then
  fail "Cask 不允许执行远程安装脚本"
fi

if grep -Eq 'system_command "/usr/bin/pluginkit"|executable: "/usr/bin/pluginkit"' "$CASK_FILE"; then
  fail "Cask 卸载不应依赖可能使升级中断的 FinderSync 注销命令"
fi

grep -q 'brew tap guyue55/macrightclick https://github.com/guyue55/MacRightClick.git' "$README_ZH" || fail "中文 README 缺少当前可用的 brew tap 命令"
grep -q 'brew install --cask guyue55/macrightclick/rightclickassistant' "$README_ZH" || fail "中文 README 缺少最小信任范围的 brew 安装命令"
grep -q 'brew trust --cask guyue55/macrightclick/rightclickassistant' "$README_ZH" || fail "中文 README 缺少 Homebrew 6 信任修复命令"
grep -q 'brew upgrade --cask guyue55/macrightclick/rightclickassistant' "$README_ZH" || fail "中文 README 缺少完整限定的升级命令"
grep -Fq "$QUARANTINE_COMMAND" "$README_ZH" || fail "中文 README 缺少可直接执行的 quarantine 移除命令"
grep -Fq 'rm -rf "$(brew --caskroom)/rightclickassistant"' "$README_ZH" || fail "中文 README 缺少 v1.2.0 升级故障恢复命令"
grep -q 'brew tap guyue55/macrightclick https://github.com/guyue55/MacRightClick.git' "$README_EN" || fail "英文 README 缺少当前可用的 brew tap 命令"
grep -q 'brew install --cask guyue55/macrightclick/rightclickassistant' "$README_EN" || fail "英文 README 缺少最小信任范围的 brew 安装命令"
grep -q 'brew trust --cask guyue55/macrightclick/rightclickassistant' "$README_EN" || fail "英文 README 缺少 Homebrew 6 信任修复命令"
grep -q 'brew upgrade --cask guyue55/macrightclick/rightclickassistant' "$README_EN" || fail "英文 README 缺少完整限定的升级命令"
grep -Fq "$QUARANTINE_COMMAND" "$README_EN" || fail "英文 README 缺少可直接执行的 quarantine 移除命令"
grep -Fq 'rm -rf "$(brew --caskroom)/rightclickassistant"' "$README_EN" || fail "英文 README 缺少 v1.2.0 升级故障恢复命令"

grep -Fq 'brew audit --cask --strict --online "$TAP_NAME/rightclickassistant"' "$VALIDATOR_FILE" || fail "Cask 验证器必须使用 Homebrew 6 支持的完整限定名称执行 audit"

users_prefix="/""Users/"
if grep -q "$users_prefix" "$README_ZH" "$README_EN"; then
  fail "README 不应包含开发者本机绝对路径"
fi

echo "✅ Cask 结构校验通过"
