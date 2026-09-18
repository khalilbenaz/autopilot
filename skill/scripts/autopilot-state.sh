#!/usr/bin/env bash
# État durable d'un run autopilot, sous <dossier>/.autopilot/.
set -uo pipefail

# Toute la chaîne de reprise repose sur ces chaînes, écrites à la main par un
# modèle : elles sont validées ici, jamais acceptées telles quelles. Une clé
# mal orthographiée créerait un champ fantôme à côté du vrai, et une phase
# inventée ferait relancer `claude` indéfiniment par le superviseur, puisque
# ce ne serait ni `termine` ni `bloque`.
CLES_LEGALES="mode demande phase tache spec plan branche worktree cycles"
PHASES_LEGALES="init conception plan execution revue verification termine bloque"

etat_dir() { printf '%s/.autopilot' "$1"; }

dans_la_liste() { # <valeur> <liste>
  for element in $2; do
    [ "$1" = "$element" ] && return 0
  done
  return 1
}

horodatage() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

ecrire_resume() {
  d=$(etat_dir "$1")
  python3 - "$d" <<'PY'
import json, sys, os

MSG = ("état illisible : %s n'est pas un JSON exploitable (fichier tronqué "
       "ou corrompu). Aucune reprise automatique n'est possible tant qu'il "
       "n'est pas réparé.\n")

def charger(chemin):
    try:
        with open(chemin, encoding="utf-8") as f:
            return json.load(f)
    except (ValueError, OSError):
        sys.stderr.write(MSG % chemin)
        sys.exit(5)

def ecrire(chemin, contenu):
    # Écriture atomique : fichier temporaire dans le MÊME dossier, puis
    # os.replace. json.dump(s, open(chemin, "w")) tronquait la cible avant
    # d'écrire, et une coupure au mauvais moment — précisément le scénario
    # « redémarrage » que la reprise doit couvrir — laissait un état
    # tronqué, donc un run irrécupérable.
    tmp = chemin + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(contenu)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, chemin)

d = sys.argv[1]
s = charger(os.path.join(d, "STATE.json"))
lignes = [
    "# Reprise autopilot", "",
    "Ce fichier est régénéré à chaque changement d'état. Il décrit où en est",
    "le travail et ce qui vient ensuite.", "",
    "| Élément | Valeur |", "|---|---|",
]
for k in ("mode", "phase", "tache", "branche", "worktree", "spec", "plan",
          "cycles"):
    v = s.get(k)
    lignes.append("| %s | %s |" % (k, v if v not in (None, "") else "—"))
lignes += ["", "## Demande", "", s.get("demande", "—"), "",
           "## Prochaine action", ""]
phase = s.get("phase", "")
# La phase nommée est la phase EN COURS, jamais celle qui vient d'être
# terminée : chaque ligne ci-dessous dit donc ce qu'il reste à faire DANS
# cette phase. Les numéros d'étape sont ceux de la table des phases de
# RESUMING.md, et un test compare les deux sources pour qu'elles ne
# puissent plus diverger.
suite = {
    "init": "Détecter le mode et amorcer le projet (étapes 0 puis 1 ou 1′).",
    "conception": "Mener la conception et écrire la spec "
                  "(étape 2, brainstorming).",
    "plan": "Écrire le plan en tâches de 2 à 5 minutes "
            "(étape 3, writing-plans).",
    "execution": "Reprendre à la tâche « %s » (étape 4, un sous-agent par "
                 "tâche)." % (s.get("tache") or "?"),
    "revue": "Demander la revue contre le plan, puis traiter les retours "
             "(étapes 6 et 7).",
    "verification": "Relancer les vérifications et coller leur sortie réelle "
                    "avant toute affirmation (étape 8).",
    "termine": "Rien : le travail est terminé (étape 9 faite).",
    "bloque": "Arrêté : une décision humaine est requise. Aucune reprise "
              "automatique n'aura lieu. Lire la ligne « Arrêt: » la plus "
              "récente dans LEDGER.md pour connaître la raison.",
}.get(phase, "Relire STATE.json pour situer la phase « %s »." % phase)
lignes.append(suite)
ecrire(os.path.join(d, "RESUME.md"), "\n".join(lignes) + "\n")
PY
}

