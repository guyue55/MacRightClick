#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG_NAME="${TAG_NAME:-}"
VERSION_VALUE="${VERSION_OVERRIDE:-$(tr -d '\r\n' < "$ROOT_DIR/VERSION")}"

fail() {
  echo "❌ [Release] $1" >&2
  exit 1
}

[[ "$VERSION_VALUE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION 必须是稳定语义版本，实际为: $VERSION_VALUE"
[[ "$TAG_NAME" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "TAG_NAME 必须形如 v1.2.0，实际为: ${TAG_NAME:-<empty>}"
[[ "${TAG_NAME#v}" == "$VERSION_VALUE" ]] || fail "标签 $TAG_NAME 与 VERSION $VERSION_VALUE 不一致"

check_plist_version() {
  local plist="$1"
  local label="$2"
  [[ -f "$plist" ]] || return 0
  local artifact_version
  artifact_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
  [[ "$artifact_version" == "$VERSION_VALUE" ]] || fail "$label 版本 $artifact_version 与 VERSION $VERSION_VALUE 不一致"
}

if [[ -z "${VERSION_OVERRIDE:-}" || "${VERIFY_BUILD_ARTIFACTS:-0}" == "1" ]]; then
  check_plist_version "$ROOT_DIR/build/RightClickAssistant.app/Contents/Info.plist" "主程序"
  check_plist_version "$ROOT_DIR/build/RightClickAssistant.app/Contents/PlugIns/RightClickAssistantExtension.appex/Contents/Info.plist" "Finder 扩展"
fi

echo "✅ [Release] 标签、VERSION 与现有构建产物版本一致: $VERSION_VALUE"
