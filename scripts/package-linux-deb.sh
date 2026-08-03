#!/usr/bin/env bash
# Builds typemate_<version>_amd64.deb from an existing Linux release bundle.
# Run on Linux/WSL from the repo root after `flutter build linux --release`.
#
# The app installs to /opt/typemate with a menu entry and icon; per-user
# autostart is registered by the app itself on first run.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUNDLE="build/linux/x64/release/bundle"
test -x "$BUNDLE/typemate" || { echo "bundle missing: $BUNDLE" >&2; exit 1; }

VERSION="$(sed -n 's/^version: \([0-9.]*\)+.*/\1/p' pubspec.yaml)"
test -n "$VERSION" || { echo "could not read version from pubspec.yaml" >&2; exit 1; }

PKG="typemate_${VERSION}_amd64"
STAGE="build/package/$PKG"
rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN" "$STAGE/opt/typemate" \
         "$STAGE/usr/share/applications" "$STAGE/usr/share/pixmaps"

cp -r "$BUNDLE"/. "$STAGE/opt/typemate/"
# Slim install: the large speech models download on first use for the
# selected language instead of shipping in every artifact.
bash scripts/slim-speech-models.sh "$STAGE/opt/typemate"
cp assets/typemate_icon.png "$STAGE/usr/share/pixmaps/typemate.png"

cat > "$STAGE/usr/share/applications/typemate.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Type Mate
Comment=Local hold-to-dictate speech typing
Exec=/opt/typemate/typemate
Icon=typemate
Terminal=false
Categories=Utility;Accessibility;
Keywords=dictation;speech;voice;typing;
EOF

INSTALLED_SIZE_KB="$(du -sk "$STAGE/opt" "$STAGE/usr" | awk '{s+=$1} END {print s}')"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: typemate
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Installed-Size: $INSTALLED_SIZE_KB
Depends: libgtk-3-0 (>= 3.24), libcurl4t64 | libcurl4
Maintainer: CodeWalnut <nattu@codewalnut.com>
Homepage: https://github.com/CW-Codewalnut/typemate
Description: Local push-to-talk dictation that types into any app
 Hold a shortcut, speak, release: the transcript is typed into the
 focused field. All speech models run locally; no audio leaves the
 machine. Requires an X11 session (or XWayland focus) for global
 shortcuts and synthetic typing.
EOF

mkdir -p dist
# gzip: the payload is dominated by already-quantized models, so xz would
# spend minutes for little gain.
dpkg-deb --build --root-owner-group -Zgzip "$STAGE" "dist/$PKG.deb"
ls -la "dist/$PKG.deb"
