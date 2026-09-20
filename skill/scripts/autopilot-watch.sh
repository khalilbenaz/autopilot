#!/usr/bin/env bash
# Surveillance continue du quota pendant qu'une session claude -p travaille.
#
# Contrairement à autopilot-supervisor.sh (qui n'interroge la sonde qu'APRÈS
# une sortie non nulle de claude), ce script tourne EN PARALLÈLE d'une
# session en cours : il permet à la skill de constater, ENTRE deux tâches,
# qu'il vaut mieux ne pas en démarrer une nouvelle plutôt que de se faire
# couper au milieu. Il ne coupe jamais lui-même une tâche en cours : il pose
# un signal (QUOTA_ALERTE) que la skill lit d'elle-même à son prochain point
# de décision.
#
# autopilot-watch.sh <dossier> [--seuil N] [--intervalle S]
usage() {
  printf 'usage : %s <dossier> [--seuil N] [--intervalle S]\n' \
    "$(basename "$0")" >&2
}

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETAT="$ICI/autopilot-state.sh"
QUOTA="${AUTOPILOT_QUOTA:-$ICI/autopilot-quota.sh}"
DORMIR="${AUTOPILOT_SLEEP:-sleep}"

CODE_ETAT_ILLISIBLE=5
SEUIL_DEFAUT=90
INTERVALLE_DEFAUT=300

cible=""; seuil=$SEUIL_DEFAUT; intervalle=$INTERVALLE_DEFAUT
while [ $# -gt 0 ]; do
  case "$1" in
    --seuil)
      case "${2:-}" in
        ''|*[!0-9]*)
          printf 'valeur numérique attendue pour --seuil\n' >&2
          usage
          exit 2
          ;;
      esac
      seuil="$2"; shift 2
      ;;
    --intervalle)
      case "${2:-}" in
        ''|*[!0-9]*)
          printf 'valeur numérique attendue pour --intervalle\n' >&2
          usage
          exit 2
          ;;
      esac
      intervalle="$2"; shift 2
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
d="$cible/.autopilot"
if [ ! -f "$d/STATE.json" ]; then
  printf 'aucun état autopilot dans %s (rien à surveiller)\n' "$cible" >&2
  exit 2
fi

horodatage() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

printf '%s\n' "$$" > "$d/watch.pid"
# Se déclenche même sur une sortie anormale : un veilleur qui plante sans
# nettoyer son propre fichier PID laisserait une trace trompeuse (un PID qui
# n'existe plus, pris pour un veilleur vivant).
trap 'rm -f "$d/watch.pid" 2>/dev/null || true' EXIT

# Écrit l'état du tour dans QUOTA.json, atomiquement (fichier temporaire puis
# renommage) : un lecteur concurrent (la skill, le superviseur) ne doit
# jamais voir un fichier à moitié écrit.
ecrire_quota_json() { # <sonde_ok:0|1> <pourcentage|-> <fenetre|-> <epoch|->
  sonde_ok="$1"; pct="$2"; fenetre="$3"; epoch="$4"
  tmp="$d/QUOTA.json.tmp"
  {
    printf '{\n'
    printf '  "horodatage": "%s",\n' "$(horodatage)"
    if [ "$sonde_ok" -eq 1 ]; then
      printf '  "sonde_ok": true,\n'
    else
      printf '  "sonde_ok": false,\n'
    fi
    case "$pct" in
      ''|-) printf '  "utilisation": null,\n' ;;
      *) printf '  "utilisation": %s,\n' "$pct" ;;
    esac
    case "$fenetre" in
      ''|-) printf '  "fenetre": null,\n' ;;
      *)
        fenetre_echappee=$(printf '%s' "$fenetre" | sed 's/"/\\"/g')
        printf '  "fenetre": "%s",\n' "$fenetre_echappee"
        ;;
    esac
    case "$epoch" in
      ''|-) printf '  "resets_at": null\n' ;;
      *) printf '  "resets_at": %s\n' "$epoch" ;;
    esac
    printf '}\n'
  } > "$tmp"
  mv -f "$tmp" "$d/QUOTA.json"
}

# « en panne » ne se journalise qu'une fois par série d'échecs consécutifs,
# jamais à chaque tour : sinon un silence réseau de plusieurs heures noierait
# le ledger sous la même ligne répétée.
panne_deja_consignee=0

tour() {
  verdict=$(bash "$QUOTA" verdict 2>/dev/null)
  code_sonde=$?
  premier="${verdict%% *}"
  if [ "$code_sonde" -ne 0 ] || [ -z "$premier" ] ||
     { [ "$premier" != "0" ] && [ "$premier" != "1" ]; }; then
    ecrire_quota_json 0 - - -
    if [ "$panne_deja_consignee" -eq 0 ]; then
      bash "$ETAT" ledger "$cible" \
        "Sonde de quota indisponible ou illisible pendant la surveillance continue (veilleur) : tour ignoré, aucune alerte créée sur ce silence." \
        >/dev/null 2>&1 || true
      panne_deja_consignee=1
    fi
    # Une sonde en panne ne crée jamais d'alerte, et n'efface jamais une
    # alerte déjà posée : on ne sait rien de plus qu'avant ce tour.
    return
  fi
  panne_deja_consignee=0

  epoch=$(printf '%s\n' "$verdict" | awk '{print $2}')
  fenetre=$(printf '%s\n' "$verdict" | awk '{print $3}')
  pct=$(printf '%s\n' "$verdict" | awk '{print $4}')
  ecrire_quota_json 1 "$pct" "$fenetre" "$epoch"

  depasse=$(awk -v p="$pct" -v s="$seuil" 'BEGIN{print (p+0>=s+0)?1:0}' 2>/dev/null)
  if [ "$depasse" = "1" ]; then
    printf 'seuil d'"'"'alerte atteint : %s%% sur %s (seuil %s%%) à %s\n' \
      "$pct" "$fenetre" "$seuil" "$(horodatage)" > "$d/QUOTA_ALERTE"
  else
    rm -f "$d/QUOTA_ALERTE"
  fi
}

while :; do
  [ -d "$cible" ] || break

  phase=$(bash "$ETAT" get "$cible" phase 2>/dev/null)
  code_phase=$?
  [ "$code_phase" -eq "$CODE_ETAT_ILLISIBLE" ] && break
  { [ "$phase" = "termine" ] || [ "$phase" = "bloque" ]; } && break

  tour

  "$DORMIR" "$intervalle"
done

exit 0
