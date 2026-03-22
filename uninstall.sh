#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
SKILL_NAME="adw"
SOURCE="$SCRIPT_DIR/skills/$SKILL_NAME"
TARGET="$SKILLS_DIR/$SKILL_NAME"

command -v realpath >/dev/null 2>&1 || { echo "Error: realpath not found. Install coreutils."; exit 1; }
resolve_path() { realpath "$1"; }

echo "Uninstalling Adversarial Dev Workflow skill..."

if [ ! -L "$TARGET" ]; then
  if [ -e "$TARGET" ]; then
    echo "Warning: $TARGET exists but is not a symlink. Skipping (not ours)."
    exit 1
  else
    echo "Nothing to uninstall: $TARGET does not exist."
    exit 0
  fi
fi

# Verify the symlink points to our source
EXISTING="$(resolve_path "$(readlink "$TARGET")")"
SOURCE_RESOLVED="$(resolve_path "$SOURCE")"
if [ "$EXISTING" != "$SOURCE_RESOLVED" ]; then
  echo "Warning: $TARGET points to $EXISTING, not to this repo."
  echo "Skipping to avoid removing someone else's skill."
  exit 1
fi

# Remove the symlink
rm "$TARGET"
echo "Removed: $TARGET"

echo ""
echo "Skill uninstalled. Your workflow state in ~/.adw/ was NOT deleted."

if [ -d "$HOME/.adw" ] && [ "$(ls -A "$HOME/.adw" 2>/dev/null)" ]; then
  echo ""
  echo "Note: Workflow state still exists in ~/.adw/:"
  ls -1 "$HOME/.adw/" 2>/dev/null | head -10
  echo "To remove all state: rm -rf ~/.adw/"
fi