cmd="${1:-}"; cible="${2:-}"

case "$cmd" in
  init)
    mode="${3:-inconnu}"; demande="${4:-}"; drapeau="${5:-}"
    d=$(etat_dir "$cible"); mkdir -p "$d"
    # Sans --force, un état déjà présent n'est jamais écrasé : init redevient
    # un no-op idempotent (code 0), pour ne jamais détruire un run en cours.
    if [ -f "$d/STATE.json" ] && [ "$drapeau" != "--force" ]; then
      [ -f "$d/LEDGER.md" ] || printf '# Journal autopilot\n\n' > "$d/LEDGER.md"
      printf -- '- %s — init ignoré : état déjà présent (utiliser --force pour réinitialiser)\n' \
        "$(horodatage)" >> "$d/LEDGER.md"
      ecrire_resume "$cible"
      printf '%s\n' "$d"
      exit 0
    fi
    deja_present=0
    [ -f "$d/STATE.json" ] && deja_present=1
    python3 - "$d" "$mode" "$demande" <<'PY'
import json, sys, os

MSG = ("état illisible : %s n'est pas un JSON exploitable (fichier tronqué "
       "ou corrompu). Aucune reprise automatique n'est possible tant qu'il "
       "n'est pas réparé.\n")

def charger(chemin):
    try:
        with open(chemin, encoding="utf-8") as f:
            return json.load(f)
    except (ValueError, OSError):
        sys.stderr.write(MSG % chemin)
        sys.exit(5)

def ecrire(chemin, contenu):
    # Écriture atomique : fichier temporaire dans le MÊME dossier, puis
    # os.replace. json.dump(s, open(chemin, "w")) tronquait la cible avant
    # d'écrire, et une coupure au mauvais moment — précisément le scénario
    # « redémarrage » que la reprise doit couvrir — laissait un état
    # tronqué, donc un run irrécupérable.
    tmp = chemin + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(contenu)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, chemin)

d, mode, demande = sys.argv[1], sys.argv[2], sys.argv[3]
etat = {"mode": mode, "demande": demande, "phase": "init",
        "tache": "", "spec": "", "plan": "", "branche": "", "worktree": "",
        "cycles": 0}
ecrire(os.path.join(d, "STATE.json"),
       json.dumps(etat, indent=2, ensure_ascii=False) + "\n")
PY
    # Le ledger n'est jamais tronqué : on ne crée l'en-tête que s'il n'existe
    # pas encore, sinon on se contente d'ajouter une ligne.
    [ -f "$d/LEDGER.md" ] || printf '# Journal autopilot\n\n' > "$d/LEDGER.md"
    if [ "$deja_present" -eq 1 ]; then
      printf -- '- %s — init --force : état réinitialisé (mode %s)\n' \
        "$(horodatage)" "$mode" >> "$d/LEDGER.md"
    else
      printf -- '- %s — démarré (mode %s)\n' "$(horodatage)" "$mode" >> "$d/LEDGER.md"
    fi
    ecrire_resume "$cible"
    printf '%s\n' "$d"
    ;;
  set)
    cle="${3:-}"; val="${4:-}"
    d=$(etat_dir "$cible")
    [ -f "$d/STATE.json" ] || { printf 'état absent : %s\n' "$d" >&2; exit 1; }
    if ! dans_la_liste "$cle" "$CLES_LEGALES"; then
      printf 'clé inconnue : « %s »\n' "$cle" >&2
      printf 'clés acceptées : %s\n' "$CLES_LEGALES" >&2
      exit 2
    fi
    if [ "$cle" = "phase" ] && ! dans_la_liste "$val" "$PHASES_LEGALES"; then
      printf 'phase inconnue : « %s »\n' "$val" >&2
      printf 'phases acceptées : %s\n' "$PHASES_LEGALES" >&2
      exit 2
    fi
    python3 - "$d" "$cle" "$val" <<'PY'
import json, sys, os

MSG = ("état illisible : %s n'est pas un JSON exploitable (fichier tronqué "
       "ou corrompu). Aucune reprise automatique n'est possible tant qu'il "
       "n'est pas réparé.\n")

