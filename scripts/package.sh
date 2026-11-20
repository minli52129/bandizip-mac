#!/usr/bin/env bash
#
# 构建 macOS 应用包：编译通用二进制 → 组装 .app → 生成图标 → ad-hoc 签名 → DMG / ZIP
# 只在 macOS 上运行（GitHub Actions 的 macos runner 就是为此准备的）。
#
set -euo pipefail

cd "$(dirname "$0")/.."

DIST="dist"
BUILD="build"
APP_NAME="BandizipMac"
APP_BUNDLE="$DIST/$APP_NAME.app"
STAGE="$BUILD/dmg"

# ---------- 版本号 ----------
VERSION="${VERSION:-}"
if [ -z "$VERSION" ]; then
  if git describe --tags --abbrev=0 >/dev/null 2>&1; then
    VERSION="$(git describe --tags --abbrev=0 | sed 's/^v//')"
  else
    VERSION="1.0.0"
  fi
fi
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"

echo "==> 版本 $VERSION (build $BUILD_NUMBER)"

rm -rf "$DIST" "$BUILD"
mkdir -p "$DIST" "$BUILD"

# ---------- 编译 ----------
echo "==> 编译通用二进制（arm64 + x86_64）"
swift build -c release --arch arm64 --arch x86_64

BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path | tail -n 1)"
if [ ! -x "$BIN_DIR/$APP_NAME" ]; then
  for candidate in ".build/apple/Products/Release" ".build/release"; do
    if [ -x "$candidate/$APP_NAME" ]; then
      BIN_DIR="$candidate"
      break
    fi
  done
fi

echo "==> 可执行文件目录：$BIN_DIR"
for product in "$APP_NAME" bz; do
  if [ ! -f "$BIN_DIR/$product" ]; then
    echo "!! 找不到可执行文件 $product" >&2
    ls -la "$BIN_DIR" >&2 || true
    exit 1
  fi
done

# ---------- 组装 .app ----------
echo "==> 组装 $APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$BIN_DIR/bz" "$APP_BUNDLE/Contents/MacOS/bz"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"

plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

# ---------- 图标 ----------
echo "==> 生成图标"
python3 Tools/gen_icon.py "$BUILD/AppIcon.iconset" >/dev/null
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# ---------- 签名 ----------
# 没有开发者证书，用 ad-hoc 签名。首次打开需要「右键 → 打开」。
echo "==> ad-hoc 签名"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE" || true
lipo -info "$APP_BUNDLE/Contents/MacOS/$APP_NAME" || true

# ---------- DMG ----------
echo "==> 制作 DMG"
mkdir -p "$STAGE"
cp -R "$APP_BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Bandizip" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DIST/BandizipMac-$VERSION.dmg" >/dev/null

# ---------- ZIP ----------
echo "==> 制作 ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$DIST/BandizipMac-$VERSION.zip"

(
  cd "$DIST"
  shasum -a 256 ./*.dmg ./*.zip > SHA256SUMS.txt
)

echo "==> 完成"
ls -lh "$DIST"
