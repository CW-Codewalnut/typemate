#!/usr/bin/env bash
# Builds typemate-<version>-1.x86_64.rpm from an existing Linux release
# bundle. Run on Linux/WSL from the repo root (needs rpmbuild: apt install rpm).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUNDLE="build/linux/x64/release/bundle"
test -x "$BUNDLE/typemate" || { echo "bundle missing: $BUNDLE" >&2; exit 1; }
command -v rpmbuild >/dev/null || { echo "rpmbuild not found (apt install rpm)" >&2; exit 1; }

VERSION="$(sed -n 's/^version: \([0-9.]*\)+.*/\1/p' pubspec.yaml)"
test -n "$VERSION" || { echo "could not read version from pubspec.yaml" >&2; exit 1; }

TOP="$PWD/build/package/rpm"
rm -rf "$TOP"
mkdir -p "$TOP"/{SPECS,BUILD,RPMS,BUILDROOT}

cat > "$TOP/SPECS/typemate.spec" <<EOF
Name:           typemate
Version:        $VERSION
Release:        1
Summary:        Local push-to-talk dictation that types into any app
License:        Apache-2.0
URL:            https://github.com/CW-Codewalnut/typemate
BuildArch:      x86_64
Requires:       gtk3, libcurl
# The bundle ships its own runtimes/libraries; do not scan them for deps.
AutoReqProv:    no
# Models are already quantized; use fast gzip instead of slow xz/zstd.
%define _binary_payload w2.gzdio
%define _build_id_links none
%global __strip /bin/true

%description
Hold a shortcut, speak, release: the transcript is typed into the
focused field. All speech models run locally; no audio leaves the
machine. Requires an X11 session (or XWayland focus) for global
shortcuts and synthetic typing.

%install
mkdir -p %{buildroot}/opt/typemate \\
         %{buildroot}%{_datadir}/applications \\
         %{buildroot}%{_datadir}/pixmaps
cp -r $PWD/$BUNDLE/. %{buildroot}/opt/typemate/
cp $PWD/assets/typemate_icon_1024.png %{buildroot}%{_datadir}/pixmaps/typemate.png
cat > %{buildroot}%{_datadir}/applications/typemate.desktop <<DESK
[Desktop Entry]
Type=Application
Name=Type Mate
Comment=Local hold-to-dictate speech typing
Exec=/opt/typemate/typemate
Icon=typemate
Terminal=false
Categories=Utility;Accessibility;
Keywords=dictation;speech;voice;typing;
DESK

%files
/opt/typemate
%{_datadir}/applications/typemate.desktop
%{_datadir}/pixmaps/typemate.png
EOF

rpmbuild -bb --define "_topdir $TOP" "$TOP/SPECS/typemate.spec"
mkdir -p dist
cp "$TOP"/RPMS/x86_64/typemate-"$VERSION"-1.x86_64.rpm dist/
ls -la dist/typemate-"$VERSION"-1.x86_64.rpm
