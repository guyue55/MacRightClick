#!/bin/bash

# ==============================================================================
# 开源右键助手 (RightClickAssistant) 自动化编译与打包脚本
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

# 2. 动态写入主 App 的 Info.plist
echo "📝 [Build] 生成主程序的 Info.plist..."
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>org.antigravity.RightClickAssistant</string>
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
    <string>org.antigravity.RightClickAssistant.Extension</string>
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

# 4. 编译主程序二进制可执行文件
echo "🛠️ [Build] 编译宿主主程序 (Swift/SwiftUI)..."
swiftc -Onone -parse-as-library -sdk $(xcrun --show-sdk-path) \
    -vfsoverlay "$BUILD_DIR/overlay.yaml" \
    -target arm64-apple-macosx14.0 \
    RightClickAssistant/AppDelegate.swift \
    RightClickAssistant/Views/ContentView.swift \
    RightClickAssistant/Core/MenuAction.swift \
    RightClickAssistant/Core/ActionDispatcher.swift \
    RightClickAssistant/Core/Actions/NewFileAction.swift \
    RightClickAssistant/Core/Actions/FileManageAction.swift \
    RightClickAssistant/Core/Actions/TerminalOpenAction.swift \
    RightClickAssistant/Core/Actions/UtilityAction.swift \
    -o "$APP_BUNDLE/Contents/MacOS/RightClickAssistant"

# 5. 编译 Finder Sync 插件二进制可执行文件
echo "🛠️ [Build] 编译 Finder Sync 扩展插件..."
swiftc -Onone -parse-as-library -sdk $(xcrun --show-sdk-path) \
    -vfsoverlay "$BUILD_DIR/overlay.yaml" \
    -target arm64-apple-macosx14.0 \
    RightClickAssistantExtension/FinderSync.swift \
    RightClickAssistant/Core/MenuAction.swift \
    RightClickAssistant/Core/ActionDispatcher.swift \
    RightClickAssistant/Core/Actions/NewFileAction.swift \
    RightClickAssistant/Core/Actions/FileManageAction.swift \
    RightClickAssistant/Core/Actions/TerminalOpenAction.swift \
    RightClickAssistant/Core/Actions/UtilityAction.swift \
    -o "$EXT_BUNDLE/Contents/MacOS/RightClickAssistantExtension"

# 6. 对生成的程序和扩展进行临时本地签名（Ad-Hoc Signing），以满足 macOS 运行与沙盒通信要求
echo "🔐 [Build] 自动进行本地临时签名 (Ad-Hoc Codesign)..."
codesign --force --sign - "$EXT_BUNDLE/Contents/MacOS/RightClickAssistantExtension"
codesign --force --sign - "$APP_BUNDLE/Contents/MacOS/RightClickAssistant"

# 7. 打包压缩为 Distribution 压缩包
echo "📦 [Build] 打包压缩为 distributable .zip 包..."
cd "$BUILD_DIR"
zip -r -q "RightClickAssistant.zip" "$APP_NAME.app"
cd ..

echo "=============================================================================="
echo "🎉 [Build] 成功！应用已成功编译并打包。"
echo "📍 编译生成文件路径: $APP_BUNDLE"
echo "📦 分发 Zip 包路径: $BUILD_DIR/RightClickAssistant.zip"
echo "=============================================================================="
