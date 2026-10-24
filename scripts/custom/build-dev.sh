#!/bin/bash
set -euo pipefail

# tian-custom: generate tian-dev.xcodeproj from project.dev.yml and build the
# Debug configuration as tian-dev.app. Nothing is installed: the app stays in
# .build/dev, so the release tian in /Applications is never touched.
#
# Usage:
#   scripts/custom/build-dev.sh          # build
#   scripts/custom/build-dev.sh --open   # build, then launch tian-dev

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../.."

OPEN=false
for arg in "$@"; do
    case "$arg" in
        --open) OPEN=true ;;
        *) echo "Usage: $0 [--open]" >&2; exit 1 ;;
    esac
done

if [ ! -d tian/Vendor/GhosttyKit.xcframework ]; then
    echo "Error: tian/Vendor/GhosttyKit.xcframework is missing. Run scripts/custom/build-ghostty.sh first." >&2
    exit 1
fi

echo "==> xcodegen generate --spec project.dev.yml"
xcodegen generate --spec project.dev.yml

echo "==> xcodebuild tian-dev (Debug)"
xcodebuild \
  -project tian-dev.xcodeproj \
  -scheme tian \
  -configuration Debug \
  -derivedDataPath .build/dev \
  build

APP="$PWD/.build/dev/Build/Products/Debug/tian-dev.app"

# The ".debug" suffix is what keeps tian-dev's socket, state and logs apart
# from the release app. Refuse to hand out an app that would share them.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
case "$BUNDLE_ID" in
    *.debug) ;;
    *) echo "Error: $APP has bundle id $BUNDLE_ID; expected a .debug id. Not safe to run next to tian." >&2; exit 1 ;;
esac

echo ""
echo "Built $APP ($BUNDLE_ID)"
if [ "$OPEN" = true ]; then
    open "$APP"
fi
