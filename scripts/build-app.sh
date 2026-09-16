#!/bin/bash
# Builds dist/ClaudeDeck.app (ad-hoc signed) with the Command Line Tools — no Xcode needed.
#
# Usage: scripts/build-app.sh [--universal] [--version X.Y.Z] [--zip] [--install]
#
#   --universal     build arm64 and x86_64 slices and merge them with lipo
#   --version X.Y.Z set CFBundleShortVersionString and CFBundleVersion in the bundle
#   --zip           also write dist/ClaudeDeck-<version>.zip and dist/ClaudeDeck-<version>.zip.sha256
#   --install       replace ~/Applications/ClaudeDeck.app with the build and launch it
#
# Flags can be given in any order. Without --version the version comes from Resources/Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

die() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
}

INSTALL=0
UNIVERSAL=0
ZIP=0
VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --install) INSTALL=1 ;;
    --universal) UNIVERSAL=1 ;;
    --zip) ZIP=1 ;;
    --version)
      [ $# -ge 2 ] && [ -n "$2" ] && [ "${2#--}" = "$2" ] || die "--version needs a value, e.g. --version 1.2.0"
      VERSION="$2"
      shift
      ;;
    --version=*) VERSION="${1#--version=}"; [ -n "$VERSION" ] || die "--version needs a value" ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

APP=dist/ClaudeDeck.app
EXECUTABLE="$APP/Contents/MacOS/ClaudeDeck"
PLIST="$APP/Contents/Info.plist"
ARCHS=(arm64 x86_64)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "$UNIVERSAL" = 1 ]; then
  SLICES=()
  for arch in "${ARCHS[@]}"; do
    triple="$arch-apple-macosx14.0"
    echo "==> swift build -c release --triple $triple"
    # A scratch path per triple: sharing .build between triples makes SwiftPM fail on rebuilds
    # ("command … swift-version….txt not registered").
    scratch=".build/$arch"
    swift build -c release --triple "$triple" --scratch-path "$scratch" \
      || die "release build for $triple failed (see the compiler output above)"
    slice="$(swift build -c release --triple "$triple" --scratch-path "$scratch" --show-bin-path)/ClaudeDeck"
    [ -f "$slice" ] || die "missing binary for $arch at $slice"
    SLICES+=("$slice")
  done
  lipo -create "${SLICES[@]}" -output "$EXECUTABLE" || die "lipo could not merge ${SLICES[*]}"
  built_archs="$(lipo -archs "$EXECUTABLE")"
  for arch in "${ARCHS[@]}"; do
    case " $built_archs " in
      *" $arch "*) ;;
      *) die "universal binary is missing $arch (lipo -archs: $built_archs)" ;;
    esac
  done
  echo "==> universal binary: $built_archs"
else
  swift build -c release
  cp "$(swift build -c release --show-bin-path)/ClaudeDeck" "$EXECUTABLE"
fi

cp Resources/Info.plist "$PLIST"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$PLIST"
fi
if [ -n "$VERSION" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST"
else
  VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")"
fi

# Ad-hoc signature (no Developer ID, no hardened runtime). Sign after every bundle change.
codesign --force --sign - "$APP"
codesign --verify "$APP"
echo "built $APP (version $VERSION)"

if [ "$ZIP" = 1 ]; then
  ZIP_NAME="ClaudeDeck-$VERSION.zip"
  rm -f "dist/$ZIP_NAME" "dist/$ZIP_NAME.sha256"
  ditto -c -k --norsrc --keepParent "$APP" "dist/$ZIP_NAME"
  (cd dist && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")
  echo "wrote dist/$ZIP_NAME"
  echo "wrote dist/$ZIP_NAME.sha256: $(cut -d' ' -f1 "dist/$ZIP_NAME.sha256")"
fi

if [ "$INSTALL" = 1 ]; then
  pkill -x ClaudeDeck || true
  mkdir -p "$HOME/Applications"
  rsync -a --delete "$APP/" "$HOME/Applications/ClaudeDeck.app/"
  open "$HOME/Applications/ClaudeDeck.app"
  echo "installed ~/Applications/ClaudeDeck.app"
fi
