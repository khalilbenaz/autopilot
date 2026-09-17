# autopilot — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer une skill `autopilot` qui mène une demande jusqu'à une branche locale testée, sans interruption, et qui reprend après épuisement du quota.

**Architecture:** Quatre scripts bash autonomes et testables (quota, état, détection de mode, superviseur), plus un `SKILL.md` qui orchestre les skills superpowers existantes. Aucune méthode de superpowers n'est recopiée : autopilot délègue.

**Tech Stack:** bash 3.2 (celui de macOS), `jq`, `python3`, `curl`, `git`, `security` (trousseau). Aucune dépendance à installer.

**Spec:** `docs/superpowers/specs/2026-09-17-autopilot-design.md`

## Global Constraints

- Compatible **bash 3.2** : pas de tableaux associatifs, pas de `declare -n`, pas de `${x^^}`.
- `shellcheck` sans aucun avertissement sur tous les `.sh`.
- Aucune dépendance externe à installer : seulement `jq`, `python3`, `curl`, `git`, `security`.
- Tout texte destiné à l'utilisateur est en **français**.
- Chaque script est exécutable seul et rend un code de sortie explicite.
- Aucun script n'écrit hors du répertoire de travail qu'on lui passe.
- Endpoint quota : `https://api.anthropic.com/api/oauth/usage`, en-tête `anthropic-beta: oauth-2025-04-20`, jeton au trousseau sous le service `Claude Code-credentials`, champ `claudeAiOauth.accessToken`.
- Fenêtres de quota possibles : `five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet`. **Elles peuvent valoir `null`** et doivent alors être ignorées sans erreur.
- Les tests tournent via `./tests/run.sh` et ne touchent jamais au réseau : les réponses de l'API sont des fixtures.

---

### Task 1: Sonde de quota

**Files:**
- Create: `skill/scripts/autopilot-quota.sh`
- Test: `tests/test_quota.sh`

**Interfaces:**
- Consumes: rien
- Produces:
  - `autopilot-quota.sh verdict [fichier-json]` → écrit `<épuisé:0|1> <epoch-reset|-> <fenêtre> <pourcentage>`, code 0. Sans argument, interroge l'API ; avec un fichier, le lit (c'est le point d'entrée des tests).
  - `autopilot-quota.sh reset-epoch [fichier-json]` → écrit l'epoch de reset de la fenêtre la plus consommée, ou `-` si inconnue.
  - Seuil d'épuisement : `utilization >= 95`.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `tests/test_quota.sh` :

```bash
Q="$ROOT/skill/scripts/autopilot-quota.sh"
FIX="$ROOT/tests/fixtures"

test_quota_compte_frais() {
  mkdir -p "$FIX"
  cat > "$FIX/frais.json" <<'J'
{"five_hour":{"utilization":14.0,"resets_at":"2026-09-18T01:40:00.944781+00:00"},
 "seven_day":{"utilization":29.0,"resets_at":"2026-09-22T14:00:00.944796+00:00"},
 "seven_day_opus":null,"seven_day_sonnet":null}
J
  out=$(bash "$Q" verdict "$FIX/frais.json")
  [ "${out%% *}" = "0" ]; assert "compte frais : non épuisé" $?
  case "$out" in *seven_day*) r=0;; *) r=1;; esac
  assert "compte frais : la fenêtre la plus consommée est seven_day" $r
}

test_quota_compte_epuise() {
  cat > "$FIX/epuise.json" <<'J'
{"five_hour":{"utilization":99.5,"resets_at":"2026-09-18T01:40:00+00:00"},
 "seven_day":{"utilization":30.0,"resets_at":"2026-09-22T14:00:00+00:00"},
 "seven_day_opus":null,"seven_day_sonnet":null}
J
  out=$(bash "$Q" verdict "$FIX/epuise.json")
  [ "${out%% *}" = "1" ]; assert "compte épuisé : détecté" $?
  epoch=$(bash "$Q" reset-epoch "$FIX/epuise.json")
  [ "$epoch" = "1789695600" ]; assert "epoch de reset calculé depuis l'ISO 8601" $?
}

test_quota_fenetres_nulles() {
  cat > "$FIX/nulles.json" <<'J'
{"five_hour":null,"seven_day":null,"seven_day_opus":null,"seven_day_sonnet":null}
J
  bash "$Q" verdict "$FIX/nulles.json" >/dev/null 2>&1
  assert "toutes fenêtres nulles : pas d'erreur" $?
}

test_quota_replie_sur_limits() {
  cat > "$FIX/limits.json" <<'J'
{"limits":[{"kind":"session","percent":97,"resets_at":"2026-09-18T01:40:00+00:00"}]}
J
  out=$(bash "$Q" verdict "$FIX/limits.json")
  [ "${out%% *}" = "1" ]; assert "repli sur le tableau limits[]" $?
}

test_quota_json_invalide() {
  echo 'pas du json' > "$FIX/casse.json"
  bash "$Q" verdict "$FIX/casse.json" >/dev/null 2>&1
  [ $? -ne 0 ]; assert "json invalide : code de sortie non nul" $?
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

Run: `./tests/run.sh`
Expected: FAIL — `skill/scripts/autopilot-quota.sh` n'existe pas.

- [ ] **Step 3: Écrire l'implémentation minimale**

Créer `skill/scripts/autopilot-quota.sh` :

```bash
#!/usr/bin/env bash
# Sonde le quota Claude annoncé par Anthropic.
# verdict [fichier]      -> "<épuisé:0|1> <epoch|-> <fenêtre> <pourcentage>"
# reset-epoch [fichier]  -> epoch de la fenêtre la plus consommée, ou "-"
# Sans fichier, interroge l'API ; avec, lit le fichier (tests).
set -uo pipefail

