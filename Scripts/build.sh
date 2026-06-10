#!/bin/bash

# ==============================================================================
# 开源右键助手 (RightClickAssistant) 自动化编译与打包脚本 (支持 Universal 2)
# ==============================================================================
set -e

echo "🚀 [Build] 开始自动化编译与打包流程..."

# 1. 初始化目录
BUILD_DIR="build"
APP_NAME="RightClickAssistant"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
EXT_BUNDLE="$APP_BUNDLE/Contents/PlugIns/${APP_NAME}Extension.appex"

if [ -f "VERSION" ]; then
    VERSION=$(cat VERSION | tr -d '\n' | tr -d '\r')
else
    VERSION="1.0.0"
fi
echo "🏷️ [Build] 检测到全局版本号: $VERSION"

echo "🧹 [Build] 清理旧编译目录: $BUILD_DIR..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "📝 [Build] 动态创建 VFS Overlay 解决系统底层 SwiftBridging 重定义冲突..."
cat << 'EOF' > "$BUILD_DIR/empty.modulemap"
// 空的 modulemap 文件，用于通过 VFS 覆盖解决系统重定义冲突
EOF

cat << EOF > "$BUILD_DIR/overlay.yaml"
{
  'version': 0,
  'roots': [
    {
      'type': 'directory',
      'name': '/Library/Developer/CommandLineTools/usr/include/swift',
      'contents': [
        {
          'type': 'file',
          'name': 'bridging.modulemap',
          'external-contents': '$(pwd)/$BUILD_DIR/empty.modulemap'
        }
      ]
    }
  ]
}
EOF

echo "📂 [Build] 创建 macOS App Bundle 结构..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$EXT_BUNDLE/Contents/MacOS"
mkdir -p "$EXT_BUNDLE/Contents/Resources"

# 2. 动态写入主 App 的 Info.plist (包含 CFBundleIconFile)
echo "📝 [Build] 生成主程序的 Info.plist..."
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>guyue.RightClickAssistant</string>
    <key>CFBundleName</key>
    <string>RightClickAssistant</string>
    <key>CFBundleDisplayName</key>
    <string>右键助手</string>
    <key>CFBundleExecutable</key>
    <string>RightClickAssistant</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# 3. 动态写入 FinderSync 扩展的 Info.plist
echo "📝 [Build] 生成访达扩展的 Info.plist..."
cat <<EOF > "$EXT_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>guyue.RightClickAssistant.Extension</string>
    <key>CFBundleName</key>
    <string>RightClickAssistantExtension</string>
    <key>CFBundleDisplayName</key>
    <string>右键助手扩展</string>
    <key>CFBundleExecutable</key>
    <string>RightClickAssistantExtension</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.FinderSync</string>
        <key>NSExtensionPrincipalClass</key>
        <string>FinderSync</string>
    </dict>
</dict>
</plist>
EOF

# 4. 转换并打包 AppIcon
if [ -f "Resources/AppIcon.png" ]; then
    echo "🎨 [Build] 检测到 Resources/AppIcon.png，开始转换为系统级 AppIcon.icns..."
    ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    
    # 缩放切图
    sips -z 16 16     "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null 2>&1 || true
    sips -z 32 32     "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null 2>&1 || true
    sips -z 32 32     "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null 2>&1 || true
    sips -z 64 64     "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null 2>&1 || true
    sips -z 128 128   "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null 2>&1 || true
    sips -z 256 256   "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null 2>&1 || true
    sips -z 256 256   "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null 2>&1 || true
    sips -z 512 512   "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null 2>&1 || true
    sips -z 512 512   "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null 2>&1 || true
    sips -z 1024 1024 "Resources/AppIcon.png" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null 2>&1 || true
    
    if command -v iconutil >/dev/null; then
        iconutil -c icns "$ICONSET_DIR" -o "$BUILD_DIR/AppIcon.icns"
        cp "$BUILD_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
        echo "🟢 [Build] 成功合成并注入 AppIcon.icns 至打包！"
    else
        echo "⚠️ [Build] 未找到 iconutil 工具，使用 AppIcon.png 直接降级拷贝..."
        cp "Resources/AppIcon.png" "$APP_BUNDLE/Contents/Resources/AppIcon.png"
    fi
else
    echo "⚠️ [Build] 未找到 Resources/AppIcon.png 资源，跳过图标打包。"
fi

