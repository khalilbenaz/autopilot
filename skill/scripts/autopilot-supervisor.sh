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

CODE_QUOTA=7            # code de sortie de claude interprété comme « quota épuisé »
ATTENTE_DEFAUT=900      # 15 min, quand l'heure de reset est inconnue
MARGE=60                # on se réveille un peu après le reset annoncé
ATTENTE_PLANCHER=60     # jamais moins d'une minute (évite une rafale d'appels)
ATTENTE_MAX=691200      # 8 jours : plafond d'UN sommeil (fenêtre 7 jours + marge)
BUDGET_ATTENTE_DEFAUT=691200  # 8 jours : plafond de la SOMME des sommeils du run
PAUSE_ERREUR=30         # pause courte après une erreur non liée au quota

usage() {
  printf 'usage : %s <dossier> [--max-cycles N] [--budget-attente N] [--dry-run]\n' \
    "$(basename "$0")" >&2
  printf 'codes de sortie : 0 terminé, 1 plafond de cycles atteint, 2 dossier ou état absent, 3 bloqué (décision humaine requise)\n' >&2
}

cible=""; max_cycles=100; dry=0; budget_attente=$BUDGET_ATTENTE_DEFAUT
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
    --budget-attente)
      case "${2:-}" in
        ''|*[!0-9]*)
          printf 'valeur numérique attendue pour --budget-attente\n' >&2
          usage
          exit 2
          ;;
      esac
      budget_attente="$2"; shift 2
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

sonde_quota_epuisee() {
  # Rend "1" si la sonde signale un compte épuisé, "0" sinon. Le superviseur
  # ne peut pas se fier au code de sortie de claude pour ça (aucun code n'est
  # documenté ni choisi par l'agent) : c'est la sonde qui tranche. Une sonde
  # en panne ou dont la sortie est illisible est traitée comme « non
  # épuisé » et consignée : une sonde cassée ne doit jamais provoquer une
  # attente de plusieurs heures à sa place.
  verdict=$(bash "$QUOTA" verdict 2>/dev/null)
  code_sonde=$?
  premier="${verdict%% *}"
  if [ "$code_sonde" -ne 0 ] || [ -z "$premier" ] ||
     { [ "$premier" != "0" ] && [ "$premier" != "1" ]; }; then
    journal "Compte traité comme non épuisé par défaut : sonde de quota indisponible ou illisible (cycle $cycle)."
    printf '0\n'
    return
  fi
  printf '%s\n' "$premier"
}

attente_cumulee=0

dormir_avec_budget() { # <secondes-a-dormir> <message-de-ledger>
  # Additionne les secondes réellement demandées à chaque sommeil. Si la
  # somme dépasserait le budget d'attente cumulée du run, on abandonne au
  # lieu de dormir encore : sans ce garde-fou, un plafond de cycles à 100
  # combiné à un sommeil individuel plafonné à 8 jours (ATTENTE_MAX)
  # laisserait un epoch de reset aberrant faire dormir le superviseur plus
  # de deux ans avant de rendre la main.
  duree="$1"; message="$2"
  total_potentiel=$(( attente_cumulee + duree ))
  if [ "$total_potentiel" -gt "$budget_attente" ]; then
    journal "Abandon : budget d'attente cumulée de $budget_attente s dépassé (cycle $cycle)."
    exit 1
  fi
  attente_cumulee="$total_potentiel"
  journal "$message"
  "$DORMIR" "$duree"
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

  phase=$(bash "$ETAT" get "$cible" phase 2>/dev/null || true)
  if [ "$phase" = "bloque" ]; then
    journal "Blocage signalé par la skill (phase bloque) : décision humaine requise, le superviseur s'arrête."
    exit 3
  fi

  cycle=$((cycle + 1))
  bash "$ETAT" set "$cible" cycles "$cycle" 2>/dev/null || true

  if [ "$dry" -eq 1 ]; then
    printf 'cycle %d : lancerait %s\n' "$cycle" "$CLAUDE"
    continue
  fi

  ( cd "$cible" && "$CLAUDE" -p "autopilot reprise" )
  code=$?

  if [ "$code" -ne 0 ]; then
    # Le code de sortie 7 reste un raccourci accepté : s'il arrive, on
    # attend sans même interroger la sonde. Pour tout autre code non nul,
    # c'est la sonde — et elle seule — qui décide si le compte est épuisé.
    if [ "$code" -eq "$CODE_QUOTA" ]; then
      epuise=1
    else
      epuise=$(sonde_quota_epuisee)
    fi

    if [ "$epuise" -eq 1 ]; then
      secondes=$(attente)
      dormir_avec_budget "$secondes" "Attente de quota : $secondes s avant reprise (cycle $cycle)."
    else
      dormir_avec_budget "$PAUSE_ERREUR" \
        "claude a rendu le code $code au cycle $cycle, nouvelle tentative."
    fi
  fi
done

if [ -d "$cible" ] && bash "$ETAT" "done" "$cible"; then
  journal "Travail terminé au dernier cycle."
  exit 0
fi
journal "Plafond de $max_cycles cycles atteint sans achèvement."
exit 1
