#!/bin/bash
set -euo pipefail

# tian-custom: build GhosttyKit.xcframework from a pinned Ghostty commit and
# vendor it into the tian project. Fork-local replacement for
# scripts/build-ghostty.sh, which stays untouched so upstream merges stay clean.
#
# Differences from the upstream script:
#   - Pins Ghostty to GHOSTTY_COMMIT instead of cloning HEAD, so the embedding
#     API (ghostty.h) and library name match what this tian version expects.
#   - Builds with the full Xcode toolchain. The upstream script switches to the
#     CommandLineTools SDK, which relies on a locally patched Ghostty checkout
#     (MetallibStep.zig) and lacks the iOS SDK that Ghostty's build graph needs.
#   - Skips the Ghostty.app bundle (-Demit-macos-app=false); tian only needs
#     the xcframework and the resources.
#   - Runs Ghostty's libtool step with the classic Command Line Tools libtool.
#     The ld-based libtool in newer Xcode (seen with 26.6) silently drops
#     archive members that are not 8-byte aligned. Zig emits such members,
#     so libghostty_zcu.o (the entire Ghostty C API) goes missing.
#
# Prerequisites:
#   - Full Xcode with the Metal Toolchain:
#       xcodebuild -downloadComponent MetalToolchain
#   - Command Line Tools (for their libtool):
#       xcode-select --install
#   - Zig matching the pinned Ghostty's minimum_zig_version:
#       brew install zig@0.15
#
# Usage:
#   scripts/custom/build-ghostty.sh
#
# Bumping the pin: after merging a new upstream release, read the Ghostty
# commit embedded in the released app and update GHOSTTY_COMMIT:
#   strings -a /Applications/tian.app/Contents/MacOS/tian \
#     | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-main\+[0-9a-f]+$'

# Ghostty commit embedded in the upstream tian v1.5.13 release (1.3.2-main+b839561).
GHOSTTY_COMMIT="b839561e5db36589d6a999044c76bfe785a013d7"
GHOSTTY_REPO="https://github.com/ghostty-org/ghostty.git"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VENDOR_DIR="$PROJECT_ROOT/tian/Vendor"
# project.yml bundles Ghostty resources from this exact path.
GHOSTTY_DIR="$PROJECT_ROOT/.ghostty-src"
ZIG="${ZIG:-zig}"

fail() {
    echo "Error: $*" >&2
    exit 1
}

# --- Toolchain checks --------------------------------------------------------

export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
case "$DEVELOPER_DIR" in
    *CommandLineTools*)
        fail "full Xcode is required, but the developer dir is $DEVELOPER_DIR. Run: sudo xcode-select -s /Applications/Xcode.app" ;;
esac
if ! xcrun -sdk macosx metal --version >/dev/null 2>&1; then
    fail "Metal Toolchain is missing. Run: xcodebuild -downloadComponent MetalToolchain"
fi
if ! command -v "$ZIG" >/dev/null 2>&1; then
    fail "zig not found. Run: brew install zig@0.15"
fi

# Ghostty invokes `libtool` by name, so a PATH shim reroutes only that tool.
CLT_LIBTOOL="/Library/Developer/CommandLineTools/usr/bin/libtool"
if [ ! -x "$CLT_LIBTOOL" ]; then
    fail "Command Line Tools libtool not found at $CLT_LIBTOOL. Run: xcode-select --install"
fi
SHIM_DIR="$(mktemp -d)"
trap 'rm -rf "$SHIM_DIR"' EXIT
ln -s "$CLT_LIBTOOL" "$SHIM_DIR/libtool"

# --- Ghostty source at the pinned commit -------------------------------------

if [ ! -d "$GHOSTTY_DIR/.git" ]; then
    if [ -e "$GHOSTTY_DIR" ]; then
        fail "$GHOSTTY_DIR exists but is not a git checkout; move it away first."
    fi
    git init -q "$GHOSTTY_DIR"
fi

if [ "$(git -C "$GHOSTTY_DIR" rev-parse -q --verify HEAD || true)" != "$GHOSTTY_COMMIT" ]; then
    if [ -n "$(git -C "$GHOSTTY_DIR" status --porcelain --untracked-files=no)" ]; then
        fail "$GHOSTTY_DIR has local changes; refusing to switch commits."
    fi
    echo "Fetching Ghostty ${GHOSTTY_COMMIT:0:9}..."
    git -C "$GHOSTTY_DIR" fetch -q --depth 1 "$GHOSTTY_REPO" "$GHOSTTY_COMMIT"
    git -C "$GHOSTTY_DIR" checkout -q --detach FETCH_HEAD
