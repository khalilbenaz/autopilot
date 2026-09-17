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