# 5. 源码列表定义
HOST_SOURCES="
    Sources/RightClickAssistant/AppDelegate.swift \
    Sources/RightClickAssistant/Views/ContentView.swift \
    Sources/RightClickAssistant/Core/MenuAction.swift \
    Sources/RightClickAssistant/Core/SharedStorageManager.swift \
    Sources/RightClickAssistant/Core/SharedFolderMonitor.swift \
    Sources/RightClickAssistant/Core/ActionDispatcher.swift \
    Sources/RightClickAssistant/Core/SharedHUDManager.swift \
    Sources/RightClickAssistant/Core/LaunchServiceManager.swift \
    Sources/RightClickAssistant/Core/Actions/NewFileAction.swift \
    Sources/RightClickAssistant/Core/Actions/FileManageAction.swift \
    Sources/RightClickAssistant/Core/Actions/TerminalOpenAction.swift \
    Sources/RightClickAssistant/Core/Actions/UtilityAction.swift
"

EXT_SOURCES="
    Sources/RightClickAssistantExtension/FinderSync.swift \
    Sources/RightClickAssistant/Core/MenuAction.swift \
    Sources/RightClickAssistant/Core/SharedStorageManager.swift \
    Sources/RightClickAssistant/Core/ActionDispatcher.swift \
    Sources/RightClickAssistant/Core/SharedHUDManager.swift \
    Sources/RightClickAssistant/Core/Actions/NewFileAction.swift \
    Sources/RightClickAssistant/Core/Actions/FileManageAction.swift \
    Sources/RightClickAssistant/Core/Actions/TerminalOpenAction.swift \
    Sources/RightClickAssistant/Core/Actions/UtilityAction.swift
"

SDK_PATH=$(xcrun --show-sdk-path)
COMMON_FLAGS="-Onone -parse-as-library -sdk $SDK_PATH -vfsoverlay $BUILD_DIR/overlay.yaml"

# 6. 编译宿主主程序 (arm64 与 x86_64)
echo "🛠️ [Build] 编译宿主主程序 (arm64)..."
swiftc $COMMON_FLAGS -target arm64-apple-macosx13.0 $HOST_SOURCES -o "$BUILD_DIR/RightClickAssistant_arm64"

echo "🛠️ [Build] 编译宿主主程序 (x86_64)..."
swiftc $COMMON_FLAGS -target x86_64-apple-macosx13.0 $HOST_SOURCES -o "$BUILD_DIR/RightClickAssistant_x86_64"

echo "🔗 [Build] 使用 lipo 创建宿主主程序的 Universal 胖二进制文件..."
lipo -create -output "$APP_BUNDLE/Contents/MacOS/RightClickAssistant" "$BUILD_DIR/RightClickAssistant_arm64" "$BUILD_DIR/RightClickAssistant_x86_64"


# 7. 编译 Finder Sync 插件 (arm64 与 x86_64)
echo "🛠️ [Build] 编译 Finder Sync 扩展插件 (arm64)..."
swiftc $COMMON_FLAGS -target arm64-apple-macosx13.0 $EXT_SOURCES -o "$BUILD_DIR/RightClickAssistantExtension_arm64"

echo "🛠️ [Build] 编译 Finder Sync 扩展插件 (x86_64)..."
swiftc $COMMON_FLAGS -target x86_64-apple-macosx13.0 $EXT_SOURCES -o "$BUILD_DIR/RightClickAssistantExtension_x86_64"

echo "🔗 [Build] 使用 lipo 创建扩展插件的 Universal 胖二进制文件..."
lipo -create -output "$EXT_BUNDLE/Contents/MacOS/RightClickAssistantExtension" "$BUILD_DIR/RightClickAssistantExtension_arm64" "$BUILD_DIR/RightClickAssistantExtension_x86_64"


# 8. 编译 ActionVerifier 工具 (arm64 与 x86_64)
echo "🛠️ [Build] 编译 ActionVerifier 校验程序 (arm64)..."
swiftc -Onone -parse-as-library -sdk $SDK_PATH -vfsoverlay "$BUILD_DIR/overlay.yaml" -target arm64-apple-macosx13.0 Sources/ActionVerifier/ActionVerifier.swift -o "$BUILD_DIR/ActionVerifier_arm64"

echo "🛠️ [Build] 编译 ActionVerifier 校验程序 (x86_64)..."
swiftc -Onone -parse-as-library -sdk $SDK_PATH -vfsoverlay "$BUILD_DIR/overlay.yaml" -target x86_64-apple-macosx13.0 Sources/ActionVerifier/ActionVerifier.swift -o "$BUILD_DIR/ActionVerifier_x86_64"

echo "🔗 [Build] 使用 lipo 创建 ActionVerifier 的 Universal 胖二进制文件..."
lipo -create -output "ActionVerifier_bin" "$BUILD_DIR/ActionVerifier_arm64" "$BUILD_DIR/ActionVerifier_x86_64"


