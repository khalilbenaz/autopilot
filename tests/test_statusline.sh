SL="$ROOT/skill/scripts/autopilot-statusline.sh"

# --- aides ---

# longueur maximale en caractères (pas en octets) parmi les lignes de $1
sl_ligne_max() {
  printf '%s' "$1" | python3 -c '
import sys
lignes = sys.stdin.read().split(chr(10))
print(max((len(l) for l in lignes), default=0))
'
}

sl_json_base() { # cwd -> JSON complet hors-run avec tout renseigné
  cwd="$1"
  cat <<JSON
{
  "session_id": "sess-abc123",
  "cwd": "$cwd",
  "workspace": {"current_dir": "$cwd"},
  "model": {"display_name": "Sonnet 5"},
  "cost": {"total_cost_usd": 0.37, "total_lines_added": 10, "total_lines_removed": 2, "total_duration_ms": 12000},
  "context_window": {"total_input_tokens": 1000, "total_output_tokens": 200, "context_window_size": 200000, "used_percentage": 42.0, "remaining_percentage": 58.0, "current_usage": {"input_tokens": 100, "output_tokens": 20, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}},
  "rate_limits": {"five_hour": {"used_percentage": 14.0, "resets_at": $(($(date +%s) + 3600))}, "seven_day": {"used_percentage": 55.0, "resets_at": $(($(date +%s) + 86400))}},
  "session_id": "sess-abc123"
}
JSON
}

test_statusline_entree_complete() {
  d=$(mktemp -d)
  sortie=$(sl_json_base "$d" | bash "$SL" 2>&1)
  code=$?
  [ "$code" -eq 0 ]; assert "entrée complète : code de sortie 0" $?
  max=$(sl_ligne_max "$sortie")
  [ "$max" -le 150 ]; assert "entrée complète : aucune ligne au-dessus de 150 caractères" $?
  case "$sortie" in *"Sonnet 5"*) r=0 ;; *) r=1 ;; esac
  assert "entrée complète : le modèle apparaît" $r
  rm -rf "$d"
}

test_statusline_rate_limits_absent() {
  d=$(mktemp -d)
  sortie=$(printf '{"cwd":"%s","model":{"display_name":"Sonnet 5"}}' "$d" | bash "$SL" 2>&1)
  code=$?
  [ "$code" -eq 0 ]; assert "rate_limits absent : code de sortie 0" $?
  max=$(sl_ligne_max "$sortie")
  [ "$max" -le 150 ]; assert "rate_limits absent : lignes sous 150 caractères" $?
  case "$sortie" in *"n/d"*) r=0 ;; *) r=1 ;; esac
  assert "rate_limits absent : replié sur n/d, pas de plantage" $r
  rm -rf "$d"
}

test_statusline_context_window_null() {
  d=$(mktemp -d)
  sortie=$(printf '{"cwd":"%s","context_window":null}' "$d" | bash "$SL" 2>&1)
  code=$?
  [ "$code" -eq 0 ]; assert "context_window null : code de sortie 0" $?
  max=$(sl_ligne_max "$sortie")
  [ "$max" -le 150 ]; assert "context_window null : lignes sous 150 caractères" $?
  rm -rf "$d"
}

test_statusline_entree_vide() {
  sortie=$(printf '' | bash "$SL" 2>&1)
  code=$?
  [ "$code" -eq 0 ]; assert "entrée vide : code de sortie 0" $?
  max=$(sl_ligne_max "$sortie")
  [ "$max" -le 150 ]; assert "entrée vide : lignes sous 150 caractères" $?
}

test_statusline_json_invalide() {
  sortie=$(printf 'ceci ne ressemble pas a du json {{{' | bash "$SL" 2>&1)
  code=$?
  [ "$code" -eq 0 ]; assert "JSON invalide : code de sortie 0 malgré tout" $?
  max=$(sl_ligne_max "$sortie")
  [ "$max" -le 150 ]; assert "JSON invalide : lignes sous 150 caractères" $?
}

test_statusline_hors_run() {
  d=$(mktemp -d)
  sortie=$(sl_json_base "$d" | bash "$SL" 2>&1)
  code=$?
  [ "$code" -eq 0 ]; assert "hors run : code de sortie 0" $?
  case "$sortie" in *cycles*) r=1 ;; *) r=0 ;; esac
  assert "hors run : rien sur les cycles (pas de STATE.json)" $r
  case "$sortie" in *"état :"*) r=1 ;; *) r=0 ;; esac
  assert "hors run : pas de ligne d'état de run" $r
  rm -rf "$d"
}

# --- écrit un STATE.json minimal pour les tests « pendant un run » ---
sl_state() { # dossier phase tache plan branche cycles
  mkdir -p "$1/.autopilot"
  cat > "$1/.autopilot/STATE.json" <<JSON
{
  "mode": "amelioration",
  "demande": "test",
  "phase": "$2",
  "tache": "$3",
  "spec": "",
  "plan": "$4",
  "branche": "$5",
  "worktree": "",
  "cycles": $6
}
JSON
}

test_statusline_run_tache_avec_numero_et_plan_valide() {
  d=$(mktemp -d)
  cat > "$d/plan.md" <<'PLAN'
### Task 1: Une
### Task 2: Deux
### Task 3: Trois
### Task 4: Quatre
PLAN
  sl_state "$d" "execution" "Task 3: Geometrie" "plan.md" "autopilot/x" 4
  sortie=$(sl_json_base "$d" | bash "$SL" 2>&1)
  code=$?
  [ "$code" -eq 0 ]; assert "run, tâche numérotée + plan valide : code 0" $?
  case "$sortie" in *"3/4"*) r=0 ;; *) r=1 ;; esac
  assert "run, tâche numérotée + plan valide : fraction 3/4 correcte" $r
  rm -rf "$d"
}