USAGE_URL="https://api.anthropic.com/api/oauth/usage"
USAGE_BETA="oauth-2025-04-20"
KEYCHAIN_SERVICE="Claude Code-credentials"
SEUIL=95

jeton() {
  security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null \
    | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(1)
o=d.get("claudeAiOauth") or d
t=o.get("accessToken","")
if not t: sys.exit(1)
print(t)' 2>/dev/null
}

releve() {
  if [ $# -ge 1 ] && [ -n "$1" ]; then cat "$1"; return; fi
  tok=$(jeton) || return 1
  [ -n "$tok" ] || return 1
  curl -s --max-time 15 "$USAGE_URL" \
    -H "Authorization: Bearer $tok" \
    -H "anthropic-beta: $USAGE_BETA" \
    -H "User-Agent: autopilot (local)"
}

# Lit le relevé sur stdin, écrit "épuisé epoch fenêtre pourcentage".
analyse() {
  SEUIL="$SEUIL" python3 -c '
import sys, json, os, datetime

def epoch(v):
    if isinstance(v, (int, float)):
        return float(v) if v > 1e9 else None
    if not isinstance(v, str) or not v:
        return None
    try:
        return datetime.datetime.fromisoformat(
            v.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not isinstance(d, dict):
    sys.exit(1)

fenetres = []
for k in ("five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"):
    w = d.get(k)
    if isinstance(w, dict) and w.get("utilization") is not None:
        fenetres.append((k, w["utilization"], epoch(w.get("resets_at"))))
for lim in d.get("limits") or []:
    if isinstance(lim, dict) and lim.get("percent") is not None:
        fenetres.append((lim.get("kind") or "limite", lim["percent"],
                         epoch(lim.get("resets_at"))))

pire = (-1.0, None, "aucune")
for nom, pct, quand in fenetres:
    try:
        pct = float(pct)
    except (TypeError, ValueError):
        continue
    if pct > pire[0]:
        pire = (pct, quand, nom)

pct, quand, nom = pire
if pct < 0:
    print("0 - aucune 0")
    sys.exit(0)
seuil = float(os.environ["SEUIL"])
print("%d %s %s %g" % (1 if pct >= seuil else 0,
                       "%d" % quand if quand else "-", nom, pct))
'
}

cmd="${1:-verdict}"
src="${2:-}"

case "$cmd" in
  verdict)
    releve "$src" | analyse
    ;;
  reset-epoch)
    out=$(releve "$src" | analyse) || exit 1
    printf '%s\n' "$out" | awk '{print $2}'
    ;;
  *)
    printf 'usage: %s {verdict|reset-epoch} [fichier.json]\n' "$0" >&2
    exit 2
    ;;
