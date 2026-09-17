SK="$ROOT/skill/SKILL.md"

test_skill_front_matter() {
  head -1 "$SK" | grep -q -- '---'; assert "SKILL.md commence par un front-matter" $?
  grep -q '^name: autopilot$' "$SK"; assert "le nom est autopilot" $?
  grep -q '^description: ' "$SK"; assert "une description est présente" $?
}

test_skill_description_declenche() {
  # Comparaison insensible à la casse : le front-matter (verbatim, non
  # modifiable) commence sa description par « Crée » avec une majuscule.
  d=$(grep '^description: ' "$SK" | tr '[:upper:]' '[:lower:]')
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
