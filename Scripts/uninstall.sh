#!/bin/bash

# ==============================================================================
# 开源右键助手 (RightClickAssistant) 卸载与旧进程清理工具
# ==============================================================================
set -e

echo "🧹 [Uninstall] 开始卸载右键助手并清理旧进程..."

# 1. 物理注销和反注册所有的 FinderSync 插件 (包括旧 org.antigravity 和新 guyue)
echo "🔌 [Uninstall] 1. 反注册和卸载系统中的 FinderSync 插件..."
pluginkit -r guyue.RightClickAssistant.Extension 2>/dev/null || true
pluginkit -r org.antigravity.RightClickAssistant.Extension 2>/dev/null || true
pluginkit -r "/Applications/RightClickAssistant.app/Contents/PlugIns/RightClickAssistantExtension.appex" 2>/dev/null || true
pluginkit -r "build/RightClickAssistant.app/Contents/PlugIns/RightClickAssistantExtension.appex" 2>/dev/null || true

# 2. 终止常驻的主宿主 App 进程
echo "🛑 [Uninstall] 2. 终止常驻保活的主程序进程..."
killall RightClickAssistant 2>/dev/null || true

# 3. 删除动态系统服务，避免卸载后保留失效菜单
echo "🧩 [Uninstall] 3. 清除动态系统服务..."
rm -rf "$HOME/Library/Services/RightClickAssistantQuickActions.service"
/usr/bin/osascript -l JavaScript \
  -e 'ObjC.import("AppKit"); $.NSUpdateDynamicServices();' 2>/dev/null || true

# 4. 删除主 App 部署包
echo "🗑️ [Uninstall] 4. 清除 /Applications 目录下的主程序..."
rm -rf "/Applications/RightClickAssistant.app"

# 5. 清理共享中介目录
echo "📂 [Uninstall] 5. 清除共享中介缓存..."
rm -rf "$HOME/Library/Containers/org.antigravity.RightClickAssistant.Extension/Data" 2>/dev/null || true
rm -rf "$HOME/Library/Containers/guyue.RightClickAssistant.Extension/Data" 2>/dev/null || true

# 6. 重启访达 (Finder)，释放扩展 XPC 会话
echo "🔄 [Uninstall] 6. 重启访达进程以释放扩展缓存..."
killall Finder 2>/dev/null || true

echo "=============================================================================="
echo "🟢 [Uninstall] 卸载与缓存清理完成。"
echo "=============================================================================="
