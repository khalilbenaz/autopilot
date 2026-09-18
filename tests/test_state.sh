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

# --- I3 : set n'accepte ni clé inventée ni phase inventée ---

test_state_set_refuse_une_cle_inconnue() {
  d=$(mktemp -d)
  bash "$S" init "$d" creation "x" >/dev/null
  sortie=$(bash "$S" set "$d" phse execution 2>&1)
  [ $? -ne 0 ]; assert "set sur une clé inconnue : code non nul" $?
  ! grep -q '"phse"' "$d/.autopilot/STATE.json"
  assert "set sur une clé inconnue : aucune clé n'est créée" $?
  case "$sortie" in *phase*) r=0 ;; *) r=1 ;; esac
  assert "set sur une clé inconnue : le message nomme les clés acceptées" $r
  rm -rf "$d"
}

test_state_set_refuse_une_phase_inconnue() {
  d=$(mktemp -d)
  bash "$S" init "$d" creation "x" >/dev/null
  sortie=$(bash "$S" set "$d" phase nimportequoi 2>&1)
  [ $? -ne 0 ]; assert "set sur une phase inconnue : code non nul" $?
  [ "$(bash "$S" get "$d" phase)" = "init" ]
  assert "set sur une phase inconnue : la phase précédente est intacte" $?
  case "$sortie" in *verification*) r=0 ;; *) r=1 ;; esac
  assert "set sur une phase inconnue : le message nomme les phases légales" $r
  rm -rf "$d"
}

test_state_set_accepte_toutes_les_cles_et_phases_legales() {
  d=$(mktemp -d)
  bash "$S" init "$d" creation "x" >/dev/null
  refus=0
  for c in mode demande tache spec plan branche; do
    bash "$S" set "$d" "$c" "valeur" >/dev/null 2>&1 || refus=$((refus+1))
  done
  bash "$S" set "$d" cycles 4 >/dev/null 2>&1 || refus=$((refus+1))
  [ "$refus" -eq 0 ]; assert "set accepte toutes les clés du schéma" $?
  refus=0
  for ph in init conception plan execution revue verification bloque termine; do
    bash "$S" set "$d" phase "$ph" >/dev/null 2>&1 || refus=$((refus+1))
  done
  [ "$refus" -eq 0 ]; assert "set accepte les huit phases légales" $?
  rm -rf "$d"
}

# --- I4 : écriture atomique et état illisible ---

test_state_illisible_message_francais_sans_traceback() {
  d=$(mktemp -d)
  bash "$S" init "$d" creation "x" >/dev/null
  printf '{"mode": "creat' > "$d/.autopilot/STATE.json"   # coupure en pleine écriture
  for sous_commande in get set done; do
    case "$sous_commande" in
      get)  sortie=$(bash "$S" get "$d" phase 2>&1) ;;
      set)  sortie=$(bash "$S" set "$d" phase execution 2>&1) ;;
      done) sortie=$(bash "$S" done "$d" 2>&1) ;;
    esac
    code=$?
    [ "$code" -ne 0 ]
    assert "$sous_commande sur un état tronqué : code non nul" $?
    case "$sortie" in *Traceback*) r=1 ;; *) r=0 ;; esac
    assert "$sous_commande sur un état tronqué : pas de traceback Python" $r
    case "$sortie" in *illisible*) r=0 ;; *) r=1 ;; esac
    assert "$sous_commande sur un état tronqué : message en français" $r
  done
  rm -rf "$d"
}

test_state_ecriture_atomique_ne_tronque_jamais() {
  if [ "$(id -u)" -eq 0 ]; then
    assert "écriture atomique : test sauté (root ignore les permissions)" 0
    return
  fi
  d=$(mktemp -d)
  bash "$S" init "$d" creation "x" >/dev/null
  # Un STATE.json en lecture seule ne peut pas être ouvert en écriture : seul
  # un remplacement atomique (fichier temporaire puis os.replace) passe.
  chmod 444 "$d/.autopilot/STATE.json"
  bash "$S" set "$d" phase execution >/dev/null 2>&1
  assert "set réécrit l'état par remplacement, jamais par troncature en place" $?
  [ "$(bash "$S" get "$d" phase)" = "execution" ]
  assert "après remplacement atomique, la nouvelle valeur est bien là" $?
  rm -rf "$d"
}

test_state_pas_de_fichier_temporaire_resideul() {
  d=$(mktemp -d)
  bash "$S" init "$d" creation "x" >/dev/null
  bash "$S" set "$d" phase execution
  restes=$(find "$d/.autopilot" -name '*.tmp*' | wc -l | tr -d ' ')
  [ "$restes" -eq 0 ]
  assert "aucun fichier temporaire ne subsiste après un set" $?
  rm -rf "$d"
}
