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
VEILLEUR="$ICI/autopilot-watch.sh"
CLAUDE="${AUTOPILOT_CLAUDE:-claude}"
DORMIR="${AUTOPILOT_SLEEP:-sleep}"
# Doublure distincte de DORMIR, jamais partagée : le surveillant de dossier
# (voir dormir_avec_budget) tourne EN PARALLÈLE du sommeil principal, et
# réutiliser la même doublure ferait écrire les deux à la fois dans les
# mêmes fichiers de test (le sommeil principal ET la cadence de vérification),
# ce qui rendrait les assertions sur cette doublure imprévisibles.
VERIF_DOSSIER="${AUTOPILOT_VERIF_DOSSIER:-sleep}"

CODE_QUOTA=7            # code de sortie de claude interprété comme « quota épuisé »
CODE_ETAT_ILLISIBLE=5   # code rendu par autopilot-state.sh sur un STATE.json corrompu
ATTENTE_DEFAUT=900      # 15 min, quand l'heure de reset est inconnue
MARGE=60                # on se réveille un peu après le reset annoncé
ATTENTE_PLANCHER=60     # jamais moins d'une minute (évite une rafale d'appels)
ATTENTE_MAX=691200      # 8 jours : plafond d'UN sommeil (fenêtre 7 jours + marge)
BUDGET_ATTENTE_DEFAUT=691200  # 8 jours : plafond de la SOMME des sommeils du run
PAUSE_ERREUR=30         # pause courte après une erreur non liée au quota
MODE_PERMISSION_DEFAUT=acceptEdits   # sous --print, sans mode explicite, tout est refusé
MODES_PERMISSION="acceptEdits auto bypassPermissions manual dontAsk plan"
SANS_PROGRES_DEFAUT=3   # cycles consécutifs sans avancement avant d'abandonner
SEUIL_ALERTE_DEFAUT=90       # marge sous le seuil d'épuisement (95) de la sonde
INTERVALLE_VEILLE_DEFAUT=300 # 5 min entre deux tours du veilleur
VERIF_DOSSIER_INTERVALLE=30  # pendant un sommeil, revérifier au moins toutes les 30 s
                             # que le dossier cible existe encore
SEUIL_BATTEMENT_DEFAUT=600  # 10 min : au-delà, un battement de coeur est périmé
VEILLE_BATTEMENT_PAS=5      # intervalle court de revérification pendant la veille

usage() {
  printf 'usage : %s <dossier> [--max-cycles N] [--budget-attente N] [--permission-mode MODE] [--max-cycles-sans-progres N] [--seuil-alerte N] [--intervalle-veille S] [--seuil-battement S] [--sans-veilleur] [--dry-run]\n' \
    "$(basename "$0")" >&2
  printf 'modes de permission acceptés : %s (défaut : %s)\n' \
    "$MODES_PERMISSION" "$MODE_PERMISSION_DEFAUT" >&2
  printf 'codes de sortie : 0 terminé, 1 plafond de cycles atteint, 2 dossier ou état absent, 3 bloqué (décision humaine requise), 4 aucun progrès pendant plusieurs cycles\n' >&2
}