def charger(chemin):
    try:
        with open(chemin, encoding="utf-8") as f:
            return json.load(f)
    except (ValueError, OSError):
        sys.stderr.write(MSG % chemin)
        sys.exit(5)

def ecrire(chemin, contenu):
    # Écriture atomique : fichier temporaire dans le MÊME dossier, puis
    # os.replace. json.dump(s, open(chemin, "w")) tronquait la cible avant
    # d'écrire, et une coupure au mauvais moment — précisément le scénario
    # « redémarrage » que la reprise doit couvrir — laissait un état
    # tronqué, donc un run irrécupérable.
    tmp = chemin + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(contenu)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, chemin)

d, cle, val = sys.argv[1], sys.argv[2], sys.argv[3]
chemin = os.path.join(d, "STATE.json")
etat = charger(chemin)
etat[cle] = int(val) if cle == "cycles" and val.isdigit() else val
ecrire(chemin, json.dumps(etat, indent=2, ensure_ascii=False) + "\n")
PY
    code=$?
    [ "$code" -eq 0 ] || exit "$code"
    ecrire_resume "$cible"
    ;;
  get)
    cle="${3:-}"
    d=$(etat_dir "$cible")
    [ -f "$d/STATE.json" ] || exit 1
    python3 - "$d" "$cle" <<'PY'
import json, sys, os

MSG = ("état illisible : %s n'est pas un JSON exploitable (fichier tronqué "
       "ou corrompu). Aucune reprise automatique n'est possible tant qu'il "
       "n'est pas réparé.\n")

def charger(chemin):
    try:
        with open(chemin, encoding="utf-8") as f:
            return json.load(f)
    except (ValueError, OSError):
        sys.stderr.write(MSG % chemin)
        sys.exit(5)

def ecrire(chemin, contenu):
    # Écriture atomique : fichier temporaire dans le MÊME dossier, puis
    # os.replace. json.dump(s, open(chemin, "w")) tronquait la cible avant
    # d'écrire, et une coupure au mauvais moment — précisément le scénario
    # « redémarrage » que la reprise doit couvrir — laissait un état
    # tronqué, donc un run irrécupérable.
    tmp = chemin + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(contenu)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, chemin)

d, cle = sys.argv[1], sys.argv[2]
etat = charger(os.path.join(d, "STATE.json"))
if cle not in etat or etat[cle] == "":
    sys.exit(1)
print(etat[cle])
PY
    ;;
  ledger)
    ligne="${3:-}"
    d=$(etat_dir "$cible")
    [ -d "$d" ] || { printf 'état absent : %s\n' "$d" >&2; exit 1; }
    printf -- '- %s — %s\n' "$(horodatage)" "$ligne" >> "$d/LEDGER.md"
    ;;
  done)
    d=$(etat_dir "$cible")
    [ -f "$d/STATE.json" ] || exit 1
    phase=$(python3 - "$d/STATE.json" <<'PY'
import json, sys, os

MSG = ("état illisible : %s n'est pas un JSON exploitable (fichier tronqué "
       "ou corrompu). Aucune reprise automatique n'est possible tant qu'il "
       "n'est pas réparé.\n")

def charger(chemin):
    try:
        with open(chemin, encoding="utf-8") as f:
            return json.load(f)
    except (ValueError, OSError):
        sys.stderr.write(MSG % chemin)
        sys.exit(5)

def ecrire(chemin, contenu):
    # Écriture atomique : fichier temporaire dans le MÊME dossier, puis
    # os.replace. json.dump(s, open(chemin, "w")) tronquait la cible avant
    # d'écrire, et une coupure au mauvais moment — précisément le scénario
    # « redémarrage » que la reprise doit couvrir — laissait un état
    # tronqué, donc un run irrécupérable.
    tmp = chemin + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(contenu)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, chemin)

print(charger(sys.argv[1]).get("phase", ""))
PY
)
    code=$?
    # 5 : état illisible — à distinguer de « pas terminé », pour que le
    # superviseur s'arrête au lieu de brûler ses cycles sur un état mort.
    [ "$code" -eq 0 ] || exit "$code"
    [ "$phase" = "termine" ]
    ;;
  *)
    printf 'usage : %s {init|set|get|ledger|done} <dossier> [args]\n' "$0" >&2
    exit 2
    ;;
esac
