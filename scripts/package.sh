#!/bin/zsh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "===> 步驟 1: 編譯可執行檔..."
./scripts/build.sh

APP_DIR="build/LosslessStudio.app"
BUILDING_APP="build/staging_app/LosslessStudio.app"
CONTENTS="$BUILDING_APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

echo "===> 步驟 2: 建立 .app Bundle 結構..."
rm -rf "build/staging_app"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"

cp build/LosslessStudio "$MACOS/LosslessStudio"
chmod +x "$MACOS/LosslessStudio"

cp Resources/Info.plist "$CONTENTS/Info.plist"
cp Resources/AppIcon.icns "$RESOURCES/AppIcon.icns"
cp Resources/LICENSE-FFMPEG.txt "$RESOURCES/LICENSE-FFMPEG.txt"
[ -f Resources/LICENSE-IMAGEMAGICK.txt ] && cp Resources/LICENSE-IMAGEMAGICK.txt "$RESOURCES/LICENSE-IMAGEMAGICK.txt"
[ -f Resources/LICENSE-THIRD-PARTY.txt ] && cp Resources/LICENSE-THIRD-PARTY.txt "$RESOURCES/LICENSE-THIRD-PARTY.txt"
cp Resources/使用說明與安裝指南.txt "$RESOURCES/使用說明與安裝指南.txt"
cp Resources/USER_GUIDE.md "$RESOURCES/USER_GUIDE.md"
echo "APPL????" > "$CONTENTS/PkgInfo"

echo "===> 步驟 2.1: 內嵌 FFmpeg 與 ffprobe 二進位..."
if [ -f "/opt/homebrew/bin/ffmpeg" ]; then
    cp /opt/homebrew/bin/ffmpeg "$RESOURCES/ffmpeg"
    chmod +x "$RESOURCES/ffmpeg"
fi
if [ -f "/opt/homebrew/bin/ffprobe" ]; then
    cp /opt/homebrew/bin/ffprobe "$RESOURCES/ffprobe"
    chmod +x "$RESOURCES/ffprobe"
fi

echo "===> 步驟 2.1.1: 內嵌可攜式 ImageMagick 與專用 Frameworks..."
if [ -d "$PROJECT_DIR/embedded/ImageMagick" ]; then
    cp -R "$PROJECT_DIR/embedded/ImageMagick" "$CONTENTS/ImageMagick"
    chmod -R 755 "$CONTENTS/ImageMagick"
fi
if [ -d "$PROJECT_DIR/embedded/Frameworks" ]; then
    cp -R "$PROJECT_DIR/embedded/Frameworks/"* "$FRAMEWORKS/"
    chmod -R 755 "$FRAMEWORKS/"
fi

echo "===> 步驟 2.2: 遞迴打包所有動態庫至 Frameworks 並重寫載入路徑 (@rpath)..."
python3 "$PROJECT_DIR/scripts/bundle_dependencies.py" "$BUILDING_APP"

# 確保 ImageMagick 內部 unversioned symlink 標的完整存在以通過 strict deep codesign
ln -sf libMagickCore-7.Q16HDRI.11.dylib "$FRAMEWORKS/libMagickCore-7.Q16HDRI.dylib"
ln -sf libMagickWand-7.Q16HDRI.11.dylib "$FRAMEWORKS/libMagickWand-7.Q16HDRI.dylib"
ln -sf libMagick++-7.Q16HDRI.5.dylib "$FRAMEWORKS/libMagick++-7.Q16HDRI.dylib"

[ -d Resources/licenses ] && cp -R Resources/licenses "$RESOURCES/licenses"

echo "===> 步驟 3: 執行安全 Ad-Hoc 程式碼簽章 (遵循系統安全限制)..."
codesign --force --deep --sign - "$BUILDING_APP"
codesign --verify --deep --strict --verbose=2 "$BUILDING_APP"

echo "===> 步驟 3.1: 固化驗收副本與原子更新 build/LosslessStudio.app..."
mkdir -p build/releases
rm -rf build/releases/LosslessStudio-v1.0.2.app
cp -R "$BUILDING_APP" build/releases/LosslessStudio-v1.0.2.app

rm -rf "$APP_DIR"
cp -R "$BUILDING_APP" "$APP_DIR"
rm -rf "build/staging_app"

if [ "$NO_INSTALL" != "1" ] && [ "$1" != "--no-install" ]; then
    echo "===> 步驟 4: 安裝至本機 /Applications 及 ~/Applications..."
    rm -rf "/Applications/LosslessStudio.app"
    cp -R "$APP_DIR" "/Applications/LosslessStudio.app"

    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/LosslessStudio.app"
    cp -R "$APP_DIR" "$HOME/Applications/LosslessStudio.app"
else
    echo "===> 步驟 4: 跳過安裝至本機 /Applications（依據指令保護現行環境）..."
fi

echo "===> 步驟 5: 打包產出 Zip 發布檔..."
mkdir -p dist
rm -f dist/LosslessStudio-macOS.zip
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" dist/LosslessStudio-macOS.zip

echo "===> 步驟 6: 準備 DMG 散布結構 (含 Applications 捷徑與授權指南)..."
DMG_STAGING="/tmp/LosslessStudio_dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

cp -R "$APP_DIR" "$DMG_STAGING/LosslessStudio.app"
ln -s /Applications "$DMG_STAGING/Applications"
cp Resources/使用說明與安裝指南.txt "$DMG_STAGING/使用說明與安裝指南.txt"
cp Resources/USER_GUIDE.md "$DMG_STAGING/完整功能說明手冊.md"
cp Resources/LICENSE-FFMPEG.txt "$DMG_STAGING/LICENSE-FFMPEG.txt"
[ -f Resources/LICENSE-IMAGEMAGICK.txt ] && cp Resources/LICENSE-IMAGEMAGICK.txt "$DMG_STAGING/LICENSE-IMAGEMAGICK.txt"
[ -f Resources/LICENSE-THIRD-PARTY.txt ] && cp Resources/LICENSE-THIRD-PARTY.txt "$DMG_STAGING/LICENSE-THIRD-PARTY.txt"
[ -d Resources/licenses ] && cp -R Resources/licenses "$DMG_STAGING/licenses"

rm -f dist/LosslessStudio.dmg /tmp/LosslessStudio.dmg
hdiutil create -volname "LosslessStudio" -srcfolder "$DMG_STAGING" -ov -format UDZO dist/LosslessStudio.dmg
rm -rf "$DMG_STAGING"

echo "===> 步驟 7: 驗證 DMG 完整性..."
hdiutil verify dist/LosslessStudio.dmg

echo "===> 步驟 8: 執行發行前隱私與機密外洩強制稽核 (Privacy & Security Gate)..."
python3 "$PROJECT_DIR/scripts/verify_privacy_and_security.py"

echo "===> 打包與安裝全部完成！"
echo "  - 應用程式: /Applications/LosslessStudio.app"
echo "  - 使用者應用程式: $HOME/Applications/LosslessStudio.app"
echo "  - Zip 發行檔: $PROJECT_DIR/dist/LosslessStudio-macOS.zip ($(du -h dist/LosslessStudio-macOS.zip | cut -f1))"
echo "  - DMG 發行檔: $PROJECT_DIR/dist/LosslessStudio.dmg ($(du -h dist/LosslessStudio.dmg | cut -f1))"
