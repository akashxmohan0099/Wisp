#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/dist"
EXECUTABLE_NAME="Wisp"
APP_DISPLAY_NAME="Wisp"
APP_BUNDLE_ID="local.wisp"
APP_DIR="${BUILD_DIR}/${APP_DISPLAY_NAME}.app"
EXECUTABLE="${ROOT_DIR}/.build/release/${EXECUTABLE_NAME}"
RESOURCE_BUNDLE="${ROOT_DIR}/.build/release/${EXECUTABLE_NAME}_${EXECUTABLE_NAME}.bundle"

rm -rf "${APP_DIR}" "${BUILD_DIR}/Cursor Dictate.app" "${BUILD_DIR}/Wisp New.app" "${BUILD_DIR}/Wisp.app"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cd "${ROOT_DIR}"
swift build -c release

cp "${EXECUTABLE}" "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}"

swift support/generate_icon.swift
iconutil -c icns "${ROOT_DIR}/support/WispIcon.iconset" -o "${APP_DIR}/Contents/Resources/WispIcon.icns"

if [[ -d "${RESOURCE_BUNDLE}" ]]; then
  cp -R "${RESOURCE_BUNDLE}" "${APP_DIR}/Contents/Resources/"
fi

cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${APP_BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundleName</key>
  <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>WispIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Wisp records audio locally to transcribe speech on-device.</string>
</dict>
</plist>
EOF

# Strip the linker-embedded signature on the inner executable before re-signing
# the whole bundle ad-hoc. Without this, codesign keeps the linker's identifier
# ("Wisp") on the Mach-O and TCC won't key permissions off the bundle id.
codesign --remove-signature "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}" 2>/dev/null || true
codesign --force --deep --sign - --identifier "${APP_BUNDLE_ID}" "${APP_DIR}"

echo "Built app bundle at: ${APP_DIR}"
