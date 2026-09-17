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

test_state_resume_affiche_zero_pour_cycles() {
  d=$(mktemp -d)
  bash "$S" init "$d" creation "x" >/dev/null
  grep -q '| cycles | 0 |' "$d/.autopilot/RESUME.md"
  assert "RESUME.md affiche 0 (et non —) juste après init" $?
  bash "$S" set "$d" cycles 0
  grep -q '| cycles | 0 |' "$d/.autopilot/RESUME.md"
  assert "RESUME.md affiche 0 après un set explicite à 0" $?
  rm -rf "$d"
}

test_state_init_est_idempotent() {
  d=$(mktemp -d)
  bash "$S" init "$d" creation "x" >/dev/null
  bash "$S" set "$d" tache "avancement important" >/dev/null
  bash "$S" set "$d" phase execution >/dev/null
  bash "$S" ledger "$d" "decision cruciale" >/dev/null
  bash "$S" init "$d" creation "x" >/dev/null
  rc=$?
  [ "$rc" -eq 0 ]; assert "un second init (sans --force) réussit en code 0" $?
  [ "$(bash "$S" get "$d" tache)" = "avancement important" ]
  assert "un second init préserve la tâche déjà enregistrée" $?
  [ "$(bash "$S" get "$d" phase)" = "execution" ]
  assert "un second init préserve la phase déjà enregistrée" $?
  grep -q "decision cruciale" "$d/.autopilot/LEDGER.md"
  assert "un second init préserve les lignes déjà écrites du ledger" $?
  rm -rf "$d"
}

test_state_init_force_reinitialise_sans_tronquer_le_ledger() {
  d=$(mktemp -d)
  bash "$S" init "$d" creation "x" >/dev/null
  bash "$S" set "$d" phase execution >/dev/null
  bash "$S" ledger "$d" "avant le force" >/dev/null
  bash "$S" init "$d" creation "y" --force >/dev/null
  [ "$(bash "$S" get "$d" phase)" = "init" ]
  assert "init --force réinitialise bien la phase" $?
  grep -q "avant le force" "$d/.autopilot/LEDGER.md"
  assert "init --force ne tronque jamais le ledger existant" $?
  rm -rf "$d"
}

test_state_resume_dit_bloque_sans_ambiguite() {
  d=$(mktemp -d)
  bash "$S" init "$d" creation "x" >/dev/null
  bash "$S" set "$d" phase bloque
  grep -qi "décision humaine" "$d/.autopilot/RESUME.md"
  assert "RESUME.md dit qu'une décision humaine est requise en phase bloque" $?
  grep -qi "aucune reprise automatique" "$d/.autopilot/RESUME.md"
  assert "RESUME.md dit qu'aucune reprise automatique n'aura lieu en phase bloque" $?
  grep -qi "Arrêt" "$d/.autopilot/RESUME.md"
  assert "RESUME.md renvoie à la ligne Arrêt du ledger" $?
  rm -rf "$d"
}

# --- I2 : RESUME.md et RESUMING.md ne peuvent plus diverger ---

test_resume_et_resuming_renvoient_a_la_meme_etape() {
  R="$ROOT/skill/references/RESUMING.md"
  d=$(mktemp -d)
  bash "$S" init "$d" creation "x" >/dev/null
  divergences=""
  for ph in init conception plan execution revue verification; do
    ligne=$(grep -E "^\| .$ph. \|" "$R" | head -1)
    attendu=$(printf '%s' "$ligne" | sed -E 's/.*étapes? ([0-9]+).*/\1/')
    bash "$S" set "$d" phase "$ph"
    suite=$(sed -n '/## Prochaine action/,$p' "$d/.autopilot/RESUME.md")
    case "$suite" in
      *"étape $attendu"*|*"étapes $attendu"*) ;;
      *) divergences="$divergences $ph(attendu $attendu)" ;;
    esac
  done
  [ -z "$divergences" ]
  assert "RESUME.md renvoie à la même étape que la table de RESUMING.md :$divergences" $?
  rm -rf "$d"
}

test_resume_dit_ecrire_le_plan_en_phase_plan() {
  d=$(mktemp -d)
  bash "$S" init "$d" creation "x" >/dev/null
  bash "$S" set "$d" phase plan
  grep -qi 'écrire le plan' "$d/.autopilot/RESUME.md"
  assert "phase plan : RESUME.md dit d'écrire le plan, pas de lancer l'exécution" $?
  rm -rf "$d"
}