test_statusline_run_plan_chemin_relatif() {
  d=$(mktemp -d)
  mkdir -p "$d/docs"
  cat > "$d/docs/plan.md" <<'PLAN'
### Task 1: Une
### Task 2: Deux
PLAN
  sl_state "$d" "execution" "Tâche 2 : bidule" "docs/plan.md" "autopilot/x" 1
  sortie=$(sl_json_base "$d" | bash "$SL" 2>&1)
  case "$sortie" in *"2/2"*) r=0 ;; *) r=1 ;; esac
  assert "run, chemin de plan relatif : résolu depuis le dossier du projet" $r
  rm -rf "$d"
}

test_statusline_run_tache_vide_pas_de_fraction() {
  d=$(mktemp -d)
  cat > "$d/plan.md" <<'PLAN'
### Task 1: Une
### Task 2: Deux
PLAN
  sl_state "$d" "execution" "" "plan.md" "autopilot/x" 0
  sortie=$(sl_json_base "$d" | bash "$SL" 2>&1)
  case "$sortie" in *[0-9]/[0-9]*) r=1 ;; *) r=0 ;; esac
  assert "run, tâche vide : aucune fraction inventée" $r
  rm -rf "$d"
}

test_statusline_run_plan_introuvable_pas_de_fraction() {
  d=$(mktemp -d)
  sl_state "$d" "execution" "Task 5: x" "plan-absent.md" "autopilot/x" 0
  sortie=$(sl_json_base "$d" | bash "$SL" 2>&1)
  case "$sortie" in *[0-9]/[0-9]*) r=1 ;; *) r=0 ;; esac
  assert "run, plan introuvable : aucune fraction inventée" $r
  rm -rf "$d"
}

test_statusline_run_tache_sans_numero_pas_de_fraction() {
  d=$(mktemp -d)
  cat > "$d/plan.md" <<'PLAN'
### Task 1: Une
### Task 2: Deux
PLAN
  sl_state "$d" "execution" "en cours de travail" "plan.md" "autopilot/x" 0
  sortie=$(sl_json_base "$d" | bash "$SL" 2>&1)
  case "$sortie" in *[0-9]/[0-9]*) r=1 ;; *) r=0 ;; esac
  assert "run, libellé de tâche sans numéro : aucune fraction inventée" $r
  case "$sortie" in *"en cours de travail"*) r=0 ;; *) r=1 ;; esac
  assert "run, libellé de tâche sans numéro : le libellé est quand même affiché" $r
  rm -rf "$d"
}

test_statusline_phase_termine() {
  d=$(mktemp -d)
  sl_state "$d" "termine" "" "" "autopilot/x" 9
  sortie=$(sl_json_base "$d" | bash "$SL" 2>&1)
  code=$?
  [ "$code" -eq 0 ]; assert "phase termine : code de sortie 0" $?
  case "$sortie" in *"terminé"*) r=0 ;; *) r=1 ;; esac
  assert "phase termine : état affiché comme terminé" $r
  rm -rf "$d"
}

test_statusline_phase_bloque() {
  d=$(mktemp -d)
  sl_state "$d" "bloque" "Task 2" "" "autopilot/x" 2
  sortie=$(sl_json_base "$d" | bash "$SL" 2>&1)
  code=$?
  [ "$code" -eq 0 ]; assert "phase bloque : code de sortie 0" $?
  case "$sortie" in *"bloqué"*) r=0 ;; *) r=1 ;; esac
  assert "phase bloque : état affiché comme bloqué" $r
  rm -rf "$d"
}

test_statusline_quota_alerte() {
  d=$(mktemp -d)
  sl_state "$d" "execution" "Task 1" "" "autopilot/x" 1
  : > "$d/.autopilot/QUOTA_ALERTE"
  sortie=$(sl_json_base "$d" | bash "$SL" 2>&1)
  code=$?
  [ "$code" -eq 0 ]; assert "QUOTA_ALERTE présent : code de sortie 0" $?
  case "$sortie" in *"attente"*) r=0 ;; *) r=1 ;; esac
  assert "QUOTA_ALERTE présent : état en attente de reset" $r
  rm -rf "$d"
}

test_statusline_quota_alerte_absent_est_normal() {
  d=$(mktemp -d)
  sl_state "$d" "execution" "Task 1" "" "autopilot/x" 1
  sortie=$(sl_json_base "$d" | bash "$SL" 2>&1)
  code=$?
  [ "$code" -eq 0 ]; assert "QUOTA_ALERTE absent : toujours code 0, pas une panne" $?
  rm -rf "$d"
}

test_statusline_duree_execution() {
  d=$(mktemp -d)
  debut=$(date +%s%N)
  sl_json_base "$d" | bash "$SL" >/dev/null 2>&1
  fin=$(date +%s%N)
  ms=$(( (fin - debut) / 1000000 ))
  printf '  (mesuré : %dms)\n' "$ms"
  # Cible réelle documentée : < 100ms. Seuil de test généreux pour ne pas
  # rendre le harnais capricieux sur une machine chargée ou un premier
  # démarrage à froid de python3 ; la mesure réelle est imprimée ci-dessus.
  [ "$ms" -lt 3000 ]; assert "s'exécute en un temps raisonnable" $?
  rm -rf "$d"
}
