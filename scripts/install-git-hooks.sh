#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_DIR="$ROOT/.git/hooks"
SOURCE_DIR="$ROOT/scripts/git-hooks"

if [ ! -d "$ROOT/.git" ]; then
  echo "This script must be run from inside a git repository."
  exit 1
fi

for hook in pre-commit pre-push commit-msg; do
  cp "$SOURCE_DIR/$hook" "$HOOK_DIR/$hook"
  chmod +x "$HOOK_DIR/$hook"
  echo "Installed $hook"
done

echo "Git hooks installed."