# 9. 对生成的程序和扩展进行临时本地签名 (Ad-Hoc Signing)
echo "🔐 [Build] 动态生成 Entitlements 签名配置文件..."
cat <<EOF > "$BUILD_DIR/RightClickAssistantExtension.entitlements"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
</dict>
</plist>
EOF

echo "🔐 [Build] 自动进行嵌套沙盒签名 (Ad-Hoc Nested Codesign)..."
# A. 先签名最内层插件的二进制与整个 XPC 插件 bundle
codesign --force --sign - --entitlements "$BUILD_DIR/RightClickAssistantExtension.entitlements" "$EXT_BUNDLE/Contents/MacOS/RightClickAssistantExtension"
codesign --force --sign - "$EXT_BUNDLE"

# B. 再签名主程序二进制
codesign --force --sign - "$APP_BUNDLE/Contents/MacOS/RightClickAssistant"

# C. 最后整体签名宿主主 App Bundle (至关重要！解决 launchd spawn 162 崩溃)
codesign --force --sign - "$APP_BUNDLE"

# D. 签名自检程序
codesign --force --sign - "ActionVerifier_bin"

# 10. 打包压缩为 Distribution 压缩包与 DMG 磁盘映像
echo "📦 [Build] 正在打包压缩为 distributable .zip 绿色免安装版..."
cd "$BUILD_DIR"
zip -r -q "RightClickAssistant.zip" "$APP_NAME.app"
cd ..

echo "📦 [Build] 开始构建商业级 Drag-to-Install DMG 磁盘映像..."
DMG_TEMP_DIR="$BUILD_DIR/dmg_temp"
rm -rf "$DMG_TEMP_DIR"
mkdir -p "$DMG_TEMP_DIR"

# A. 拷贝 App 以及 Applications 快捷方式
cp -R "$APP_BUNDLE" "$DMG_TEMP_DIR/"
ln -s /Applications "$DMG_TEMP_DIR/Applications"

# B. 创建原始可写 DMG (UDRW 格式)
RAW_DMG="$BUILD_DIR/RightClickAssistant_raw.dmg"
rm -f "$RAW_DMG"
hdiutil create -volname "RightClickAssistant" -srcfolder "$DMG_TEMP_DIR" -ov -format UDRW "$RAW_DMG" >/dev/null

# C. 静默挂载原始 DMG 以便调用 AppleScript 写入 Finder 窗口对称排版元数据
echo "🎨 [Build] 静默挂载临时磁盘映像并启动 Finder 视觉排版排布..."
# 使用 -nobrowse 避免在用户桌面弹出影响体验
device=$(hdiutil attach -nobrowse -readwrite "$RAW_DMG" | egrep '/Volumes/' | awk '{print $1}')
sleep 1.5

# 使用 AppleScript 让 Finder 调整该虚拟盘的布局元数据。添加 Headless 降级保护
osascript <<EOF || echo "⚠️ [Build] 提示: 当前处于 headless 无显示环境，已安全跳过 Finder UI 窗口排版，默认继承系统基础布局。"
tell application "Finder"
    tell disk "RightClickAssistant"
        open
        delay 1
        set containerWindow to container window of disk "RightClickAssistant"
        set current view of containerWindow to icon view
        set toolbar visible of containerWindow to false
        set statusbar visible of containerWindow to false
        -- 设定黄金分辨率大小宽 550, 高 360
        set the bounds of containerWindow to {400, 200, 950, 560}
        set icon size of icon view options of containerWindow to 128
        set arrangement of icon view options of containerWindow to not arranged
        
        -- 对称拖拽排版
        set position of item "RightClickAssistant.app" to {150, 180}
        set position of item "Applications" to {400, 180}
        
        delay 1
        close containerWindow
    end tell
end tell
EOF

sleep 1
hdiutil detach "$device" >/dev/null || true
sleep 1

# D. 转换为正式发布版只读高压缩 DMG (UDZO 格式)
FINAL_DMG="$BUILD_DIR/RightClickAssistant.dmg"
rm -f "$FINAL_DMG"
echo "⚡ [Build] 正在将原始映像转换为只读高压缩分发级 DMG..."
hdiutil convert "$RAW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null

# E. 清理临时过渡资源
rm -f "$RAW_DMG"
rm -rf "$DMG_TEMP_DIR"

echo "=============================================================================="
echo "🎉 [Build] 成功！应用已成功编译并完成双格式打包分发。"
echo "📍 宿主应用路径: $APP_BUNDLE"
echo "📦 绿色免安装版: $BUILD_DIR/RightClickAssistant.zip"
echo "📀 拖拽式安装版: $BUILD_DIR/RightClickAssistant.dmg"
echo "🧪 校验程序路径: ./ActionVerifier_bin"
echo "=============================================================================="
