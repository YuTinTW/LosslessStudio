#!/bin/zsh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# Accept the previous no-install flag for existing callers. Packaging never installs.
if [ "${1:-}" = "--no-install" ]; then
    shift
fi
if [ "$#" -ne 0 ]; then
    echo "Usage: $0 [--no-install]" >&2
    exit 2
fi

for executable in /opt/homebrew/bin/ffmpeg /opt/homebrew/bin/ffprobe embedded/ImageMagick/bin/magick; do
    if [ ! -x "$executable" ]; then
        echo "Missing required packaging dependency: $executable" >&2
        exit 1
    fi
done

CANDIDATE_DIR="$PROJECT_DIR/reports/blackmagic-localization"
mkdir -p "$CANDIDATE_DIR"
STAGING="$(mktemp -d "$CANDIDATE_DIR/.candidate.XXXXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
trap 'exit 1' HUP INT TERM
PUBLISH_DIR="$CANDIDATE_DIR/${${STAGING:t}#.}"
BUILDING_APP="$STAGING/LosslessStudio.app"
CONTENTS="$BUILDING_APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
ZIP_PATH="$STAGING/LosslessStudio-macOS.zip"
DMG_PATH="$STAGING/LosslessStudio.dmg"
DMG_STAGING="$STAGING/dmg-contents"

echo "===> 編譯候選程式並建立 App Bundle..."
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"
./scripts/build.sh "$MACOS/LosslessStudio"

cp Resources/Info.plist "$CONTENTS/Info.plist"
cp Resources/AppIcon.icns "$RESOURCES/AppIcon.icns"
cp Resources/LICENSE-FFMPEG.txt "$RESOURCES/LICENSE-FFMPEG.txt"
[ -f Resources/LICENSE-IMAGEMAGICK.txt ] && cp Resources/LICENSE-IMAGEMAGICK.txt "$RESOURCES/LICENSE-IMAGEMAGICK.txt"
[ -f Resources/LICENSE-THIRD-PARTY.txt ] && cp Resources/LICENSE-THIRD-PARTY.txt "$RESOURCES/LICENSE-THIRD-PARTY.txt"
cp Resources/使用說明與安裝指南.txt "$RESOURCES/使用說明與安裝指南.txt"
cp Resources/USER_GUIDE.md "$RESOURCES/USER_GUIDE.md"
cp Resources/INSTALLATION_GUIDE.en.txt Resources/USER_GUIDE.en.md "$RESOURCES/"
echo "APPL????" > "$CONTENTS/PkgInfo"

echo "===> 步驟 2.1: 內嵌 FFmpeg 與 ffprobe 二進位..."
cp /opt/homebrew/bin/ffmpeg /opt/homebrew/bin/ffprobe "$RESOURCES/"
chmod +x "$RESOURCES/ffmpeg" "$RESOURCES/ffprobe"

echo "===> 步驟 2.1.1: 內嵌可攜式 ImageMagick 與專用 Frameworks..."
cp -R "$PROJECT_DIR/embedded/ImageMagick" "$CONTENTS/ImageMagick"
chmod -R 755 "$CONTENTS/ImageMagick"
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

echo "===> 建立 ZIP 與 DMG 候選安裝包..."
ditto -c -k --sequesterRsrc --keepParent "$BUILDING_APP" "$ZIP_PATH"
mkdir -p "$DMG_STAGING"
cp -R "$BUILDING_APP" "$DMG_STAGING/LosslessStudio.app"
ln -s /Applications "$DMG_STAGING/Applications"
cp Resources/使用說明與安裝指南.txt "$DMG_STAGING/使用說明與安裝指南.txt"
cp Resources/USER_GUIDE.md "$DMG_STAGING/完整功能說明手冊.md"
cp Resources/INSTALLATION_GUIDE.en.txt Resources/USER_GUIDE.en.md "$DMG_STAGING/"
cp Resources/LICENSE-FFMPEG.txt "$DMG_STAGING/LICENSE-FFMPEG.txt"
[ -f Resources/LICENSE-IMAGEMAGICK.txt ] && cp Resources/LICENSE-IMAGEMAGICK.txt "$DMG_STAGING/LICENSE-IMAGEMAGICK.txt"
[ -f Resources/LICENSE-THIRD-PARTY.txt ] && cp Resources/LICENSE-THIRD-PARTY.txt "$DMG_STAGING/LICENSE-THIRD-PARTY.txt"
[ -d Resources/licenses ] && cp -R Resources/licenses "$DMG_STAGING/licenses"

hdiutil create -volname "LosslessStudio" -srcfolder "$DMG_STAGING" -format UDZO "$DMG_PATH"
rm -rf "$DMG_STAGING"
hdiutil verify "$DMG_PATH"

echo "===> 稽核候選包隱私與機密資料..."
python3 "$PROJECT_DIR/scripts/verify_privacy_and_security.py" --candidate "$STAGING"

mv "$STAGING" "$PUBLISH_DIR"
trap - EXIT
echo "===> 候選包已通過打包與稽核：$PUBLISH_DIR"
