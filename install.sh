#!/usr/bin/env bash
# Rend la skill autopilot visible par Claude Code, sans dupliquer les fichiers.
set -uo pipefail

SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skill"
DEST="${HOME}/.claude/skills/autopilot"

chmod +x "$SOURCE"/scripts/*.sh 2>/dev/null || true
mkdir -p "$(dirname "$DEST")"

if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  printf 'refus : %s existe déjà et n'\''est pas un lien.\n' "$DEST" >&2
  printf 'déplace-le ou supprime-le, puis relance.\n' >&2
  exit 1
fi

rm -f "$DEST"
ln -s "$SOURCE" "$DEST"
printf 'skill autopilot installée : %s -> %s\n' "$DEST" "$SOURCE"