cible=""; max_cycles=100; dry=0; budget_attente=$BUDGET_ATTENTE_DEFAUT
mode_permission="$MODE_PERMISSION_DEFAUT"; max_sans_progres=$SANS_PROGRES_DEFAUT
seuil_alerte=$SEUIL_ALERTE_DEFAUT; intervalle_veille=$INTERVALLE_VEILLE_DEFAUT
seuil_battement=$SEUIL_BATTEMENT_DEFAUT
sans_veilleur=0
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
    --permission-mode)
      valide=0
      for m in $MODES_PERMISSION; do
        [ "${2:-}" = "$m" ] && valide=1
      done
      if [ "$valide" -eq 0 ]; then
        printf 'mode de permission inconnu : « %s »\n' "${2:-}" >&2
        printf 'valeurs acceptées : %s\n' "$MODES_PERMISSION" >&2
        usage
        exit 2
      fi
      mode_permission="$2"; shift 2
      ;;
    --max-cycles-sans-progres)
      case "${2:-}" in
        ''|*[!0-9]*|0)
          printf 'entier strictement positif attendu pour --max-cycles-sans-progres\n' >&2
          usage
          exit 2
          ;;
      esac
      max_sans_progres="$2"; shift 2
      ;;
    --dry-run)
      dry=1; shift
      ;;
    --seuil-alerte)
      case "${2:-}" in
        ''|*[!0-9]*)
          printf 'valeur numérique attendue pour --seuil-alerte\n' >&2
          usage
          exit 2
          ;;
      esac
      seuil_alerte="$2"; shift 2
      ;;
    --intervalle-veille)
      case "${2:-}" in
        ''|*[!0-9]*)
          printf 'valeur numérique attendue pour --intervalle-veille\n' >&2
          usage
          exit 2
          ;;
      esac
      intervalle_veille="$2"; shift 2
      ;;
    --seuil-battement)
      case "${2:-}" in
        ''|*[!0-9]*)
          printf 'valeur numérique attendue pour --seuil-battement\n' >&2
          usage
          exit 2
          ;;
      esac
      seuil_battement="$2"; shift 2
      ;;
    --sans-veilleur)
      sans_veilleur=1; shift
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

# --- Piège 1, la récursion : si ce superviseur tourne alors qu'il est
# lui-même la doublure lancée par un AUTRE superviseur (AUTOPILOT_SUPERVISE=1
# hérité), il refuse de démarrer. La défense principale vit dans SKILL.md
# (la skill ne lance aucun superviseur quand cette variable vaut 1) ; ce
# garde-fou est une seconde ligne de défense, côté script, pour ne jamais
# empiler des superviseurs les uns dans les autres si l'instruction de la
# skill était un jour contournée ou mal suivie.
if [ "${AUTOPILOT_SUPERVISE:-}" = "1" ]; then
  journal "Refus de lancement : AUTOPILOT_SUPERVISE=1 (déjà sous surveillance d'un superviseur), protection anti-récursion."
  printf 'refus : AUTOPILOT_SUPERVISE=1, une session surveillée ne relance pas son propre superviseur\n' >&2
  exit 0
fi

# --- Piège 2, la collision : verrou de PID anti-doublon. Un seul superviseur
# actif à la fois par dossier cible. Ne jamais se fier à la seule présence du
# fichier : les PID sont réutilisés par le système, un verrou périmé
# bloquerait indéfiniment un nouveau superviseur légitime.
verrou_pose=0
fichier_verrou="$cible/.autopilot/supervisor.pid"

verrou_valide() { # <pid>
  # Vivant, ET c'est bien CE script visant CE dossier — les deux conditions,
  # jamais une seule.
  pid_verrou="$1"
  case "$pid_verrou" in
    ''|*[!0-9]*) return 1 ;;
  esac
  kill -0 "$pid_verrou" 2>/dev/null || return 1
  ligne=$(ps -p "$pid_verrou" -o command= 2>/dev/null || true)
  case "$ligne" in
    *autopilot-supervisor.sh*"$cible"*) return 0 ;;
    *) return 1 ;;
  esac
}

acquerir_verrou() {
  # Rend 0 si le verrou est posé pour ce process, 1 si un autre superviseur
  # légitime tourne déjà pour ce dossier.
  if [ -f "$fichier_verrou" ]; then
    pid_existant=$(cat "$fichier_verrou" 2>/dev/null || true)
    if verrou_valide "$pid_existant"; then
      return 1
    fi
    # Verrou périmé (PID mort, ou PID réutilisé par une autre commande) :
    # remplacé sans hésiter.
  fi
  printf '%s\n' "$$" > "$fichier_verrou"
  verrou_pose=1
  return 0
}

liberer_verrou() {
  # Ne supprime jamais le verrou d'un AUTRE superviseur : seulement celui
  # qu'on a soi-même posé (verrou_pose ne vaut 1 que dans ce cas précis).
  [ "$verrou_pose" -eq 1 ] || return 0
  rm -f "$fichier_verrou" 2>/dev/null || true
  verrou_pose=0
}

