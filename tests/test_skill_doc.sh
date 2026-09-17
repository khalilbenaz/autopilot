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

# --- Corrections demandées en revue (2026-09-18) ---

test_phase_bloque_specifiee() {
  grep -q 'bloque' "$ROOT/skill/references/AUTONOMY.md"
  assert "AUTONOMY.md spécifie le mécanisme de la phase bloque" $?
  grep -q 'bloque' "$ROOT/skill/references/RESUMING.md"
  assert "RESUMING.md liste bloque parmi les phases" $?
}

test_phases_enumerees_dans_resuming() {
  R="$ROOT/skill/references/RESUMING.md"
  manquants=0
  for p in init conception plan execution revue verification termine bloque; do
    grep -q "$p" "$R" || manquants=$((manquants+1))
  done
  [ "$manquants" -eq 0 ]; assert "RESUMING.md énumère les 8 phases légales" $?
}

test_pas_de_code_7() {
  ! grep -riq 'code 7' "$ROOT/skill/SKILL.md" "$ROOT/skill/references"/*.md
  assert "aucun fichier de la skill ne promet un code de sortie 7" $?
}

test_pas_de_meta_commentaire_de_revue() {
  ! grep -riqE 'ce dépôt|tranchée en revue|revue technique' \
    "$ROOT/skill/SKILL.md" "$ROOT/skill/references"/*.md
  assert "aucune référence n'expose de méta-commentaire de revue" $?
}

test_chemins_de_scripts_precises() {
  grep -qi 'dossier de la skill' "$SK"
  assert "SKILL.md précise que les chemins de scripts sont relatifs à la skill" $?
}

test_aiguillage_demarrage_ou_reprise() {
  grep -q 'STATE.json' "$SK" && grep -qi 'reprise' "$SK"
  assert "SKILL.md aiguille entre démarrage et reprise selon l'état existant" $?
}

test_superviseur_lance_par_un_humain() {
  grep -qi 'humain' "$SK"
  assert "SKILL.md dit que le superviseur est lancé par un humain" $?
}

test_delivery_a_un_gabarit() {
  grep -qi 'gabarit' "$ROOT/skill/references/DELIVERY.md"
  assert "DELIVERY.md fournit un gabarit de rapport final" $?
}

# --- Corrections demandées en revue (2026-09-18, round 4) ---

test_arret_porte_sur_toute_ecriture_hors_dossier() {
  A="$ROOT/skill/references/AUTONOMY.md"
  grep -qiE 'toute .{0,20}écriture.{0,40}hors du dossier' "$A"
  assert "AUTONOMY.md fait de toute écriture hors du dossier un arrêt" $?
  grep -qi 'réversible ou non' "$A"
  assert "AUTONOMY.md précise que la réversibilité ne rattrape rien" $?
  ! grep -riq 'opération irréversible hors du dossier\|irréversible hors du répertoire' \
    "$ROOT/skill/SKILL.md" "$ROOT/skill/references"/*.md
  assert "aucune référence ne limite plus l'arrêt au seul cas irréversible" $?
}

test_lecture_hors_dossier_reste_permise() {
  grep -qi 'lire hors du dossier' "$ROOT/skill/references/AUTONOMY.md"
  assert "AUTONOMY.md distingue explicitement lecture (permise) et écriture (arrêt)" $?
}

# --- C1 : les gates des skills déléguées sont pré-approuvées ---

test_skill_preapprouve_le_gate_de_brainstorming() {
  grep -qi 'instruction utilisateur' "$SK"
  assert "SKILL.md se présente comme une instruction utilisateur, pas une suggestion" $?
  grep -qi 'take precedence over skills' "$SK"
  assert "SKILL.md s'appuie sur la précédence des instructions utilisateur (using-superpowers)" $?
  grep -qi 'brainstorming' "$SK" && grep -qi 'constitue cette approbation' "$SK"
  assert "SKILL.md dit que l'invocation vaut l'approbation attendue par brainstorming" $?
  grep -qi "sans attendre un « oui »" "$SK"
  assert "SKILL.md dit que la conception continue sans attendre un oui" $?
}

test_skill_declare_la_preference_de_worktree() {
  grep -qi 'préférence' "$SK" && grep -qi 'worktree' "$SK"
  assert "SKILL.md déclare la préférence de worktree cherchée par using-git-worktrees" $?
  grep -qi 'ne se pose donc pas' "$SK"
  assert "SKILL.md dit que la question du worktree n'est pas posée" $?
}
