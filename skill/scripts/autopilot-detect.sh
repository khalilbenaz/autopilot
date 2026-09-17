#!/usr/bin/env bash
# Décide du mode de travail : creation ou amelioration.
# Usage : autopilot-detect.sh [dossier]
set -uo pipefail

cible="${1:-.}"

if [ ! -d "$cible" ]; then
  printf 'creation\n'; exit 0
fi

# Dossier illisible (pas de droit de lecture ou de traversée) : on ne peut
# pas savoir s'il contient déjà du code, donc par prudence on ne propose
# jamais de repartir de zéro par-dessus un contenu qu'on n'a pas pu voir.
if [ ! -r "$cible" ] || [ ! -x "$cible" ]; then
  printf 'amelioration\n'; exit 0
fi

# Un fichier ou un lien symbolique visible suffit à parler d'amélioration ;
# les entrées cachées (.DS_Store, .git, .gitignore) et les répertoires
# (y compris un sous-dossier vide) ne comptent pas comme du contenu.
visibles=$(find "$cible" -maxdepth 2 \( -type f -o -type l \) \
  -not -path '*/.*' -not -name '.*' 2>/dev/null | head -1)

if [ -n "$visibles" ]; then
  printf 'amelioration\n'
else
  printf 'creation\n'
fi
