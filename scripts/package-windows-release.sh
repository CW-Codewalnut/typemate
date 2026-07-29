#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER_BIN="${FLUTTER_BIN:-R:/Tools/flutter/bin/flutter}"
RELEASE_DIR="build/windows/x64/runner/Release"
DIST_DIR="dist"
PACKAGE_NAME="typemate-windows-x64"
STAGING_DIR="build/package/$PACKAGE_NAME"
ZIP_PATH="$DIST_DIR/$PACKAGE_NAME.zip"
# Anonymous error reporting backend for RELEASE builds only; dev builds
# (plain `flutter run`/`flutter build`) carry no DSN and send nothing.
# The single source of truth is the TYPEMATE_SENTRY_DSN env in
# .github/workflows/release.yml; CI must always provide it. The literal
# below exists ONLY for packaging locally on a dev machine (a DSN is an
# ingest-only address, safe to commit) and must be kept matching the
# workflow's value if the DSN ever rotates.
if [ -z "${TYPEMATE_SENTRY_DSN:-}" ]; then
  if [ -n "${CI:-}" ]; then
    echo "ERROR: TYPEMATE_SENTRY_DSN is not set; CI must pass the DSN from release.yml" >&2
    exit 1
  fi
  echo "NOTE: TYPEMATE_SENTRY_DSN not set; using the local-packaging fallback DSN" >&2
  TYPEMATE_SENTRY_DSN="https://6dd30c1b5156941a36bca5322e9395ee@o4511812673994752.ingest.de.sentry.io/4511812753490000"
fi

"$FLUTTER_BIN" build windows \
  --dart-define=TYPEMATE_SENTRY_DSN="$TYPEMATE_SENTRY_DSN"

test -f "$RELEASE_DIR/typemate.exe"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
cp -R "$RELEASE_DIR"/. "$STAGING_DIR"/

cat > "$STAGING_DIR/README.txt" <<'README'
TypeMate Windows x64
===================

Run typemate.exe.

Optional local speech runtime environment variables:
- TYPEMATE_WHISPER_CLI: path to whisper.cpp CLI executable
- TYPEMATE_WHISPER_MODEL: path to the local whisper model file

Default hold shortcut on Windows: Ctrl+Alt+Space.
README

rm -f "$ZIP_PATH"
(
  cd "build/package"
  if command -v 7z >/dev/null 2>&1; then
    7z a -tzip "../../$ZIP_PATH" "$PACKAGE_NAME" >/dev/null
  elif command -v zip >/dev/null 2>&1; then
    zip -qr "../../$ZIP_PATH" "$PACKAGE_NAME"
  else
    python - <<'PY'
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
package = Path('typemate-windows-x64')
out = Path('../../dist/typemate-windows-x64.zip')
with ZipFile(out, 'w', ZIP_DEFLATED) as zf:
    for path in package.rglob('*'):
        if path.is_file():
            zf.write(path, path.as_posix())
PY
  fi
)

test -f "$ZIP_PATH"
printf '%s\n' "$ZIP_PATH"

# Also produce the Setup installer when Inno Setup is available
# (installer/typemate.iss). Version comes from pubspec.yaml.
VERSION="$(sed -n 's/^version: \([0-9.]*\)+.*/\1/p' pubspec.yaml)"
ISCC="${ISCC:-$HOME/scoop/apps/inno-setup/current/ISCC.exe}"
if [ -x "$ISCC" ] && [ -n "$VERSION" ]; then
  # MSYS bash (Git Bash, GitHub runners) path-converts /D... into a
  # Windows path, so ISCC sees a second "script filename" and aborts;
  # exclude the define flag from argument conversion.
  MSYS2_ARG_CONV_EXCL='/DAppVersion' \
    "$ISCC" "/DAppVersion=$VERSION" "installer/typemate.iss"
  printf '%s\n' "$DIST_DIR/TypeMate-Setup-v$VERSION.exe"
else
  echo "NOTE: Inno Setup not found; skipped TypeMate-Setup exe" >&2
fi
