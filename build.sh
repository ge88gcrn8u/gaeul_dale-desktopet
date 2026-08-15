#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="SquirrelPet"
BUNDLE_NAME="Dal-E.app"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$BUNDLE_NAME"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

INSTALL_TO_APPS="${1:-}"   # pass --install to copy to /Applications

echo "🔨 Building 🐿️ Dal-E..."

# ── Clean ──
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# ── Compile ──
echo "   Compiling…"
cd "$PROJECT_DIR"
swiftc -framework AppKit -framework SpriteKit -framework ServiceManagement -O \
    -target arm64-apple-macos12.0 \
    -o "$MACOS_DIR/$APP_NAME" \
    main.swift AppDelegate.swift PetWindow.swift PetView.swift \
    SquirrelNode.swift AnimationManager.swift LoginItemManager.swift \
    Reminder.swift ReminderStore.swift ReminderScheduler.swift \
    EncouragementDialogue.swift ReminderUI.swift \
    DalEStyle.swift ReminderNotifications.swift \
    ChatWindow.swift ReminderGardenWindow.swift

# ── Info.plist → binary format ──
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
plutil -convert binary1 "$APP_BUNDLE/Contents/Info.plist"

# ── PkgInfo (required for APPL bundles) ──
echo -n 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# ── Squirrel sprite ──
if [ -f "$PROJECT_DIR/squirrel.png" ]; then
    cp "$PROJECT_DIR/squirrel.png" "$RESOURCES_DIR/squirrel.png"
    echo "   ✅ squirrel.png"
else
    echo "   ⚠️  squirrel.png not found — place it in project root"
fi

# ── Left-eye eyelid overlay (blink) ──
if [ -f "$PROJECT_DIR/eyelid.png" ]; then
    cp "$PROJECT_DIR/eyelid.png" "$RESOURCES_DIR/eyelid.png"
    echo "   ✅ eyelid.png"
else
    echo "   ⚠️  eyelid.png not found — skipping left-eye blink overlay"
fi

# ── App Icon (.icns) ──
if [ -f "$PROJECT_DIR/AppIcon.png" ]; then
    echo "   Generating AppIcon.icns…"
    ICONSET="$BUILD_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET"
    SRC="$PROJECT_DIR/AppIcon.png"
    sips -z 16   16   "$SRC" --out "$ICONSET/icon_16x16.png"        > /dev/null 2>&1
    sips -z 32   32   "$SRC" --out "$ICONSET/icon_16x16@2x.png"     > /dev/null 2>&1
    sips -z 32   32   "$SRC" --out "$ICONSET/icon_32x32.png"        > /dev/null 2>&1
    sips -z 64   64   "$SRC" --out "$ICONSET/icon_32x32@2x.png"     > /dev/null 2>&1
    sips -z 128  128  "$SRC" --out "$ICONSET/icon_128x128.png"      > /dev/null 2>&1
    sips -z 256  256  "$SRC" --out "$ICONSET/icon_128x128@2x.png"   > /dev/null 2>&1
    sips -z 256  256  "$SRC" --out "$ICONSET/icon_256x256.png"      > /dev/null 2>&1
    sips -z 512  512  "$SRC" --out "$ICONSET/icon_256x256@2x.png"   > /dev/null 2>&1
    sips -z 512  512  "$SRC" --out "$ICONSET/icon_512x512.png"      > /dev/null 2>&1
    sips -z 1024 1024 "$SRC" --out "$ICONSET/icon_512x512@2x.png"   > /dev/null 2>&1
    iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/AppIcon.icns" 2>/dev/null
    rm -rf "$ICONSET"
    echo "   ✅ AppIcon.icns"
else
    echo "   ⚠️  AppIcon.png not found — skipping icon"
fi

chmod +x "$MACOS_DIR/$APP_NAME"

# ── Clean extended attributes & ad-hoc sign ──
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

# ── Install to /Applications ──
APPS_TARGET="/Applications/$BUNDLE_NAME"
if [ "$INSTALL_TO_APPS" = "--install" ] || [ "$INSTALL_TO_APPS" = "-i" ]; then
    echo ""
    echo "📦 Installing to /Applications…"
    if [ -d "$APPS_TARGET" ]; then
        rm -rf "$APPS_TARGET"
    fi
    cp -R "$APP_BUNDLE" "$APPS_TARGET"
    echo "   ✅ Installed to $APPS_TARGET"
    echo "   ℹ️  图标将在几秒后出现在启动台 (Launchpad)"
fi

# ── Launch ──
echo ""
echo "🚀 Launching…"
pkill -f "$APP_NAME" 2>/dev/null || true
sleep 0.3
open "$APP_BUNDLE" 2>/dev/null || "$MACOS_DIR/$APP_NAME" &
sleep 1

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🐿️  Dal-E is ready!"
echo "  App  : $APP_BUNDLE"
[ "$INSTALL_TO_APPS" = "--install" ] || [ "$INSTALL_TO_APPS" = "-i" ] && echo "  已安装: $APPS_TARGET"
echo ""
echo "  右键松鼠 → 菜单"
echo "  拖拽松鼠 → 移动"
echo "  点击松鼠 → 互动"
echo ""
echo "  安装到启动台: bash build.sh --install"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
