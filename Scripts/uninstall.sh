#!/bin/bash

# ==============================================================================
# 开源右键助手 (RightClickAssistant) 彻底物理卸载与旧进程清理工具
# ==============================================================================
set -e

echo "🧹 [Uninstall] 开始执行系统级高合规彻底物理卸载与内存清理..."

# 1. 物理注销和反注册所有的 FinderSync 插件 (包括旧 org.antigravity 和新 guyue)
echo "🔌 [Uninstall] 1. 反注册和卸载系统中的 FinderSync 插件..."
pluginkit -r guyue.RightClickAssistant.Extension 2>/dev/null || true
pluginkit -r org.antigravity.RightClickAssistant.Extension 2>/dev/null || true
pluginkit -r "/Applications/RightClickAssistant.app/Contents/PlugIns/RightClickAssistantExtension.appex" 2>/dev/null || true
pluginkit -r "build/RightClickAssistant.app/Contents/PlugIns/RightClickAssistantExtension.appex" 2>/dev/null || true

# 2. 强力停用和终止常驻保活的主宿主 App 进程
echo "🛑 [Uninstall] 2. 终止常驻保活的主程序进程..."
killall RightClickAssistant 2>/dev/null || true

# 3. 物理删除主 App 部署包
echo "🗑️ [Uninstall] 3. 物理清除 /Applications 目录下的主程序..."
rm -rf "/Applications/RightClickAssistant.app"

# 4. 清理多进程穿透残留的沙盒中介目录 (保持系统一尘不染)
echo "📂 [Uninstall] 4. 清除多进程沙盒穿透残留的物理中介缓存..."
rm -rf "$HOME/Library/Containers/org.antigravity.RightClickAssistant.Extension/Data" 2>/dev/null || true
rm -rf "$HOME/Library/Containers/guyue.RightClickAssistant.Extension/Data" 2>/dev/null || true

# 5. 强制热重启访达 (Finder)，彻底释放内存中的插件 XPC 常驻会话并进行物理刷新
echo "🔄 [Uninstall] 5. 强制热重启访达进程以完全清空缓存..."
killall Finder 2>/dev/null || true

echo "=============================================================================="
echo "🟢 [Uninstall] 物理卸载与内存清理完美成功！您的电脑已一尘不染。"
echo "=============================================================================="