if ! acquerir_verrou; then
  journal "Verrou actif : un superviseur tourne déjà pour ce dossier, rien à faire."
  printf 'un superviseur tourne déjà pour %s (verrou actif) : rien à faire\n' "$cible" >&2
  exit 0
fi

attente() { # <epoch|->
  # Rend le nombre de secondes à dormir avant la prochaine tentative,
  # plafonné pour éviter une rafale (epoch passé) ou une attente absurde
  # (epoch aberrant, très loin dans le futur). L'epoch vient du SEUL appel
  # de sonde du cycle : interroger la sonde une deuxième fois ici serait un
  # appel réseau de plus pour une information déjà en main.
  epoch="${1:--}"
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

epuise=0
epoch_reset="-"

sonde_quota() { # <journaliser-la-panne:0|1>
  # Interroge la sonde UNE seule fois et renseigne deux variables globales :
  # « epuise » (0/1) et « epoch_reset » (epoch du réveil, ou "-"). Le
  # superviseur ne peut pas se fier au code de sortie de claude pour savoir
  # si le quota est épuisé (aucun code n'est documenté ni choisi par
  # l'agent) : c'est la sonde qui tranche. Une sonde en panne ou dont la
  # sortie est illisible est traitée comme « non épuisé » et consignée : une
  # sonde cassée ne doit jamais provoquer une attente de plusieurs heures à
  # sa place.
  #
  # Pas de $( ) autour de l'appel : un sous-shell perdrait les deux valeurs.
  epuise=0
  epoch_reset="-"
  verdict=$(bash "$QUOTA" verdict 2>/dev/null)
  code_sonde=$?
  premier="${verdict%% *}"
  if [ "$code_sonde" -ne 0 ] || [ -z "$premier" ] ||
     { [ "$premier" != "0" ] && [ "$premier" != "1" ]; }; then
    if [ "${1:-1}" -eq 1 ]; then
      journal "Compte traité comme non épuisé par défaut : sonde de quota indisponible ou illisible (cycle $cycle)."
    fi
    return
  fi
  epuise="$premier"
  epoch_reset=$(printf '%s\n' "$verdict" | awk '{print $2}')
  case "$epoch_reset" in
    ''|*[!0-9]*) epoch_reset='-' ;;
  esac
}

pid_veilleur=""
pid_claude=""
pid_dodo=""
pid_surveille_sommeil=""

demarrer_veilleur() {
  # Sous --sans-veilleur, ne lance jamais rien : comportement réactif d'avant,
  # à l'identique.
  [ "$sans_veilleur" -eq 1 ] && return 0
  "$VEILLEUR" "$cible" --seuil "$seuil_alerte" --intervalle "$intervalle_veille" \
    >/dev/null 2>&1 &
  pid_veilleur=$!
}

arreter_veilleur() {
  # Un veilleur déjà mort (jamais démarré, ou terminé de lui-même entre
  # temps) est toléré sans erreur : on vérifie son PID avant de le tuer.
  #
  # Appelée aussi bien après un cycle normal (claude terminé) que depuis le
  # trap EXIT/INT/TERM : dans ce second cas, claude peut encore tourner (en
  # arrière-plan, voir plus bas pourquoi), et le laisser filer sans lui le
  # transformerait en orphelin au même titre que le veilleur — le risque
  # principal de cette fonctionnalité. Sur une interruption (INT/TERM) reçue
  # PENDANT que claude tourne encore, bash ne traite les traps qu'aux
  # limites de commande : un `wait` sur un job en arrière-plan est
  # interruptible, contrairement à l'exécution d'une commande au premier
  # plan qui retarderait ce nettoyage jusqu'à son terme (donc indéfiniment,
  # si ce terme n'arrive jamais). C'est pour ça que claude est lancé en
  # arrière-plan puis attendu via `wait`.
  # pkill -P d'abord : tuer seulement le veilleur laisserait orphelin
  # l'enfant qu'il est peut-être en train d'attendre (son propre sommeil
  # entre deux tours) — un parent tué ne tue pas ses enfants de lui-même.
  if [ -n "$pid_veilleur" ] && kill -0 "$pid_veilleur" 2>/dev/null; then
    pkill -P "$pid_veilleur" 2>/dev/null || true
    kill "$pid_veilleur" 2>/dev/null || true
    wait "$pid_veilleur" 2>/dev/null || true
  fi
  pid_veilleur=""
  rm -f "$cible/.autopilot/watch.pid" 2>/dev/null || true
  if [ -n "$pid_claude" ] && kill -0 "$pid_claude" 2>/dev/null; then
    pkill -P "$pid_claude" 2>/dev/null || true
    kill "$pid_claude" 2>/dev/null || true
    wait "$pid_claude" 2>/dev/null || true
  fi
  pid_claude=""
  if [ -n "$pid_dodo" ] && kill -0 "$pid_dodo" 2>/dev/null; then
    kill "$pid_dodo" 2>/dev/null || true
    wait "$pid_dodo" 2>/dev/null || true
  fi
  pid_dodo=""
  if [ -n "$pid_surveille_sommeil" ] && kill -0 "$pid_surveille_sommeil" 2>/dev/null; then
    kill "$pid_surveille_sommeil" 2>/dev/null || true
    wait "$pid_surveille_sommeil" 2>/dev/null || true
  fi
  pid_surveille_sommeil=""
  liberer_verrou
}