esac
```

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

Run: `./tests/run.sh`
Expected: les 5 assertions de `test_quota.sh` passent.

- [ ] **Step 5: shellcheck**

Run: `shellcheck skill/scripts/autopilot-quota.sh`
Expected: aucune sortie.

- [ ] **Step 6: Commit**

```bash
git add skill/scripts/autopilot-quota.sh tests/test_quota.sh tests/fixtures
git commit -m "feat(quota): sonde du quota Claude et calcul de l'heure de reset"
```

---

### Task 2: État et reprise

**Files:**
- Create: `skill/scripts/autopilot-state.sh`
- Test: `tests/test_state.sh`

**Interfaces:**
- Consumes: rien
- Produces:
  - `autopilot-state.sh init <dossier> <mode> <demande>` → crée `<dossier>/.autopilot/` avec `STATE.json`, `LEDGER.md`, `RESUME.md`
  - `autopilot-state.sh set <dossier> <clé> <valeur>` → met à jour une clé de `STATE.json` et régénère `RESUME.md`
  - `autopilot-state.sh get <dossier> <clé>` → écrit la valeur, code 1 si absente
  - `autopilot-state.sh ledger <dossier> <ligne>` → ajoute une ligne horodatée à `LEDGER.md`
  - `autopilot-state.sh done <dossier>` → code 0 si `phase` vaut `termine`, sinon 1
  - Clés de `STATE.json` : `mode`, `demande`, `phase`, `tache`, `spec`, `plan`, `branche`, `cycles`

- [ ] **Step 1: Écrire le test qui échoue**

Créer `tests/test_state.sh` :

```bash
S="$ROOT/skill/scripts/autopilot-state.sh"

test_state_init_cree_les_fichiers() {
  d=$(mktemp -d)
  bash "$S" init "$d" creation "faire un truc" >/dev/null
  [ -f "$d/.autopilot/STATE.json" ]; assert "init crée STATE.json" $?
  [ -f "$d/.autopilot/LEDGER.md" ]; assert "init crée LEDGER.md" $?
  [ -f "$d/.autopilot/RESUME.md" ]; assert "init crée RESUME.md" $?
  [ "$(bash "$S" get "$d" mode)" = "creation" ]; assert "init enregistre le mode" $?
  rm -rf "$d"
}

test_state_set_et_get() {
  d=$(mktemp -d)
  bash "$S" init "$d" amelioration "autre truc" >/dev/null
  bash "$S" set "$d" phase execution
  [ "$(bash "$S" get "$d" phase)" = "execution" ]; assert "set puis get rend la valeur" $?
  bash "$S" get "$d" inexistante >/dev/null 2>&1
  [ $? -ne 0 ]; assert "get sur clé absente : code non nul" $?
  rm -rf "$d"
}

test_state_resume_reflete_l_etat() {
  d=$(mktemp -d)
  bash "$S" init "$d" creation "bâtir X" >/dev/null
  bash "$S" set "$d" tache "Task 3"
  grep -q "Task 3" "$d/.autopilot/RESUME.md"
  assert "RESUME.md est régénéré à chaque set" $?
  rm -rf "$d"
}

test_state_ledger_append_only() {
  d=$(mktemp -d)
  bash "$S" init "$d" creation "x" >/dev/null
  bash "$S" ledger "$d" "Ruling: A — parce que — pas cher"
  bash "$S" ledger "$d" "Ruling: B — parce que — pas cher"
  n=$(grep -c "Ruling:" "$d/.autopilot/LEDGER.md")
  [ "$n" -eq 2 ]; assert "le ledger accumule sans écraser" $?
  rm -rf "$d"
}

test_state_done() {
  d=$(mktemp -d)
  bash "$S" init "$d" creation "x" >/dev/null
  bash "$S" done "$d"; [ $? -ne 0 ]; assert "pas terminé au départ" $?
  bash "$S" set "$d" phase termine
  bash "$S" done "$d"; assert "terminé une fois la phase à 'termine'" $?
  rm -rf "$d"
}

