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

test_skill_actes_sortants_jamais_par_initiative_propre() {
  grep -qi 'propre initiative' "$SK"
  assert "SKILL.md limite l'interdiction à la propre initiative, pas à l'absolu" $?
  grep -qi 'propre initiative' "$ROOT/README.md"
  assert "README.md reprend la même limite : jamais de sa propre initiative" $?
}

test_skill_acte_demande_explicitement_est_livre() {
  grep -qi 'partie du livrable comme une autre' "$SK"
  assert "SKILL.md dit qu'un acte sortant demandé explicitement est livré" $?
  grep -qi 'partie du livrable comme une autre' "$ROOT/README.md"
  assert "README.md dit la même chose" $?
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

test_superviseur_lance_par_la_skill() {
  # Changement de conception (2026-09-20) : c'est la skill qui lance son
  # propre superviseur, pas un humain. La commande manuelle reste
  # documentée comme recours, d'où la présence persistante de « humain ».
  grep -qi 'nohup' "$SK"
  assert "SKILL.md donne la commande de lancement détachée (nohup)" $?
  grep -q 'AUTOPILOT_SUPERVISE' "$SK"
  assert "SKILL.md documente AUTOPILOT_SUPERVISE (anti-récursion)" $?
  grep -qi 'humain' "$SK"
  assert "SKILL.md garde le recours manuel documenté pour un humain" $?
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

# --- C4 : mode de permission et code 4 documentés ---

test_code_4_et_permission_mode_documentes() {
  grep -q '| `4` |' "$SK"
  assert "SKILL.md documente le code de sortie 4 du superviseur" $?
  grep -q '| `4` |' "$ROOT/README.md"
  assert "README.md documente le code de sortie 4 du superviseur" $?
  grep -q 'permission-mode' "$SK" && grep -q 'acceptEdits' "$SK"
  assert "SKILL.md documente --permission-mode et son défaut acceptEdits" $?
  grep -q 'permission-mode' "$ROOT/README.md" && grep -q 'acceptEdits' "$ROOT/README.md"
  assert "README.md documente --permission-mode et son défaut acceptEdits" $?
  grep -q 'max-cycles-sans-progres' "$SK" && grep -q 'max-cycles-sans-progres' "$ROOT/README.md"
  assert "SKILL.md et README.md documentent --max-cycles-sans-progres" $?
}

# --- I1 : la phase est écrite à l'entrée de chaque phase ---

test_skill_prescrit_un_set_phase_a_l_entree() {
  grep -qi "entrée de chaque phase" "$SK"
  assert "SKILL.md prescrit un set phase à l'entrée de chaque phase" $?
  manquants=0
  for ph in conception plan execution revue verification; do
    grep -q "phase $ph" "$SK" || manquants=$((manquants+1))
  done
  [ "$manquants" -eq 0 ]
  assert "SKILL.md nomme le set phase de chaque phase intermédiaire" $?
  grep -qi "reste .init." "$SK"
  assert "SKILL.md explique ce que coûte une phase laissée à init" $?
}

test_worktree_prescrit_et_documente() {
  grep -q 'worktree' "$SK" && grep -q 'clé `worktree`' "$SK"
  assert "SKILL.md prescrit l'écriture de la clé worktree à l'étape 1′" $?
  grep -q 'worktree' "$ROOT/skill/references/RESUMING.md"
  assert "RESUMING.md décrit le worktree dans le contenu de STATE.json" $?
}

# --- Résidus de revue finale (2026-09-17) ---

test_skill_force_brainstorming_sur_architectural() {
  grep -qi 'architectural' "$SK"
  assert "SKILL.md nomme le chemin architectural de brainstorming" $?
  grep -qi 'quelle que soit la taille' "$SK"
  assert "SKILL.md impose ce chemin quelle que soit la taille apparente de la demande" $?
  grep -qi 'bounded' "$SK"
  assert "SKILL.md nomme explicitement le chemin Bounded écarté" $?
  grep -qi 'instruction utilisateur' "$SK"
  assert "SKILL.md dit avec la même force que le reste de la pré-approbation : instruction utilisateur" $?
}

# --- Corrections demandées en revue (2026-09-20) : actes sortants sur demande ---

test_autonomy_nomme_les_actes_sortants() {
  A="$ROOT/skill/references/AUTONOMY.md"
  grep -qi 'actes sortants' "$A"
  assert "AUTONOMY.md nomme la section des actes sortants" $?
  grep -qi 'propre initiative' "$A"
  assert "AUTONOMY.md pose la règle : jamais de sa propre initiative" $?
}

test_autonomy_actes_sortants_couverture_stricte() {
  A="$ROOT/skill/references/AUTONOMY.md"
  grep -qi 'strictement ce qui est nommé' "$A"
  assert "AUTONOMY.md exige que chaque acte sortant soit couvert un par un" $?
  grep -qi "n'autorise pas un déploiement" "$A"
  assert "AUTONOMY.md donne l'exemple : un push n'autorise pas un déploiement" $?
}

test_autonomy_actes_sortants_apres_verification() {
  A="$ROOT/skill/references/AUTONOMY.md"
  grep -qi 'étape 8' "$A" && grep -qi 'pousser du rouge est interdit' "$A"
  assert "AUTONOMY.md exige les actes sortants après vérification, tests verts d'abord" $?
}

test_autonomy_depot_prive_par_defaut() {
  A="$ROOT/skill/references/AUTONOMY.md"
  grep -qi 'privé par défaut' "$A"
  assert "AUTONOMY.md impose un dépôt créé privé par défaut" $?
  grep -qi 'rendre public est un acte à part' "$A"
  assert "AUTONOMY.md dit que rendre public est un acte nommé à part" $?
}

test_autonomy_git_destructif_reste_un_arret() {
  A="$ROOT/skill/references/AUTONOMY.md"
  grep -qi -- '--force' "$A"
  assert "AUTONOMY.md nomme push --force comme cas exigeant d'être nommé pour lui-même" $?
  grep -qi "réécriture d'historique" "$A"
  assert "AUTONOMY.md nomme la réécriture d'historique" $?
}

test_autonomy_distingue_push_de_l_ecriture_hors_dossier() {
  A="$ROOT/skill/references/AUTONOMY.md"
  grep -qi 'actes sortants' "$A" && grep -qi "n'est pas l'écriture qui distingue" "$A"
  assert "AUTONOMY.md distingue clairement les actes sortants du cas 2 (écriture hors dossier)" $?
}

test_delivery_liste_les_actes_sortants_avec_autorisation() {
  D="$ROOT/skill/references/DELIVERY.md"
  grep -qi "ce qui l'autorisait" "$D"
  assert "DELIVERY.md exige de nommer ce qui autorisait chaque acte sortant" $?
  grep -qi 'de sa propre initiative' "$D"
  assert "DELIVERY.md rappelle l'absence d'initiative propre, pas une interdiction absolue" $?
}

test_spec_actes_sortants_conditionnels_pas_exclus() {
  S="$ROOT/docs/superpowers/specs/2026-09-17-autopilot-design.md"
  grep -qi 'conditionnel' "$S"
  assert "la spec range merge/push/publication/déploiement en conditionnel" $?
  ! grep -A3 '### Exclu' "$S" | grep -qi 'merge, push, publication'
  assert "la spec ne liste plus merge/push/publication/déploiement sous Exclu" $?
}

# --- Nouvelle fonctionnalité (2026-09-20) : veilleur, surveillance continue ---

test_skill_documente_le_veilleur_et_ses_options() {
  grep -qi 'sans-veilleur' "$SK"
  assert "SKILL.md documente --sans-veilleur" $?
  grep -qi 'seuil-alerte' "$SK"
  assert "SKILL.md documente --seuil-alerte" $?
  grep -qi 'intervalle-veille' "$SK"
  assert "SKILL.md documente --intervalle-veille" $?
  grep -qi 'autopilot-watch' "$SK"
  assert "SKILL.md nomme le script autopilot-watch.sh" $?
}

test_skill_decrit_le_point_de_decision_entre_deux_taches() {
  grep -qi 'QUOTA_ALERTE' "$SK"
  assert "SKILL.md nomme le fichier QUOTA_ALERTE" $?
  grep -qi 'entre deux tâches' "$SK"
  assert "SKILL.md décrit le point de décision entre deux tâches" $?
  grep -qi "ne coupe jamais une tâche en cours\|jamais au milieu" "$SK"
  assert "SKILL.md documente la limite : jamais d'interruption en cours de tâche" $?
}

test_resuming_liste_les_fichiers_du_veilleur() {
  R="$ROOT/skill/references/RESUMING.md"
  grep -q 'QUOTA.json' "$R"
  assert "RESUMING.md documente QUOTA.json" $?
  grep -q 'QUOTA_ALERTE' "$R"
  assert "RESUMING.md documente QUOTA_ALERTE" $?
  grep -q 'watch.pid' "$R"
  assert "RESUMING.md documente watch.pid" $?
  grep -qi 'ne change jamais la phase\|reste celle en cours' "$R"
  assert "RESUMING.md précise que l'alerte ne change jamais la phase" $?
}

test_readme_documente_les_deux_regimes() {
  grep -qi 'réactif' "$ROOT/README.md"
  assert "README.md nomme le régime réactif" $?
  grep -qi 'surveillance continue' "$ROOT/README.md"
  assert "README.md nomme le régime de surveillance continue" $?
  grep -qi 'sans-veilleur' "$ROOT/README.md"
  assert "README.md documente --sans-veilleur" $?
  grep -q 'QUOTA_ALERTE' "$ROOT/README.md"
  assert "README.md documente QUOTA_ALERTE" $?
}

test_spec_documente_le_veilleur() {
  S="$ROOT/docs/superpowers/specs/2026-09-17-autopilot-design.md"
  grep -qi 'veilleur' "$S"
  assert "la spec nomme le veilleur" $?
  grep -qi "entre deux tâches" "$S"
  assert "la spec décrit le point de décision entre deux tâches" $?
  grep -qi 'limite assumée' "$S"
  assert "la spec documente la limite assumée (pas d'interruption en cours de tâche)" $?
}

# --- Autolancement du superviseur (2026-09-20) : la skill lance elle-même
# le superviseur, protégée par un verrou de PID et un battement de coeur.

test_skill_documente_autolancement_verrou_et_battement() {
  grep -qi 'supervisor.pid' "$SK"
  assert "SKILL.md documente le verrou supervisor.pid" $?
  grep -q 'HEARTBEAT' "$SK"
  assert "SKILL.md documente le fichier HEARTBEAT" $?
  grep -qi 'seuil-battement' "$SK"
  assert "SKILL.md documente --seuil-battement" $?
  grep -qi 'entre chaque tâche' "$SK"
  assert "SKILL.md prescrit l'écriture du battement entre chaque tâche" $?
}

test_resuming_documente_verrou_et_battement() {
  R="$ROOT/skill/references/RESUMING.md"
  grep -q 'supervisor.pid' "$R"
  assert "RESUMING.md documente le verrou supervisor.pid" $?
  grep -q 'HEARTBEAT' "$R"
  assert "RESUMING.md documente le fichier HEARTBEAT" $?
}

test_readme_documente_autolancement() {
  grep -qi 'lancé par la skill' "$ROOT/README.md"
  assert "README.md dit que le superviseur est lancé par la skill" $?
  grep -q 'supervisor.pid' "$ROOT/README.md"
  assert "README.md documente le verrou supervisor.pid" $?
  grep -q 'AUTOPILOT_SUPERVISE' "$ROOT/README.md"
  assert "README.md documente AUTOPILOT_SUPERVISE" $?
  grep -qi 'recours' "$ROOT/README.md"
  assert "README.md garde la commande manuelle comme recours" $?
}

test_spec_documente_autolancement() {
  S="$ROOT/docs/superpowers/specs/2026-09-17-autopilot-design.md"
  grep -q 'AUTOPILOT_SUPERVISE' "$S"
  assert "la spec documente AUTOPILOT_SUPERVISE" $?
  grep -q 'HEARTBEAT' "$S"
  assert "la spec documente le battement de coeur" $?
  grep -q 'supervisor.pid' "$S"
  assert "la spec documente le verrou supervisor.pid" $?
}
