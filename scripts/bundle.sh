#!/bin/bash
# release 빌드 후 build/Symboard.app 번들을 만든다.
set -euo pipefail
cd "$(dirname "$0")/.."

# 버전은 Sources/SymboardCore/Version.swift 한 곳에만 둔다. 빌드 번호는 커밋 수(늘기만 한다).
VERSION="$(sed -nE 's/.*version = "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' Sources/SymboardCore/Version.swift)"
if [ -z "$VERSION" ]; then echo "Version.swift 에서 버전을 읽지 못했다" >&2; exit 1; fi
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP=build/Symboard.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Symboard" "$APP/Contents/MacOS/Symboard"
# claude 콘솔이 보드에 콘솔을 띄우는 stdio MCP 서버(8차).
cp "$BIN_DIR/symboard-mcp" "$APP/Contents/MacOS/symboard-mcp"
# SwiftPM 리소스 번들(있으면)도 같이 넣는다.
for b in "$BIN_DIR"/*.bundle; do
  [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Symboard</string>
  <key>CFBundleDisplayName</key><string>Symboard</string>
  <key>CFBundleIdentifier</key><string>local.symboard.app</string>
  <key>CFBundleExecutable</key><string>Symboard</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

# 서명: Developer ID 인증서가 키체인에 있으면 그걸로, 없으면 임시(ad-hoc) 서명.
# 안쪽 실행 파일부터 서명하고 마지막에 앱 전체를 서명한다.
ID="${SIGN_IDENTITY:-Developer ID Application: jikwon seo (K6599UJ4KM)}"
if security find-identity -v -p codesigning | grep -qF "$ID"; then
  codesign --force --options runtime --timestamp --sign "$ID" "$APP/Contents/MacOS/symboard-mcp"
  codesign --force --options runtime --timestamp --sign "$ID" "$APP"
  codesign --verify --strict --deep "$APP"
  SIGNED_WITH_ID=1
else
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
  SIGNED_WITH_ID=0
fi
echo "built $APP ($VERSION, build $BUILD)"

# 공증: NOTARIZE=1 일 때만 (몇 분 걸림). 다른 맥에서 경고 없이 열리게 하려면 필요하다.
# 계정 정보는 미리 `xcrun notarytool store-credentials symboard-notary ...` 로 저장해 둔다.
if [ "${NOTARIZE:-0}" = 1 ]; then
  if [ "$SIGNED_WITH_ID" != 1 ]; then echo "Developer ID 서명이 없어 공증할 수 없다" >&2; exit 1; fi
  ZIP=build/Symboard.zip
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "${NOTARY_PROFILE:-symboard-notary}" --wait
  xcrun stapler staple "$APP"
  # 배포용 zip 은 공증 결과를 붙인 뒤 다시 만든다.
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl -a -vv "$APP"
  echo "notarized $ZIP"
fi