test_state_survit_a_une_relecture() {
  d=$(mktemp -d)
  bash "$S" init "$d" creation "reprise" >/dev/null
  bash "$S" set "$d" tache "Task 4"
  # simulation d'une nouvelle session : rien en mémoire, tout sur disque
  [ "$(bash "$S" get "$d" tache)" = "Task 4" ]
  assert "l'état se relit depuis le disque seul" $?
  rm -rf "$d"
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

Run: `./tests/run.sh`
Expected: FAIL — `autopilot-state.sh` n'existe pas.

- [ ] **Step 3: Écrire l'implémentation minimale**

Créer `skill/scripts/autopilot-state.sh` :

```bash
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
    [ -f "$d/STATE.json" ] || { printf 'état absent: %s\n' "$d" >&2; exit 1; }
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
    [ -d "$d" ] || { printf 'état absent: %s\n' "$d" >&2; exit 1; }
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
    printf 'usage: %s {init|set|get|ledger|done} <dossier> [args]\n' "$0" >&2
    exit 2
    ;;
esac
```

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

Run: `./tests/run.sh`
Expected: les assertions de `test_state.sh` passent.

- [ ] **Step 5: shellcheck**

Run: `shellcheck skill/scripts/autopilot-state.sh`
Expected: aucune sortie.

- [ ] **Step 6: Commit**

```bash
git add skill/scripts/autopilot-state.sh tests/test_state.sh
git commit -m "feat(state): état durable, journal et document de reprise"
```

---

### Task 3: Détection du mode

**Files:**
- Create: `skill/scripts/autopilot-detect.sh`
- Test: `tests/test_detect.sh`

**Interfaces:**
- Consumes: rien
- Produces:
  - `autopilot-detect.sh <dossier>` → écrit `creation` ou `amelioration`, code 0
  - Règle : dossier absent, vide, ou sans dépôt git **et** sans fichier source → `creation`. Sinon → `amelioration`.
  - Un dossier contenant uniquement des fichiers cachés compte comme vide.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `tests/test_detect.sh` :

```bash
D="$ROOT/skill/scripts/autopilot-detect.sh"

test_detect_dossier_absent() {
  [ "$(bash "$D" /tmp/autopilot-inexistant-$$)" = "creation" ]
  assert "dossier absent : création" $?
}

test_detect_dossier_vide() {
  d=$(mktemp -d)
  [ "$(bash "$D" "$d")" = "creation" ]; assert "dossier vide : création" $?
  rm -rf "$d"
}

test_detect_seulement_caches() {
  d=$(mktemp -d); touch "$d/.DS_Store"
  [ "$(bash "$D" "$d")" = "creation" ]; assert "fichiers cachés seuls : création" $?
  rm -rf "$d"
}

test_detect_repo_avec_code() {
  d=$(mktemp -d); (cd "$d" && git init -q); echo 'print(1)' > "$d/main.py"
  [ "$(bash "$D" "$d")" = "amelioration" ]; assert "dépôt avec code : amélioration" $?
  rm -rf "$d"
}

test_detect_code_sans_git() {
  d=$(mktemp -d); echo 'print(1)' > "$d/main.py"
  [ "$(bash "$D" "$d")" = "amelioration" ]; assert "code sans dépôt : amélioration" $?
  rm -rf "$d"
}

test_detect_repo_vide() {
  d=$(mktemp -d); (cd "$d" && git init -q)
  [ "$(bash "$D" "$d")" = "creation" ]; assert "dépôt sans code : création" $?
  rm -rf "$d"
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

Run: `./tests/run.sh`
Expected: FAIL — `autopilot-detect.sh` n'existe pas.

- [ ] **Step 3: Écrire l'implémentation minimale**

Créer `skill/scripts/autopilot-detect.sh` :

```bash
#!/usr/bin/env bash
# Décide du mode de travail : creation ou amelioration.
set -uo pipefail

cible="${1:-.}"

if [ ! -d "$cible" ]; then
  printf 'creation\n'; exit 0
fi

# Un fichier source visible suffit à parler d'amélioration ; les fichiers
# cachés (.DS_Store, .git, .gitignore) ne comptent pas comme du contenu.
visibles=$(find "$cible" -maxdepth 2 -type f \
  -not -path '*/.*' -not -name '.*' 2>/dev/null | head -1)

if [ -n "$visibles" ]; then
  printf 'amelioration\n'
else
  printf 'creation\n'
fi
```

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

Run: `./tests/run.sh`
Expected: les 6 assertions de `test_detect.sh` passent.

- [ ] **Step 5: shellcheck**

Run: `shellcheck skill/scripts/autopilot-detect.sh`
Expected: aucune sortie.

- [ ] **Step 6: Commit**

```bash
git add skill/scripts/autopilot-detect.sh tests/test_detect.sh
git commit -m "feat(detect): détection automatique du mode de travail"
```

---

### Task 4: Superviseur

**Files:**
- Create: `skill/scripts/autopilot-supervisor.sh`
- Test: `tests/test_supervisor.sh`

**Interfaces:**
- Consumes: `autopilot-state.sh` (done, ledger, set, get), `autopilot-quota.sh` (reset-epoch)
- Produces:
  - `autopilot-supervisor.sh <dossier> [--max-cycles N] [--dry-run]`
  - Variables d'environnement reconnues, pour les tests : `AUTOPILOT_CLAUDE` (binaire à lancer, défaut `claude`), `AUTOPILOT_SLEEP` (commande d'attente, défaut `sleep`), `AUTOPILOT_QUOTA` (chemin de la sonde).
  - Codes de sortie : `0` travail terminé, `1` plafond de cycles atteint, `2` dossier ou état absent.
  - Sortie de `claude` valant `7` → interprétée comme quota épuisé.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `tests/test_supervisor.sh` :

```bash
SUP="$ROOT/skill/scripts/autopilot-supervisor.sh"
ST="$ROOT/skill/scripts/autopilot-state.sh"

# Fabrique un faux binaire claude au comportement scripté.
faux_claude() { # <chemin> <suite de codes séparés par des espaces>
  cat > "$1" <<EOS
#!/usr/bin/env bash
compteur="\$(dirname "\$0")/compteur"
n=\$(cat "\$compteur" 2>/dev/null || echo 0)
n=\$((n+1)); echo "\$n" > "\$compteur"
codes=($2)
code=\${codes[\$((n-1))]:-0}
echo "faux claude, appel \$n, code \$code"
exit "\$code"
EOS
  chmod +x "$1"
}

test_supervisor_sort_si_deja_termine() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  bash "$ST" set "$d" phase termine
  faux_claude "$bin/claude" "0"
  AUTOPILOT_CLAUDE="$bin/claude" bash "$SUP" "$d" >/dev/null 2>&1
  assert "sort en 0 si l'état est déjà terminé" $?
  [ ! -f "$bin/compteur" ]; assert "ne lance pas claude si terminé" $?
  rm -rf "$d" "$bin"
}

