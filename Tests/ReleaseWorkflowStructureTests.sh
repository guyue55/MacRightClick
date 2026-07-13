#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW_FILE="$ROOT_DIR/.github/workflows/ci.yml"

fail() {
  echo "❌ $1" >&2
  exit 1
}

[[ -f "$WORKFLOW_FILE" ]] || fail "缺少发布工作流: $WORKFLOW_FILE"

grep -q 'name: Ad-hoc Community Tag Release' "$WORKFLOW_FILE" || fail "标签任务必须明确标识为 Ad-hoc 社区发布"
grep -q 'DISTRIBUTION_ROUTE: website-dev' "$WORKFLOW_FILE" || fail "社区发布必须使用 website-dev 路线"
grep -q 'Signature=adhoc' "$WORKFLOW_FILE" || fail "社区发布必须验证 Ad-hoc 签名"
grep -q 'lipo -archs' "$WORKFLOW_FILE" || fail "标签任务必须验证 Universal 2 架构"
grep -q 'RightClickAssistant-v\${VERSION}-macOS-Universal.dmg' "$WORKFLOW_FILE" || fail "缺少不可变版本 DMG"
grep -q 'RightClickAssistant-Latest.dmg' "$WORKFLOW_FILE" || fail "缺少 Latest DMG 便利资产"
grep -q 'SHA256SUMS' "$WORKFLOW_FILE" || fail "社区发布必须附带 SHA-256 清单"
grep -q 'Ad-hoc / Not notarized' "$WORKFLOW_FILE" || fail "Release 说明必须显式披露未公证状态"
grep -q -- '--verify-tag' "$WORKFLOW_FILE" || fail "GitHub Release 必须绑定已验证标签"
grep -q -- '--latest' "$WORKFLOW_FILE" || fail "稳定标签发布必须标记为 GitHub Latest"
grep -q 'actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd' "$WORKFLOW_FILE" || fail "checkout 必须锁定到 Node 24 稳定版"
grep -q 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a' "$WORKFLOW_FILE" || fail "upload-artifact 必须锁定到 Node 24 稳定版"

if grep -q -- '--clobber' "$WORKFLOW_FILE"; then
  fail "已发布的版本资产不应被原地覆盖"
fi

if grep -q 'secrets\.DEVELOPER_ID_APPLICATION' "$WORKFLOW_FILE"; then
  fail "当前社区发布不应强制依赖付费 Developer ID Secret"
fi

if grep -q 'FORCE_JAVASCRIPT_ACTIONS_TO_NODE24' "$WORKFLOW_FILE"; then
  fail "GitHub Actions 应原生使用 Node 24，不应依赖强制兼容开关"
fi

echo "✅ 社区发布工作流结构校验通过"