trap 'arreter_veilleur' EXIT
trap 'arreter_veilleur; exit 130' INT
trap 'arreter_veilleur; exit 143' TERM

empreinte_etat() {
  # « phase|tache|HEAD git|lignes du ledger » du moment. phase et tache ne
  # suffisent pas : une tâche longue traverse plusieurs cycles sans changer
  # de nom, et un run qui commite ou consigne au ledger progresse vraiment
  # même si ces deux champs restent immobiles. Le HEAD git tolère l'absence
  # de dépôt ou de commit (chaîne vide), et le compte de lignes tolère un
  # LEDGER.md absent (zéro) : ni l'un ni l'autre ne doit faire échouer la
  # fonction, qui doit toujours rendre une empreinte comparable.
  p=$(bash "$ETAT" get "$cible" phase 2>/dev/null || true)
  t=$(bash "$ETAT" get "$cible" tache 2>/dev/null || true)
  tete=$(cd "$cible" 2>/dev/null && git rev-parse HEAD 2>/dev/null || true)
  lignes=$(wc -l < "$cible/.autopilot/LEDGER.md" 2>/dev/null || true)
  printf '%s|%s|%s|%s' "$p" "$t" "$tete" "${lignes:-0}"
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
  # En arrière-plan puis attendu via `wait`, jamais au premier plan : un
  # sommeil de plusieurs jours (ATTENTE_MAX) exécuté au premier plan
  # rendrait le superviseur sourd à INT/TERM jusqu'à son terme naturel — le
  # même principe que pour claude (voir arreter_veilleur), avec un enjeu
  # bien plus grand ici puisque ce sommeil peut durer jusqu'à 8 jours.
  "$DORMIR" "$duree" &
  pid_dodo=$!
  # Second garde-fou, indépendant des signaux : rien ne prévient le
  # superviseur si, PENDANT ce sommeil, le dossier cible disparaît, la
  # phase passe à `bloque`, ou STATE.json devient illisible (pas de
  # notification du système de fichiers en bash pur, et la sonde ne
  # regarde jamais ces trois choses-là). Ce surveillant revérifie donc
  # périodiquement les trois et coupe le sommeil dès que l'une survient,
  # au lieu de laisser le superviseur dormir jusqu'au bout d'une attente
  # qui peut durer jusqu'à 8 jours sur un run déjà arrêté par ailleurs.
  # Une fois le sommeil coupé, c'est le contrôle habituel en haut de la
  # boucle principale qui tranche la suite exacte (code 2 avec sa ligne de
  # ledger pour un état illisible, code 3 sans relancer claude pour
  # `bloque`) : ce surveillant n'a besoin de rien décider lui-même, juste
  # de rendre la main plus tôt. Il se termine de lui-même dès que le
  # sommeil principal se termine (kill -0 sur pid_dodo échoue alors), sans
  # jamais dormir plus de VERIF_DOSSIER_INTERVALLE secondes à la fois.
  (
    while kill -0 "$pid_dodo" 2>/dev/null; do
      [ -d "$cible" ] || { kill "$pid_dodo" 2>/dev/null; exit 0; }
      phase_surveillee=$(bash "$ETAT" get "$cible" phase 2>/dev/null)
      code_phase_surveillee=$?
      if [ "$code_phase_surveillee" -eq "$CODE_ETAT_ILLISIBLE" ] ||
         [ "$phase_surveillee" = "bloque" ]; then
        kill "$pid_dodo" 2>/dev/null
        exit 0
      fi
      "$VERIF_DOSSIER" "$VERIF_DOSSIER_INTERVALLE" 2>/dev/null || exit 0
    done
  ) &
  pid_surveille_sommeil=$!
  wait "$pid_dodo" 2>/dev/null
  pid_dodo=""
  kill "$pid_surveille_sommeil" 2>/dev/null || true
  wait "$pid_surveille_sommeil" 2>/dev/null || true
  pid_surveille_sommeil=""
}

