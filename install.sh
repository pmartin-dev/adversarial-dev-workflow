#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
SKILL_NAME="adw"
SOURCE="$SCRIPT_DIR/skills/$SKILL_NAME"
TARGET="$SKILLS_DIR/$SKILL_NAME"

echo "Installing Adversarial Dev Workflow skill..."

# Check source exists
if [ ! -d "$SOURCE" ]; then
  echo "Error: Skill source not found at $SOURCE"
  exit 1
fi

# Create skills directory if needed
if [ ! -d "$SKILLS_DIR" ]; then
  mkdir -p "$SKILLS_DIR"
  echo "Created $SKILLS_DIR"
fi

# Check for existing symlink or directory
if [ -L "$TARGET" ]; then
  EXISTING=$(readlink "$TARGET")
  if [ "$EXISTING" = "$SOURCE" ]; then
    echo "Already installed and pointing to the correct location."
    exit 0
  else
    echo "Warning: $TARGET exists but points to $EXISTING"
    echo "Remove it manually if you want to reinstall: rm $TARGET"
    exit 1
  fi
elif [ -e "$TARGET" ]; then
  echo "Warning: $TARGET exists and is not a symlink."
  echo "Remove it manually if you want to install: rm -rf $TARGET"
  exit 1
fi

# Create symlink
ln -s "$SOURCE" "$TARGET"
echo "Installed: $TARGET -> $SOURCE"

# Create ~/.adw directory for state persistence
if [ ! -d "$HOME/.adw" ]; then
  mkdir -p "$HOME/.adw"
  echo "Created ~/.adw/ for workflow state persistence"
fi

echo ""
echo "Done! You can now use /adw in Claude Code."
echo "Try: /adw plan <describe your feature>"
