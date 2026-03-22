#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
SKILL_NAME="adw"
SOURCE="$SCRIPT_DIR/skills/$SKILL_NAME"
TARGET="$SKILLS_DIR/$SKILL_NAME"

echo "Uninstalling Adversarial Dev Workflow skill..."

if [ ! -L "$TARGET" ]; then
  if [ -e "$TARGET" ]; then
    echo "Warning: $TARGET exists but is not a symlink. Skipping (not ours)."
  else
    echo "Nothing to uninstall: $TARGET does not exist."
  fi
  exit 0
fi

# Verify the symlink points to our source
EXISTING=$(readlink "$TARGET")
if [ "$EXISTING" != "$SOURCE" ]; then
  echo "Warning: $TARGET points to $EXISTING, not to this repo."
  echo "Skipping to avoid removing someone else's skill."
  exit 1
fi

# Remove the symlink
rm "$TARGET"
echo "Removed: $TARGET"

echo ""
echo "Skill uninstalled. Your workflow state in ~/.adw/ was NOT deleted."
echo "To remove state too: rm -rf ~/.adw/"
echo "Or use /adw clean per project before uninstalling."
