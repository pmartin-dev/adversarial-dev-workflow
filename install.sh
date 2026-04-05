#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"

command -v realpath >/dev/null 2>&1 || { echo "Error: realpath not found. Install coreutils."; exit 1; }
resolve_path() { realpath "$1"; }

echo "Installing Adversarial Dev Workflow skills..."

# Create skills directory if needed
if [ ! -d "$SKILLS_DIR" ]; then
  mkdir -p "$SKILLS_DIR"
  echo "Created $SKILLS_DIR"
fi

# Remove legacy /adw skill if present (replaced by adw-plan and adw-changes)
LEGACY_TARGET="$SKILLS_DIR/adw"
if [ -L "$LEGACY_TARGET" ]; then
  rm "$LEGACY_TARGET"
  echo "Removed legacy skill: $LEGACY_TARGET"
elif [ -e "$LEGACY_TARGET" ]; then
  echo "Warning: $LEGACY_TARGET exists and is not a symlink. Remove it manually if needed."
fi

# Install each skill
install_skill() {
  local NAME="$1"
  local SOURCE="$SCRIPT_DIR/skills/$NAME"
  local TARGET="$SKILLS_DIR/$NAME"

  if [ ! -d "$SOURCE" ]; then
    echo "Error: Skill source not found at $SOURCE"
    return 1
  fi

  if [ -L "$TARGET" ]; then
    EXISTING="$(resolve_path "$(readlink "$TARGET")")"
    SOURCE_RESOLVED="$(resolve_path "$SOURCE")"
    if [ "$EXISTING" = "$SOURCE_RESOLVED" ]; then
      echo "Already installed: $NAME"
      return
    else
      echo "Warning: $TARGET exists but points to $EXISTING"
      echo "Remove it manually to reinstall: rm \"$TARGET\""
      return 1
    fi
  elif [ -e "$TARGET" ]; then
    echo "Warning: $TARGET exists and is not a symlink."
    echo "Remove it manually to install: rm -rf \"$TARGET\""
    return 1
  fi

  ln -s "$SOURCE" "$TARGET"
  echo "Installed: $TARGET -> $SOURCE"

  if [ ! -f "$TARGET/SKILL.md" ]; then
    echo "Warning: Symlink created but SKILL.md not found in $TARGET"
    echo "The skill may not work. Verify the repository is complete."
  fi
}

FAILED=0
install_skill "adw-plan"   || FAILED=$((FAILED + 1))
install_skill "adw-changes" || FAILED=$((FAILED + 1))

echo ""
if [ "$FAILED" -gt 0 ]; then
  echo "Warning: $FAILED skill(s) failed to install. See errors above."
  exit 1
fi
echo "Done! You can now use the following skills in Claude Code:"
echo "  /adw-plan   — Challenge a plan adversarially"
echo "  /adw-changes — Challenge code changes adversarially"
