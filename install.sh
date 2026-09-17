#!/usr/bin/env bash
# Rend la skill autopilot visible par Claude Code, sans dupliquer les fichiers.
set -uo pipefail

SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skill"
DEST="${HOME}/.claude/skills/autopilot"

chmod +x "$SOURCE"/scripts/*.sh 2>/dev/null || true

if ! mkdir -p "$(dirname "$DEST")"; then
  printf 'échec : impossible de créer %s.\n' "$(dirname "$DEST")" >&2
  printf 'cause probable : droits insuffisants sur %s.\n' "$HOME" >&2
  exit 1
fi

if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  printf 'refus : %s existe déjà et n'\''est pas un lien.\n' "$DEST" >&2
  printf 'déplace-le ou supprime-le, puis relance.\n' >&2
  exit 1
fi

rm -f "$DEST"

if ! ln -s "$SOURCE" "$DEST"; then
  printf 'échec : impossible de créer le lien %s -> %s.\n' "$DEST" "$SOURCE" >&2
  printf 'cause probable : droits insuffisants sur %s.\n' "$(dirname "$DEST")" >&2
  exit 1
fi

# On ne se contente pas du code de retour de ln : on relit le disque pour
# constater que le lien existe vraiment et qu'il pointe au bon endroit,
# avant d'annoncer un succès.
cible_posee="$(readlink "$DEST" 2>/dev/null || true)"
if [ ! -L "$DEST" ] || [ "$cible_posee" != "$SOURCE" ]; then
  printf 'échec : le lien %s n'\''a pas été posé correctement.\n' "$DEST" >&2
  printf 'cause probable : droits insuffisants, ou disque plein.\n' >&2
  exit 1
fi

printf 'skill autopilot installée : %s -> %s\n' "$DEST" "$SOURCE"
