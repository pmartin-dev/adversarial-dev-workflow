#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"

command -v realpath >/dev/null 2>&1 || { echo "Error: realpath not found. Install coreutils."; exit 1; }
resolve_path() { realpath "$1"; }

echo "Uninstalling Adversarial Dev Workflow skills..."

# Remove legacy /adw skill if present
LEGACY_TARGET="$SKILLS_DIR/adw"
if [ -L "$LEGACY_TARGET" ]; then
  rm "$LEGACY_TARGET"
  echo "Removed legacy skill: $LEGACY_TARGET"
fi

uninstall_skill() {
  local NAME="$1"
  local SOURCE="$SCRIPT_DIR/skills/$NAME"
  local TARGET="$SKILLS_DIR/$NAME"

  if [ ! -L "$TARGET" ]; then
    if [ -e "$TARGET" ]; then
      echo "Warning: $TARGET exists but is not a symlink. Skipping (not ours)."
    else
      echo "Nothing to uninstall: $NAME (not found)"
    fi
    return
  fi

  # Verify the symlink points to our source
  EXISTING="$(resolve_path "$(readlink "$TARGET")")"
  SOURCE_RESOLVED="$(resolve_path "$SOURCE")"
  if [ "$EXISTING" != "$SOURCE_RESOLVED" ]; then
    echo "Warning: $TARGET points to $EXISTING, not to this repo. Skipping."
    return
  fi

  rm "$TARGET"
  echo "Removed: $TARGET"
}

uninstall_skill "adw-plan"
uninstall_skill "adw-changes"

echo ""
echo "Skills uninstalled."