test_supervisor_relance_puis_termine() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  # claude rend 0 et marque l'état terminé au premier appel
  cat > "$bin/claude" <<EOS
#!/usr/bin/env bash
bash "$ST" set "$d" phase termine
exit 0
EOS
  chmod +x "$bin/claude"
  AUTOPILOT_CLAUDE="$bin/claude" bash "$SUP" "$d" >/dev/null 2>&1
  assert "s'arrête dès que claude marque l'état terminé" $?
  rm -rf "$d" "$bin"
}

test_supervisor_plafond_de_cycles() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  faux_claude "$bin/claude" "0 0 0 0 0"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true \
    bash "$SUP" "$d" --max-cycles 3 >/dev/null 2>&1
  [ $? -eq 1 ]; assert "rend 1 quand le plafond de cycles est atteint" $?
  n=$(cat "$bin/compteur"); [ "$n" -eq 3 ]
  assert "ne dépasse pas le plafond de cycles" $?
  rm -rf "$d" "$bin"
}

test_supervisor_attend_sur_quota() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  faux_claude "$bin/claude" "7 0"
  cat > "$bin/sleep" <<'EOS'
#!/usr/bin/env bash
echo "DORT $1" >> "$(dirname "$0")/dodo"
EOS
  chmod +x "$bin/sleep"
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
[ "$1" = "reset-epoch" ] && echo "-"
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP="$bin/sleep" \
    AUTOPILOT_QUOTA="$bin/quota" bash "$SUP" "$d" --max-cycles 2 >/dev/null 2>&1
  [ -f "$bin/dodo" ]; assert "dort après une sortie sur quota épuisé" $?
  grep -q "quota" "$d/.autopilot/LEDGER.md"
  assert "consigne l'attente dans le ledger" $?
  rm -rf "$d" "$bin"
}