fi
echo "Ghostty: $(git -C "$GHOSTTY_DIR" log -1 --format='%h %cs %s')"

REQUIRED_ZIG="$(sed -n 's/.*minimum_zig_version = "\([^"]*\)".*/\1/p' "$GHOSTTY_DIR/build.zig.zon")"
if [ -z "$REQUIRED_ZIG" ]; then
    fail "could not read minimum_zig_version from $GHOSTTY_DIR/build.zig.zon"
fi
REQUIRED_SERIES="$(echo "$REQUIRED_ZIG" | cut -d. -f1,2)"
ZIG_VERSION="$("$ZIG" version)"
if [ "$(echo "$ZIG_VERSION" | cut -d. -f1,2)" != "$REQUIRED_SERIES" ]; then
    fail "this Ghostty needs zig $REQUIRED_ZIG, found $ZIG_VERSION. Run: brew install zig@$REQUIRED_SERIES"
fi

# --- Build -------------------------------------------------------------------

# Drop previous install outputs so nothing stale from another commit survives;
# zig's cache makes the reinstall cheap.
rm -rf "$GHOSTTY_DIR/zig-out" "$GHOSTTY_DIR/macos/GhosttyKit.xcframework"

echo "Building GhosttyKit.xcframework with zig $ZIG_VERSION (takes a few minutes)..."
(
    cd "$GHOSTTY_DIR"
    PATH="$SHIM_DIR:$PATH" "$ZIG" build \
        -Demit-xcframework=true \
        -Demit-macos-app=false \
        -Dxcframework-target=native \
        -Doptimize=ReleaseFast
)

BUILT_XCFW="$GHOSTTY_DIR/macos/GhosttyKit.xcframework"
BUILT_RESOURCES="$GHOSTTY_DIR/zig-out/share/ghostty"
[ -d "$BUILT_XCFW" ] || fail "GhosttyKit.xcframework not found at $BUILT_XCFW"
[ -d "$BUILT_RESOURCES" ] || fail "Ghostty resources not found at $BUILT_RESOURCES"

# An archive without the Ghostty C API still "builds" and only fails at tian's
# link step. Catch it here. zig caches the libtool output without regard to
# which libtool produced it, so a bad archive can survive a rerun.
BUILT_LIB="$(find "$BUILT_XCFW" -name 'libghostty*.a' -type f -print -quit)"
[ -n "$BUILT_LIB" ] || fail "no libghostty archive found in $BUILT_XCFW"
if [ "$(nm "$BUILT_LIB" 2>/dev/null | grep -c ' T _ghostty_surface_new$')" = 0 ]; then
    fail "$BUILT_LIB lacks the Ghostty C API. Clear the zig cache and rerun: rm -rf \"$GHOSTTY_DIR/.zig-cache\""
fi

# --- Vendor ------------------------------------------------------------------

echo "Vendoring into $VENDOR_DIR..."
rm -rf "$VENDOR_DIR/ghostty" "$VENDOR_DIR/GhosttyKit.xcframework" "$VENDOR_DIR/resources"
rm -f "$VENDOR_DIR/ghostty.h"
mkdir -p "$VENDOR_DIR/resources"

cp -R "$BUILT_XCFW" "$VENDOR_DIR/"
HEADER_PATH="$(find "$BUILT_XCFW" -name ghostty.h -type f -print -quit)"
[ -n "$HEADER_PATH" ] || fail "ghostty.h not found in $BUILT_XCFW"
cp "$HEADER_PATH" "$VENDOR_DIR/ghostty.h"
cp -R "$BUILT_RESOURCES"/. "$VENDOR_DIR/resources/"

echo ""
echo "Vendored Ghostty ${GHOSTTY_COMMIT:0:9}:"
echo "  XCFramework: $VENDOR_DIR/GhosttyKit.xcframework ($(du -sh "$VENDOR_DIR/GhosttyKit.xcframework" | cut -f1))"
echo "  Header:      $VENDOR_DIR/ghostty.h"
echo "  Resources:   $VENDOR_DIR/resources/"
echo "Done."
