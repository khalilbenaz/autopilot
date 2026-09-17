#!/usr/bin/env bash
# État durable d'un run autopilot, sous <dossier>/.autopilot/.
set -uo pipefail

etat_dir() { printf '%s/.autopilot' "$1"; }

horodatage() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

ecrire_resume() {
  d=$(etat_dir "$1")
  python3 - "$d" <<'PY'
import json, sys, os
d = sys.argv[1]
s = json.load(open(os.path.join(d, "STATE.json")))
lignes = [
    "# Reprise autopilot", "",
    "Ce fichier est régénéré à chaque changement d'état. Il décrit où en est",
    "le travail et ce qui vient ensuite.", "",
    "| Élément | Valeur |", "|---|---|",
]
for k in ("mode", "phase", "tache", "branche", "spec", "plan", "cycles"):
    lignes.append("| %s | %s |" % (k, s.get(k) or "—"))
lignes += ["", "## Demande", "", s.get("demande", "—"), "",
           "## Prochaine action", ""]
phase = s.get("phase", "")
suite = {
    "init": "Détecter le mode et amorcer le projet.",
    "conception": "Écrire la spec, puis le plan.",
    "plan": "Lancer l'exécution tâche par tâche.",
    "execution": "Reprendre à la tâche « %s »." % (s.get("tache") or "?"),
    "revue": "Traiter les retours de revue.",
    "verification": "Relancer les tests et relire leur sortie.",
    "termine": "Rien : le travail est terminé.",
}.get(phase, "Relire STATE.json pour situer la phase « %s »." % phase)
lignes.append(suite)
open(os.path.join(d, "RESUME.md"), "w").write("\n".join(lignes) + "\n")
PY
}

cmd="${1:-}"; cible="${2:-}"

case "$cmd" in
  init)
    mode="${3:-inconnu}"; demande="${4:-}"
    d=$(etat_dir "$cible"); mkdir -p "$d"
    python3 - "$d" "$mode" "$demande" <<'PY'
import json, sys, os
d, mode, demande = sys.argv[1], sys.argv[2], sys.argv[3]
etat = {"mode": mode, "demande": demande, "phase": "init",
        "tache": "", "spec": "", "plan": "", "branche": "", "cycles": 0}
json.dump(etat, open(os.path.join(d, "STATE.json"), "w"),
          indent=2, ensure_ascii=False)
PY
    printf '# Journal autopilot\n\nDémarré le %s — mode %s.\n\n' \
      "$(horodatage)" "$mode" > "$d/LEDGER.md"
    ecrire_resume "$cible"
    printf '%s\n' "$d"
    ;;
  set)
    cle="${3:-}"; val="${4:-}"
    d=$(etat_dir "$cible")
    [ -f "$d/STATE.json" ] || { printf 'état absent : %s\n' "$d" >&2; exit 1; }
    python3 - "$d" "$cle" "$val" <<'PY'
import json, sys, os
d, cle, val = sys.argv[1], sys.argv[2], sys.argv[3]
p = os.path.join(d, "STATE.json")
s = json.load(open(p))
s[cle] = int(val) if cle == "cycles" and val.isdigit() else val
json.dump(s, open(p, "w"), indent=2, ensure_ascii=False)
PY
    ecrire_resume "$cible"
    ;;
  get)
    cle="${3:-}"
    d=$(etat_dir "$cible")
    [ -f "$d/STATE.json" ] || exit 1
    python3 - "$d" "$cle" <<'PY'
import json, sys, os
d, cle = sys.argv[1], sys.argv[2]
s = json.load(open(os.path.join(d, "STATE.json")))
if cle not in s or s[cle] == "":
    sys.exit(1)
print(s[cle])
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
    phase=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["phase"])' \
      "$d/STATE.json" 2>/dev/null) || exit 1
    [ "$phase" = "termine" ]
    ;;
  *)
    printf 'usage : %s {init|set|get|ledger|done} <dossier> [args]\n' "$0" >&2
    exit 2
    ;;
esac