test_supervisor_dossier_absent() {
  bash "$SUP" /tmp/autopilot-absent-$$ >/dev/null 2>&1
  [ $? -eq 2 ]; assert "rend 2 si le dossier n'existe pas" $?
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

Run: `./tests/run.sh`
Expected: FAIL — `autopilot-supervisor.sh` n'existe pas.

- [ ] **Step 3: Écrire l'implémentation minimale**

Créer `skill/scripts/autopilot-supervisor.sh` :

```bash
#!/usr/bin/env bash
# Relance autopilot jusqu'à ce que le travail soit terminé, en attendant la
# réinitialisation du quota quand elle bloque.
set -uo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETAT="$ICI/autopilot-state.sh"
QUOTA="${AUTOPILOT_QUOTA:-$ICI/autopilot-quota.sh}"
CLAUDE="${AUTOPILOT_CLAUDE:-claude}"
DORMIR="${AUTOPILOT_SLEEP:-sleep}"

CODE_QUOTA=7        # code de sortie interprété comme « quota épuisé »
ATTENTE_DEFAUT=900  # 15 min, quand l'heure de reset est inconnue
MARGE=60            # on se réveille un peu après le reset annoncé

cible=""; max_cycles=100; dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --max-cycles) max_cycles="${2:-100}"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) cible="$1"; shift ;;
  esac
done

[ -n "$cible" ] && [ -d "$cible" ] || {
  printf 'dossier introuvable: %s\n' "$cible" >&2; exit 2; }
[ -f "$cible/.autopilot/STATE.json" ] || {
  printf 'aucun état autopilot dans %s\n' "$cible" >&2; exit 2; }

journal() { bash "$ETAT" ledger "$cible" "$1" 2>/dev/null || true; }

attente() {
  # Rend le nombre de secondes à dormir avant la prochaine tentative.
  epoch=$(bash "$QUOTA" reset-epoch 2>/dev/null || printf -- '-')
  case "$epoch" in
    ''|-|*[!0-9]*) printf '%s\n' "$ATTENTE_DEFAUT"; return ;;
  esac
  maintenant=$(date +%s)
  delta=$(( epoch - maintenant + MARGE ))
  if [ "$delta" -lt 60 ]; then printf '60\n'; else printf '%s\n' "$delta"; fi
}

cycle=0
while [ "$cycle" -lt "$max_cycles" ]; do
  if bash "$ETAT" done "$cible"; then
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
    journal "Quota épuisé, attente de $secondes s avant reprise (cycle $cycle)."
    "$DORMIR" "$secondes"
    continue
  fi

  if [ "$code" -ne 0 ]; then
    journal "claude a rendu le code $code au cycle $cycle, nouvelle tentative."
    "$DORMIR" 30
  fi
done

if bash "$ETAT" done "$cible"; then
  journal "Travail terminé au dernier cycle."
  exit 0
fi
journal "Plafond de $max_cycles cycles atteint sans achèvement."
exit 1
```

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

Run: `./tests/run.sh`
Expected: les assertions de `test_supervisor.sh` passent.

- [ ] **Step 5: shellcheck**

Run: `shellcheck skill/scripts/autopilot-supervisor.sh`
Expected: aucune sortie.

- [ ] **Step 6: Commit**

```bash
git add skill/scripts/autopilot-supervisor.sh tests/test_supervisor.sh
git commit -m "feat(supervisor): boucle de relance avec attente du reset de quota"
```

---

### Task 5: SKILL.md et références

**Files:**
- Create: `skill/SKILL.md`
- Create: `skill/references/MODES.md`
- Create: `skill/references/AUTONOMY.md`
- Create: `skill/references/DELIVERY.md`
- Create: `skill/references/RESUMING.md`
- Test: `tests/test_skill_doc.sh`

**Interfaces:**
- Consumes: les trois scripts des tâches 1 à 3, le superviseur de la tâche 4
- Produces: la skill invocable, avec un front-matter `name: autopilot` et une `description` qui déclenche sur « créer un projet », « améliorer un projet », « livrer de A à Z »

- [ ] **Step 1: Écrire le test qui échoue**

Créer `tests/test_skill_doc.sh` :

```bash
SK="$ROOT/skill/SKILL.md"

test_skill_front_matter() {
  head -1 "$SK" | grep -q -- '---'; assert "SKILL.md commence par un front-matter" $?
  grep -q '^name: autopilot$' "$SK"; assert "le nom est autopilot" $?
  grep -q '^description: ' "$SK"; assert "une description est présente" $?
}

test_skill_description_declenche() {
  d=$(grep '^description: ' "$SK")
  case "$d" in *cré*|*creé*|*créer*) r=0;; *) r=1;; esac
  assert "la description parle de création" $r
  case "$d" in *amélior*|*ameliorer*) r=0;; *) r=1;; esac
  assert "la description parle d'amélioration" $r
}

test_skill_references_existent() {
  manquants=0
  for f in MODES AUTONOMY DELIVERY RESUMING; do
    [ -f "$ROOT/skill/references/$f.md" ] || manquants=$((manquants+1))
  done
  [ "$manquants" -eq 0 ]; assert "les 4 fichiers de référence existent" $?
}

test_skill_cite_ses_references() {
  manquants=0
  for f in MODES AUTONOMY DELIVERY RESUMING; do
    grep -q "$f.md" "$SK" || manquants=$((manquants+1))
  done
  [ "$manquants" -eq 0 ]; assert "SKILL.md cite ses 4 références" $?
}

test_skill_cite_ses_scripts() {
  manquants=0
  for s in autopilot-detect autopilot-state autopilot-quota autopilot-supervisor; do
    grep -q "$s" "$SK" || manquants=$((manquants+1))
  done
  [ "$manquants" -eq 0 ]; assert "SKILL.md cite ses 4 scripts" $?
}

test_skill_interdit_le_push() {
  grep -qiE 'jamais.*(push|merge)|ne (pousse|fusionne) jamais' "$SK"
  assert "SKILL.md interdit explicitement merge et push" $?
}

test_skill_delegue_a_superpowers() {
  manquants=0
  for s in writing-plans subagent-driven-development test-driven-development \
           verification-before-completion; do
    grep -q "$s" "$SK" || manquants=$((manquants+1))
  done
  [ "$manquants" -eq 0 ]; assert "SKILL.md délègue aux skills superpowers" $?
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

Run: `./tests/run.sh`
Expected: FAIL — `skill/SKILL.md` n'existe pas.

- [ ] **Step 3: Écrire `skill/SKILL.md`**

Le front-matter exact :

```markdown
---
name: autopilot
description: Crée un projet neuf ou améliore un projet existant à partir d'une demande, de bout en bout et sans interruption — détection du mode, conception, plan, exécution en TDD, revue, vérification, livraison sur une branche locale. Reprend seule après une coupure ou un épuisement de quota. À utiliser quand la demande est « construis-moi X », « améliore X », « livre X de A à Z », ou toute demande de projet à mener sans surveillance.
---
```

Le corps couvre, dans cet ordre, en citant chaque fichier de référence et chaque script :

1. **Ce que fait la skill** — trois phrases, dont l'interdiction de merge/push.
2. **Démarrage** — `scripts/autopilot-detect.sh <dossier>` pour le mode, puis `scripts/autopilot-state.sh init`. Lire `references/MODES.md`.
3. **Le flux** — le tableau des étapes 0 à 9 de la spec, chaque ligne nommant la skill superpowers déléguée (`brainstorming`, `writing-plans`, `subagent-driven-development`, `test-driven-development`, `systematic-debugging`, `requesting-code-review`, `receiving-code-review`, `verification-before-completion`).
4. **Autonomie** — renvoi à `references/AUTONOMY.md`, format du `Ruling:`, les quatre seuls arrêts.
5. **Checkpoints** — après chaque tâche : commit git, `autopilot-state.sh set`, `autopilot-state.sh ledger`. Renvoi à `references/RESUMING.md`.
6. **Reprise** — ce que fait la skill quand elle est invoquée avec « reprise » : lire `.autopilot/RESUME.md` et `STATE.json`, ne jamais se fier à un souvenir de conversation.
7. **Quota** — `scripts/autopilot-supervisor.sh <dossier>` à lancer en arrière-plan, et le fait qu'elle doit sortir avec le code 7 quand elle constate un épuisement.
8. **Fin** — renvoi à `references/DELIVERY.md`, format du rapport final.

- [ ] **Step 4: Écrire les quatre références**

`references/MODES.md` — la règle de détection, ce que fait l'amorçage en mode création (dépôt, échafaudage, premier commit, baseline verte), ce que fait `using-git-worktrees` en mode amélioration, et le fait qu'aucune question n'est posée pour trancher.

`references/AUTONOMY.md` — le format `Ruling: <décision> — <pourquoi> — <coût si faux>`, les quatre situations qui arrêtent (identifiants ou réseau manquants, opération irréversible hors du dossier, action sensible côté sécurité, demande indéfendable), et une table de signaux d'alarme du type « je ferais mieux de demander » → « non : tranche et consigne ».

`references/DELIVERY.md` — la définition de « fini » : tests lancés avec leur sortie réelle citée, branche nommée, plan et spec référencés, Rulings listés, et l'interdiction de merge, push, publication, déploiement.

`references/RESUMING.md` — le contenu de `.autopilot/`, la règle du commit par tâche, la procédure de reprise pas à pas, et l'obligation de ne jamais reconstruire l'état depuis la conversation.

- [ ] **Step 5: Lancer le test, vérifier qu'il passe**

Run: `./tests/run.sh`
Expected: les assertions de `test_skill_doc.sh` passent.

- [ ] **Step 6: Commit**

```bash
git add skill/SKILL.md skill/references tests/test_skill_doc.sh
git commit -m "feat(skill): orchestrateur autopilot et ses quatre références"
```

---

### Task 6: Installation et vérification d'ensemble

**Files:**
- Create: `install.sh`
- Create: `README.md`
- Test: `tests/test_install.sh`

**Interfaces:**
- Consumes: tout ce qui précède
- Produces: `~/.claude/skills/autopilot` → lien symbolique vers `<dépôt>/skill`

- [ ] **Step 1: Écrire le test qui échoue**

Créer `tests/test_install.sh` :

```bash
I="$ROOT/install.sh"

test_install_cree_le_lien() {
  faux_home=$(mktemp -d)
  HOME="$faux_home" bash "$I" >/dev/null 2>&1
  [ -L "$faux_home/.claude/skills/autopilot" ]
  assert "install.sh crée le lien symbolique" $?
  [ -f "$faux_home/.claude/skills/autopilot/SKILL.md" ]
  assert "le lien pointe sur une skill lisible" $?
  rm -rf "$faux_home"
}

test_install_idempotent() {
  faux_home=$(mktemp -d)
  HOME="$faux_home" bash "$I" >/dev/null 2>&1
  HOME="$faux_home" bash "$I" >/dev/null 2>&1
  assert "deux installations de suite ne cassent rien" $?
  rm -rf "$faux_home"
}

test_install_refuse_d_ecraser_un_vrai_dossier() {
  faux_home=$(mktemp -d)
  mkdir -p "$faux_home/.claude/skills/autopilot"
  echo "contenu précieux" > "$faux_home/.claude/skills/autopilot/garde.md"
  HOME="$faux_home" bash "$I" >/dev/null 2>&1
  [ -f "$faux_home/.claude/skills/autopilot/garde.md" ]
  assert "un dossier existant n'est jamais écrasé" $?
  rm -rf "$faux_home"
}

test_tous_les_scripts_sont_executables() {
  manquants=0
  for s in "$ROOT"/skill/scripts/*.sh; do
    [ -x "$s" ] || manquants=$((manquants+1))
  done
  [ "$manquants" -eq 0 ]; assert "tous les scripts sont exécutables" $?
}

test_shellcheck_propre() {
  command -v shellcheck >/dev/null || { assert "shellcheck absent, ignoré" 0; return; }
  shellcheck "$ROOT"/skill/scripts/*.sh "$ROOT"/install.sh "$ROOT"/tests/run.sh
  assert "shellcheck ne signale rien" $?
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

Run: `./tests/run.sh`
Expected: FAIL — `install.sh` n'existe pas.

- [ ] **Step 3: Écrire `install.sh`**

```bash
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
```

- [ ] **Step 4: Écrire `README.md`**

Contenu : ce que fait autopilot, comment l'installer (`./install.sh`), comment l'invoquer, comment lancer le superviseur, où vit l'état, ce qu'elle ne fait jamais, et comment lancer les tests.

- [ ] **Step 5: Lancer toute la suite**

Run: `./tests/run.sh`
Expected: toutes les assertions des six fichiers de test passent, zéro échec.

- [ ] **Step 6: Installer pour de vrai et vérifier**

```bash
./install.sh
ls -l ~/.claude/skills/autopilot
```
Expected: le lien existe et pointe sur `~/Projects/autopilot/skill`.

- [ ] **Step 7: Commit**

```bash
git add install.sh README.md tests/test_install.sh
git commit -m "feat(install): installation par lien symbolique et vérification d'ensemble"
```
