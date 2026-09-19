#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP="$ROOT/noteアカウントスイッチャー.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
BUILD="$ROOT/.build"
ARM64_BINARY="$BUILD/note-account-switcher-arm64"
X86_64_BINARY="$BUILD/note-account-switcher-x86_64"

rm -rf "$APP"
mkdir -p "$MACOS"
mkdir -p "$BUILD/module-cache/arm64" "$BUILD/module-cache/x86_64"

# Use the SDK selected by the active Xcode / Command Line Tools installation.
# Pinning an SDK version makes the build fail as soon as that SDK is removed.
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"
LIPO="$(xcrun --find lipo)"

CLANG_MODULE_CACHE_PATH="$BUILD/module-cache/arm64" "$SWIFTC" \
  -sdk "$SDK" \
  -target arm64-apple-macosx14.0 \
  -parse-as-library \
  -framework SwiftUI \
  -framework AppKit \
  "$ROOT/NoteAccountSwitcher.swift" \
  "$ROOT/Analytics.swift" \
  "$ROOT/DashboardView.swift" \
  -o "$ARM64_BINARY"

CLANG_MODULE_CACHE_PATH="$BUILD/module-cache/x86_64" "$SWIFTC" \
  -sdk "$SDK" \
  -target x86_64-apple-macosx14.0 \
  -parse-as-library \
  -framework SwiftUI \
  -framework AppKit \
  "$ROOT/NoteAccountSwitcher.swift" \
  "$ROOT/Analytics.swift" \
  "$ROOT/DashboardView.swift" \
  -o "$X86_64_BINARY"

# Combine both native executables into one Universal Binary so the same app
# runs on Apple Silicon and Intel Macs.
"$LIPO" -create \
  "$ARM64_BINARY" \
  "$X86_64_BINARY" \
  -output "$MACOS/note-account-switcher"

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
mkdir -p "$CONTENTS/Resources"
cp "$ROOT/FetchAnalytics.js" "$CONTENTS/Resources/FetchAnalytics.js"
cp "$ROOT/icon.png" "$CONTENTS/Resources/icon.png"
# Keep the bundle launchable even when it is copied through a filesystem or
# archive operation that does not preserve Unix executable permissions.
chmod 755 "$MACOS/note-account-switcher"
# Finder metadata/resource forks invalidate code signatures when copied into
# an app bundle. Remove them before applying the local ad-hoc signature.
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"

echo "Built Universal Binary (arm64 + x86_64): $APP"
