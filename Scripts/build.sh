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
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
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
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
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
    Sources/RightClickAssistant/Core/Actions/NewFileAction.swift \
    Sources/RightClickAssistant/Core/Actions/FileManageAction.swift \
    Sources/RightClickAssistant/Core/Actions/TerminalOpenAction.swift \
    Sources/RightClickAssistant/Core/Actions/UtilityAction.swift
"

SDK_PATH=$(xcrun --show-sdk-path)
COMMON_FLAGS="-Onone -parse-as-library -sdk $SDK_PATH -vfsoverlay $BUILD_DIR/overlay.yaml"

# 6. 编译宿主主程序 (arm64 与 x86_64)
echo "🛠️ [Build] 编译宿主主程序 (arm64)..."
swiftc $COMMON_FLAGS -target arm64-apple-macosx14.0 $HOST_SOURCES -o "$BUILD_DIR/RightClickAssistant_arm64"

echo "🛠️ [Build] 编译宿主主程序 (x86_64)..."
swiftc $COMMON_FLAGS -target x86_64-apple-macosx14.0 $HOST_SOURCES -o "$BUILD_DIR/RightClickAssistant_x86_64"

echo "🔗 [Build] 使用 lipo 创建宿主主程序的 Universal 胖二进制文件..."
lipo -create -output "$APP_BUNDLE/Contents/MacOS/RightClickAssistant" "$BUILD_DIR/RightClickAssistant_arm64" "$BUILD_DIR/RightClickAssistant_x86_64"


# 7. 编译 Finder Sync 插件 (arm64 与 x86_64)
echo "🛠️ [Build] 编译 Finder Sync 扩展插件 (arm64)..."
swiftc $COMMON_FLAGS -target arm64-apple-macosx14.0 $EXT_SOURCES -o "$BUILD_DIR/RightClickAssistantExtension_arm64"

echo "🛠️ [Build] 编译 Finder Sync 扩展插件 (x86_64)..."
swiftc $COMMON_FLAGS -target x86_64-apple-macosx14.0 $EXT_SOURCES -o "$BUILD_DIR/RightClickAssistantExtension_x86_64"

echo "🔗 [Build] 使用 lipo 创建扩展插件的 Universal 胖二进制文件..."
lipo -create -output "$EXT_BUNDLE/Contents/MacOS/RightClickAssistantExtension" "$BUILD_DIR/RightClickAssistantExtension_arm64" "$BUILD_DIR/RightClickAssistantExtension_x86_64"


# 8. 编译 ActionVerifier 工具 (arm64 与 x86_64)
echo "🛠️ [Build] 编译 ActionVerifier 校验程序 (arm64)..."
swiftc -Onone -parse-as-library -sdk $SDK_PATH -vfsoverlay "$BUILD_DIR/overlay.yaml" -target arm64-apple-macosx14.0 Sources/ActionVerifier/ActionVerifier.swift -o "$BUILD_DIR/ActionVerifier_arm64"

echo "🛠️ [Build] 编译 ActionVerifier 校验程序 (x86_64)..."
swiftc -Onone -parse-as-library -sdk $SDK_PATH -vfsoverlay "$BUILD_DIR/overlay.yaml" -target x86_64-apple-macosx14.0 Sources/ActionVerifier/ActionVerifier.swift -o "$BUILD_DIR/ActionVerifier_x86_64"

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

# 10. 打包压缩为 Distribution 压缩包
echo "📦 [Build] 打包压缩为 distributable .zip 包..."
cd "$BUILD_DIR"
zip -r -q "RightClickAssistant.zip" "$APP_NAME.app"
cd ..

echo "=============================================================================="
echo "🎉 [Build] 成功！应用与校验工具已成功编译并打包为双架构胖程序。"
echo "📍 宿主应用路径: $APP_BUNDLE"
echo "📦 分发 Zip 包路径: $BUILD_DIR/RightClickAssistant.zip"
echo "🧪 校验程序路径: ./ActionVerifier_bin"
echo "=============================================================================="
