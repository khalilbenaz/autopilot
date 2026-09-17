#!/usr/bin/env bash
# Relance autopilot jusqu'à ce que le travail soit terminé, en attendant la
# réinitialisation du quota quand elle bloque.
#
# N'appelle jamais autopilot-state.sh init : un état existant est requis,
# sinon sortie en code 2.
set -uo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETAT="$ICI/autopilot-state.sh"
QUOTA="${AUTOPILOT_QUOTA:-$ICI/autopilot-quota.sh}"
CLAUDE="${AUTOPILOT_CLAUDE:-claude}"
DORMIR="${AUTOPILOT_SLEEP:-sleep}"

CODE_QUOTA=7          # code de sortie de claude interprété comme « quota épuisé »
ATTENTE_DEFAUT=900    # 15 min, quand l'heure de reset est inconnue
MARGE=60              # on se réveille un peu après le reset annoncé
ATTENTE_PLANCHER=60   # jamais moins d'une minute (évite une rafale d'appels)
ATTENTE_MAX=691200    # 8 jours : couvre la fenêtre 7 jours + marge, plafonne le reste
PAUSE_ERREUR=30       # pause courte après une erreur non liée au quota

usage() {
  printf 'usage : %s <dossier> [--max-cycles N] [--dry-run]\n' "$(basename "$0")" >&2
}

cible=""; max_cycles=100; dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --max-cycles)
      case "${2:-}" in
        ''|*[!0-9]*)
          printf 'valeur numérique attendue pour --max-cycles\n' >&2
          usage
          exit 2
          ;;
      esac
      max_cycles="$2"; shift 2
      ;;
    --dry-run)
      dry=1; shift
      ;;
    -*)
      printf 'option inconnue : %s\n' "$1" >&2
      usage
      exit 2
      ;;
    *)
      cible="$1"; shift
      ;;
  esac
done

if [ -z "$cible" ]; then
  usage
  exit 2
fi
if [ ! -d "$cible" ]; then
  printf 'dossier introuvable : %s\n' "$cible" >&2
  exit 2
fi
if [ ! -f "$cible/.autopilot/STATE.json" ]; then
  printf 'aucun état autopilot dans %s (lancer autopilot-state.sh init au préalable)\n' "$cible" >&2
  exit 2
fi

journal() { bash "$ETAT" ledger "$cible" "$1" 2>/dev/null || true; }

attente() {
  # Rend le nombre de secondes à dormir avant la prochaine tentative,
  # plafonné pour éviter une rafale (epoch passé) ou une attente absurde
  # (epoch aberrant, très loin dans le futur).
  epoch=$(bash "$QUOTA" reset-epoch 2>/dev/null || printf -- '-')
  case "$epoch" in
    ''|-|*[!0-9]*) printf '%s\n' "$ATTENTE_DEFAUT"; return ;;
  esac
  maintenant=$(date +%s)
  delta=$(( epoch - maintenant + MARGE ))
  if [ "$delta" -lt "$ATTENTE_PLANCHER" ]; then
    delta="$ATTENTE_PLANCHER"
  elif [ "$delta" -gt "$ATTENTE_MAX" ]; then
    delta="$ATTENTE_MAX"
  fi
  printf '%s\n' "$delta"
}

cycle=0
while [ "$cycle" -lt "$max_cycles" ]; do
  if [ ! -d "$cible" ]; then
    printf 'le dossier a disparu en cours de route : %s\n' "$cible" >&2
    exit 2
  fi

  if bash "$ETAT" "done" "$cible"; then
    journal "Travail terminé, le superviseur s'arrête."
    exit 0
  fi

  cycle=$((cycle + 1))
  bash "$ETAT" set "$cible" cycles "$cycle" 2>/dev/null || true

  if [ "$dry" -eq 1 ]; then
    printf 'cycle %d : lancerait %s\n' "$cycle" "$CLAUDE"
    continue
  fi

  ( cd "$cible" && "$CLAUDE" -p "autopilot reprise" )
  code=$?

  if [ "$code" -eq "$CODE_QUOTA" ]; then
    secondes=$(attente)
    journal "Attente de quota : $secondes s avant reprise (cycle $cycle)."
    "$DORMIR" "$secondes"
    continue
  fi

  if [ "$code" -ne 0 ]; then
    journal "claude a rendu le code $code au cycle $cycle, nouvelle tentative."
    "$DORMIR" "$PAUSE_ERREUR"
  fi
done

if [ -d "$cible" ] && bash "$ETAT" "done" "$cible"; then
  journal "Travail terminé au dernier cycle."
  exit 0
fi
journal "Plafond de $max_cycles cycles atteint sans achèvement."
exit 1