cycle=0
sans_progres=0
veille_signalee=0
while [ "$cycle" -lt "$max_cycles" ]; do
  if [ ! -d "$cible" ]; then
    printf 'le dossier a disparu en cours de route : %s\n' "$cible" >&2
    exit 2
  fi

  bash "$ETAT" "done" "$cible"
  code_etat=$?
  if [ "$code_etat" -eq 0 ]; then
    journal "Travail terminé, le superviseur s'arrête."
    exit 0
  fi
  # « Pas terminé » et « illisible » ne se ressemblent que de loin : sur un
  # STATE.json tronqué, relancer claude cent fois ne répare rien et n'écrit
  # pas une ligne. On s'arrête, et on le dit.
  if [ "$code_etat" -eq "$CODE_ETAT_ILLISIBLE" ]; then
    journal "État illisible (STATE.json tronqué ou corrompu) : arrêt du superviseur, aucune reprise automatique n'est possible."
    printf 'état illisible : %s/.autopilot/STATE.json\n' "$cible" >&2
    exit 2
  fi

  phase=$(bash "$ETAT" get "$cible" phase 2>/dev/null || true)
  if [ "$phase" = "bloque" ]; then
    journal "Blocage signalé par la skill (phase bloque) : décision humaine requise, le superviseur s'arrête."
    exit 3
  fi

  # Le veilleur a laissé un signal d'alerte (seuil franchi PENDANT la
  # dernière session, entre deux tâches) : on attend la réinitialisation du
  # quota MAINTENANT, même si la sonde ne dit pas encore « épuisé ». Sans ce
  # garde-fou, la skill se serait arrêtée proprement à 90 % et le
  # superviseur l'aurait relancée aussitôt (ou après la pause d'erreur
  # ordinaire de 30 s), annulant tout le bénéfice de s'être arrêtée tôt. Ce
  # n'est pas un cycle : aucun appel à claude n'a eu lieu, le compteur de
  # cycles n'avance pas.
  if [ "$sans_veilleur" -eq 0 ] && [ -f "$cible/.autopilot/QUOTA_ALERTE" ]; then
    sonde_quota 1
    secondes=$(attente "$epoch_reset")
    dormir_avec_budget "$secondes" \
      "Alerte de quota (veilleur) : attente de $secondes s avant de relancer (seuil d'alerte franchi, cycle $cycle)."
    rm -f "$cible/.autopilot/QUOTA_ALERTE"
    continue
  fi

  # Piège 2, la collision, pièce centrale : un battement de coeur récent
  # signifie qu'une session `claude -p` travaille déjà sur ce dossier
  # (lancée directement, hors de ce superviseur — sinon on serait en train
  # de l'attendre via `wait`, pas ici). La lancer une deuxième fois en
  # parallèle produirait des éditions concurrentes, des commits en double,
  # un état corrompu. On attend que le battement devienne périmé, sans
  # consommer ni cycle ni budget d'attente : ce n'est pas une attente de
  # quota, c'est une veille. L'absence du fichier (jamais écrit, ou déjà
  # périmé) est traitée exactement comme un contenu illisible : personne ne
  # travaille, on peut lancer claude.
  frais=0
  if [ -f "$cible/.autopilot/HEARTBEAT" ]; then
    battement=$(cat "$cible/.autopilot/HEARTBEAT" 2>/dev/null || true)
    case "$battement" in
      ''|*[!0-9]*) frais=0 ;;
      *)
        maintenant=$(date +%s)
        age=$(( maintenant - battement ))
        if [ "$age" -ge 0 ] && [ "$age" -lt "$seuil_battement" ]; then
          frais=1
        fi
        ;;
    esac
  fi
  if [ "$frais" -eq 1 ]; then
    if [ "$veille_signalee" -eq 0 ]; then
      journal "Veille : battement de coeur récent (moins de ${seuil_battement}s), une session travaille déjà sur ce dossier ; le superviseur attend sans consommer de cycle ni de budget d'attente."
      veille_signalee=1
    fi
    "$DORMIR" "$VEILLE_BATTEMENT_PAS" &
    pid_dodo=$!
    wait "$pid_dodo" 2>/dev/null
    pid_dodo=""
    continue
  fi
  veille_signalee=0

  cycle=$((cycle + 1))
  bash "$ETAT" set "$cible" cycles "$cycle" 2>/dev/null || true

  if [ "$dry" -eq 1 ]; then
    printf 'cycle %d : lancerait %s\n' "$cycle" "$CLAUDE"
    continue
  fi

  avant=$(empreinte_etat)

  demarrer_veilleur

  # Sans --permission-mode explicite, `claude --print` refuse automatiquement
  # tout ce qui demanderait une permission : l'agent ne pourrait rien écrire.
  # Lancé en arrière-plan puis attendu via `wait` (et non exécuté au premier
  # plan) pour que INT/TERM restent traitables pendant que claude tourne :
  # voir le commentaire de arreter_veilleur.
  # AUTOPILOT_SUPERVISE=1 exporté au processus enfant : c'est le signal que
  # la skill lit à son démarrage pour ne jamais lancer son propre
  # superviseur (protection anti-récursion, voir plus haut et SKILL.md).
  ( cd "$cible" && AUTOPILOT_SUPERVISE=1 "$CLAUDE" -p --permission-mode "$mode_permission" "autopilot reprise" ) &
  pid_claude=$!
  wait "$pid_claude"
  code=$?
  pid_claude=""

  arreter_veilleur

  apres=$(empreinte_etat)

  if [ "$code" -eq 0 ]; then
    if [ "$apres" = "$avant" ]; then
      sans_progres=$((sans_progres + 1))
      journal "Cycle $cycle : claude a rendu 0 sans faire avancer l'état ($sans_progres/$max_sans_progres)."
      if [ "$sans_progres" -ge "$max_sans_progres" ]; then
        journal "Abandon : $sans_progres cycles consécutifs sans le moindre progrès (phase et tâche inchangées)."
        exit 4
      fi
    else
      sans_progres=0
      journal "Cycle $cycle : terminé en code 0, état avancé ($avant -> $apres)."
    fi
  fi

  if [ "$code" -ne 0 ]; then
    # Le code de sortie 7 reste un raccourci accepté : s'il arrive, on
    # attend sans même interroger la sonde. Pour tout autre code non nul,
    # c'est la sonde — et elle seule — qui décide si le compte est épuisé.
    if [ "$code" -eq "$CODE_QUOTA" ]; then
      sonde_quota 0   # on ne veut que l'heure de réveil, le verdict est acquis
      epuise=1
    else
      sonde_quota 1
    fi

    if [ "$epuise" -eq 1 ]; then
      secondes=$(attente "$epoch_reset")
      dormir_avec_budget "$secondes" "Attente de quota : $secondes s avant reprise (cycle $cycle)."
    else
      dormir_avec_budget "$PAUSE_ERREUR" \
        "claude a rendu le code $code au cycle $cycle, nouvelle tentative."
    fi
  fi
done

if [ -d "$cible" ] && bash "$ETAT" "done" "$cible" 2>/dev/null; then
  journal "Travail terminé au dernier cycle."
  exit 0
fi
journal "Plafond de $max_cycles cycles atteint sans achèvement."
exit 1
