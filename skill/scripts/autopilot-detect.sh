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
#
# Le caractère caché se juge sur le NOM des entrées trouvées dans le
# dossier cible (-name), jamais sur le chemin complet : un filtre
# -path '*/.*' s'appliquerait aussi au préfixe d'invocation et rendrait
# « vide » tout projet vivant sous ~/.config, ~/.cache, ~/.local/share…
# Les répertoires cachés sont élagués (-prune) pour que leur contenu, lui
# aussi caché, ne compte pas non plus : sans ça, .git/config suffirait à
# faire passer un dépôt vide pour un projet existant.
visibles=$(find "$cible" -mindepth 1 -maxdepth 2 \
  -name '.*' -prune -o \( -type f -o -type l \) -print 2>/dev/null | head -1)

if [ -n "$visibles" ]; then
  printf 'amelioration\n'
else
  printf 'creation\n'
fi
