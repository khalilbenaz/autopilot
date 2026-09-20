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
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true bash "$SUP" "$d" >/dev/null 2>&1
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
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true bash "$SUP" "$d" --sans-veilleur >/dev/null 2>&1
  assert "s'arrête dès que claude marque l'état terminé" $?
  rm -rf "$d" "$bin"
}

test_supervisor_plafond_de_cycles() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  faux_claude "$bin/claude" "0 0 0 0 0"
  # --max-cycles-sans-progres élevé : ce test porte sur le plafond de cycles,
  # pas sur le détecteur d'absence de progrès (qui rendrait 4 dès le 3e cycle).
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true \
    bash "$SUP" "$d" --max-cycles 3 --max-cycles-sans-progres 9 --sans-veilleur >/dev/null 2>&1
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
    AUTOPILOT_QUOTA="$bin/quota" bash "$SUP" "$d" --max-cycles 2 --sans-veilleur >/dev/null 2>&1
  [ -f "$bin/dodo" ]; assert "dort après une sortie sur quota épuisé" $?
  grep -q "quota" "$d/.autopilot/LEDGER.md"
  assert "consigne l'attente dans le ledger" $?
  rm -rf "$d" "$bin"
}

test_supervisor_dossier_absent() {
  AUTOPILOT_SLEEP=true bash "$SUP" /tmp/autopilot-absent-$$ >/dev/null 2>&1
  [ $? -eq 2 ]; assert "rend 2 si le dossier n'existe pas" $?
}

# --- Cas limites ---

test_supervisor_usage_sans_argument() {
  out=$(AUTOPILOT_SLEEP=true bash "$SUP" 2>&1)
  [ $? -eq 2 ]; assert "sans argument : code 2" $?
  case "$out" in *sage*) r=0 ;; *) r=1 ;; esac
  assert "sans argument : message d'usage affiché" $r
}

test_supervisor_option_inconnue_rejetee() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  faux_claude "$bin/claude" "0"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true bash "$SUP" "$d" --option-bidon >/dev/null 2>&1
  [ $? -eq 2 ]; assert "option inconnue : code 2" $?
  [ ! -f "$bin/compteur" ]; assert "option inconnue : ne lance jamais claude" $?
  rm -rf "$d" "$bin"
}

test_supervisor_max_cycles_non_numerique() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  faux_claude "$bin/claude" "0"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true bash "$SUP" "$d" --max-cycles abc >/dev/null 2>&1
  [ $? -eq 2 ]; assert "--max-cycles non numérique : code 2" $?
  [ ! -f "$bin/compteur" ]; assert "--max-cycles non numérique : ne lance jamais claude" $?
  rm -rf "$d" "$bin"
}

test_supervisor_max_cycles_sans_valeur() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  faux_claude "$bin/claude" "0"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true bash "$SUP" "$d" --max-cycles >/dev/null 2>&1
  [ $? -eq 2 ]; assert "--max-cycles sans valeur : sort en code 2 (pas de boucle infinie)" $?
  rm -rf "$d" "$bin"
}

test_supervisor_dry_run_ne_lance_jamais_claude() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  faux_claude "$bin/claude" "0"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true \
    bash "$SUP" "$d" --dry-run --max-cycles 2 >/dev/null 2>&1
  [ $? -eq 1 ]; assert "dry-run : atteint le plafond sans jamais réussir" $?
  [ ! -f "$bin/compteur" ]; assert "dry-run : ne lance jamais claude" $?
  rm -rf "$d" "$bin"
}

test_supervisor_epoch_de_reset_deja_passe() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  faux_claude "$bin/claude" "7 0"
  cat > "$bin/sleep" <<'EOS'
#!/usr/bin/env bash
echo "$1" >> "$(dirname "$0")/dodo"
EOS
  chmod +x "$bin/sleep"
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
[ "$1" = "reset-epoch" ] && echo $(( $(date +%s) - 3600 ))
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP="$bin/sleep" \
    AUTOPILOT_QUOTA="$bin/quota" bash "$SUP" "$d" --max-cycles 2 --sans-veilleur >/dev/null 2>&1
  attente=$(cat "$bin/dodo")
  [ "$attente" -ge 60 ]
  assert "epoch de reset déjà passé : attente plancher, pas de rafale immédiate" $?
  rm -rf "$d" "$bin"
}

test_supervisor_plafond_attente_epoch_absurde() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  faux_claude "$bin/claude" "7 0"
  cat > "$bin/sleep" <<'EOS'
#!/usr/bin/env bash
echo "$1" >> "$(dirname "$0")/dodo"
EOS
  chmod +x "$bin/sleep"
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
[ "$1" = "reset-epoch" ] && echo $(( $(date +%s) + 999999999 ))
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP="$bin/sleep" \
    AUTOPILOT_QUOTA="$bin/quota" bash "$SUP" "$d" --max-cycles 2 --sans-veilleur >/dev/null 2>&1
  attente=$(cat "$bin/dodo")
  [ "$attente" -le 691200 ]
  assert "epoch de reset absurde (années) : attente plafonnée" $?
  rm -rf "$d" "$bin"
}

test_supervisor_quota_en_boucle_sans_jamais_avancer() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  faux_claude "$bin/claude" "7 7 7 7 7 7 7 7"
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
[ "$1" = "reset-epoch" ] && echo "-"
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true AUTOPILOT_QUOTA="$bin/quota" \
    bash "$SUP" "$d" --max-cycles 3 --sans-veilleur >/dev/null 2>&1
  [ $? -eq 1 ]; assert "quota épuisé à chaque cycle : le plafond stoppe quand même la boucle" $?
  n=$(cat "$bin/compteur"); [ "$n" -eq 3 ]
  assert "quota épuisé à chaque cycle : n'appelle pas claude au-delà du plafond" $?
  rm -rf "$d" "$bin"
}

test_supervisor_dossier_disparait_pendant_la_boucle() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  cat > "$bin/claude" <<EOS
#!/usr/bin/env bash
compteur="\$(dirname "\$0")/compteur"
n=\$(cat "\$compteur" 2>/dev/null || echo 0)
n=\$((n+1)); echo "\$n" > "\$compteur"
rm -rf "$d"
exit 0
EOS
  chmod +x "$bin/claude"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true \
    bash "$SUP" "$d" --max-cycles 50 --sans-veilleur >/dev/null 2>&1
  [ $? -eq 2 ]; assert "rend 2 si le dossier disparaît en cours de boucle" $?
  n=$(cat "$bin/compteur"); [ "$n" -eq 1 ]
  assert "dossier disparu : ne réessaie pas d'appeler claude après coup" $?
  rm -rf "$bin"
}

test_supervisor_budget_attente_cumulee_epuise() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  faux_claude "$bin/claude" "7 7 7 7 7 7 7 7 7 7"
  cat > "$bin/sleep" <<'EOS'
#!/usr/bin/env bash
echo "$1" >> "$(dirname "$0")/dodo"
EOS
  chmod +x "$bin/sleep"
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
[ "$1" = "reset-epoch" ] && echo $(( $(date +%s) + 999999999 ))
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP="$bin/sleep" AUTOPILOT_QUOTA="$bin/quota" \
    bash "$SUP" "$d" --max-cycles 50 --budget-attente 100 --sans-veilleur >/dev/null 2>&1
  [ $? -eq 1 ]; assert "budget d'attente cumulée épuisé : sort en code 1" $?
  grep -q "budget" "$d/.autopilot/LEDGER.md"
  assert "budget d'attente cumulée épuisé : consigné au ledger" $?
  n=$(cat "$bin/compteur"); [ "$n" -lt 50 ]
  assert "budget d'attente cumulée épuisé : n'a pas consommé tous ses cycles" $?
  rm -rf "$d" "$bin"
}

test_supervisor_sonde_signale_epuise_meme_sans_code_7() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  faux_claude "$bin/claude" "5 0"
  cat > "$bin/sleep" <<'EOS'
#!/usr/bin/env bash
echo "$1" >> "$(dirname "$0")/dodo"
EOS
  chmod +x "$bin/sleep"
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
case "$1" in
  verdict) echo "1 - epuise 99" ;;
  reset-epoch) echo "-" ;;
esac
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP="$bin/sleep" AUTOPILOT_QUOTA="$bin/quota" \
    bash "$SUP" "$d" --max-cycles 2 --sans-veilleur >/dev/null 2>&1
  attente=$(cat "$bin/dodo" 2>/dev/null)
  [ "$attente" = "900" ]
  assert "code non-7 + sonde épuisée : attend jusqu'au reset, pas la pause d'erreur" $?
  grep -q "quota" "$d/.autopilot/LEDGER.md"
  assert "code non-7 + sonde épuisée : consigné comme attente de quota" $?
  rm -rf "$d" "$bin"
}

test_supervisor_sonde_signale_compte_sain_pause_ordinaire() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  faux_claude "$bin/claude" "5 0"
  cat > "$bin/sleep" <<'EOS'
#!/usr/bin/env bash
echo "$1" >> "$(dirname "$0")/dodo"
EOS
  chmod +x "$bin/sleep"
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
case "$1" in
  verdict) echo "0 - aucune 12" ;;
  reset-epoch) echo "-" ;;
esac
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP="$bin/sleep" AUTOPILOT_QUOTA="$bin/quota" \
    bash "$SUP" "$d" --max-cycles 2 --sans-veilleur >/dev/null 2>&1
  attente=$(cat "$bin/dodo" 2>/dev/null)
  [ "$attente" = "30" ]
  assert "code non-7 + sonde saine : pause d'erreur ordinaire, pas une attente de quota" $?
  rm -rf "$d" "$bin"
}

test_supervisor_sonde_en_panne_pause_ordinaire_et_consignee() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  faux_claude "$bin/claude" "5 0"
  cat > "$bin/sleep" <<'EOS'
#!/usr/bin/env bash
echo "$1" >> "$(dirname "$0")/dodo"
EOS
  chmod +x "$bin/sleep"
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
exit 1
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP="$bin/sleep" AUTOPILOT_QUOTA="$bin/quota" \
    bash "$SUP" "$d" --max-cycles 2 --sans-veilleur >/dev/null 2>&1
  attente=$(cat "$bin/dodo" 2>/dev/null)
  [ "$attente" = "30" ]
  assert "sonde en panne : pause d'erreur ordinaire, pas une attente de plusieurs heures" $?
  grep -q "sonde" "$d/.autopilot/LEDGER.md"
  assert "sonde en panne : signalée dans le ledger" $?
  rm -rf "$d" "$bin"
}

test_supervisor_phase_bloque_sort_en_3_sans_appeler_claude() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  bash "$ST" set "$d" phase bloque
  faux_claude "$bin/claude" "0"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true bash "$SUP" "$d" >/dev/null 2>&1
  [ $? -eq 3 ]; assert "phase bloque : sort en code 3" $?
  [ ! -f "$bin/compteur" ]; assert "phase bloque : ne lance jamais claude" $?
  grep -q "bloqu" "$d/.autopilot/LEDGER.md"
  assert "phase bloque : consigné au ledger" $?
  rm -rf "$d" "$bin"
}

test_supervisor_chemin_avec_espace() {
  base=$(mktemp -d)
  d="$base/dossier avec espace"
  mkdir -p "$d"
  bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  bash "$ST" set "$d" phase termine
  faux_claude "$bin/claude" "0"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true bash "$SUP" "$d" >/dev/null 2>&1
  assert "gère un chemin de dossier contenant une espace" $?
  rm -rf "$base" "$bin"
}

# --- C4 : mode de permission, détection d'absence de progrès, appel unique ---

# Faux claude qui enregistre ses arguments et rend toujours 0.
claude_espion() { # <chemin>
  cat > "$1" <<'EOS'
#!/usr/bin/env bash
dir="$(dirname "$0")"
compteur="$dir/compteur"
n=$(cat "$compteur" 2>/dev/null || echo 0)
n=$((n+1)); echo "$n" > "$compteur"
echo "$*" >> "$dir/arguments"
exit 0
EOS
  chmod +x "$1"
}

test_supervisor_passe_accept_edits_par_defaut() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  claude_espion "$bin/claude"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true \
    bash "$SUP" "$d" --max-cycles 1 --sans-veilleur >/dev/null 2>&1
  grep -q -- '--permission-mode acceptEdits' "$bin/arguments"
  assert "claude est lancé avec --permission-mode acceptEdits par défaut" $?
  rm -rf "$d" "$bin"
}

test_supervisor_mode_de_permission_reglable() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  claude_espion "$bin/claude"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true \
    bash "$SUP" "$d" --max-cycles 1 --permission-mode bypassPermissions --sans-veilleur >/dev/null 2>&1
  grep -q -- '--permission-mode bypassPermissions' "$bin/arguments"
  assert "--permission-mode remplace la valeur par défaut" $?
  rm -rf "$d" "$bin"
}

test_supervisor_mode_de_permission_invalide_rejete() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  claude_espion "$bin/claude"
  sortie=$(AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true bash "$SUP" "$d" --permission-mode nimportequoi 2>&1)
  [ $? -eq 2 ]; assert "--permission-mode inconnu : code 2" $?
  [ ! -f "$bin/compteur" ]; assert "--permission-mode inconnu : ne lance jamais claude" $?
  case "$sortie" in *acceptEdits*) r=0 ;; *) r=1 ;; esac
  assert "--permission-mode inconnu : le message nomme les valeurs acceptées" $r
  rm -rf "$d" "$bin"
}

test_supervisor_abandonne_sans_progres() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  claude_espion "$bin/claude"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true \
    bash "$SUP" "$d" --max-cycles 30 --sans-veilleur >/dev/null 2>&1
  [ $? -eq 4 ]; assert "aucun progrès pendant 3 cycles : code 4" $?
  n=$(cat "$bin/compteur"); [ "$n" -eq 3 ]
  assert "aucun progrès : s'arrête au 3e cycle, pas au 30e" $?
  grep -qi 'progr' "$d/.autopilot/LEDGER.md"
  assert "aucun progrès : consigné au ledger" $?
  rm -rf "$d" "$bin"
}

# --- Régression : un run qui commite et écrit au ledger progresse vraiment,
# même quand phase et tâche ne changent pas de cycle en cycle (une tâche
# longue peut traverser plusieurs cycles sans changer de nom).

test_supervisor_ne_abandonne_pas_si_ca_commite_sans_changer_phase_ou_tache() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  cat > "$bin/claude" <<EOS
#!/usr/bin/env bash
compteur="\$(dirname "\$0")/compteur"
n=\$(cat "\$compteur" 2>/dev/null || echo 0)
n=\$((n+1)); echo "\$n" > "\$compteur"
echo "contenu \$n" > "fichier-\$n.txt"
git init -q . >/dev/null 2>&1
git -c user.email=test@test.test -c user.name=Test add -A >/dev/null 2>&1
git -c user.email=test@test.test -c user.name=Test commit -q -m "commit \$n" >/dev/null 2>&1
bash "$ST" ledger "$d" "Ruling: décision \$n — parce que — rien" >/dev/null 2>&1
exit 0
EOS
  chmod +x "$bin/claude"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true \
    bash "$SUP" "$d" --max-cycles 5 --sans-veilleur >/dev/null 2>&1
  code=$?
  [ "$code" -ne 4 ]
  assert "des commits et des lignes de ledger à chaque cycle : pas d'abandon en code 4" $?
  n=$(cat "$bin/compteur"); [ "$n" -eq 5 ]
  assert "des commits et des lignes de ledger à chaque cycle : les 5 cycles tournent" $?
  rm -rf "$d" "$bin"
}

test_supervisor_seuil_de_progres_reglable() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  claude_espion "$bin/claude"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true \
    bash "$SUP" "$d" --max-cycles 30 --max-cycles-sans-progres 1 --sans-veilleur >/dev/null 2>&1
  [ $? -eq 4 ]; assert "--max-cycles-sans-progres 1 : abandonne dès le premier cycle stérile" $?
  n=$(cat "$bin/compteur"); [ "$n" -eq 1 ]
  assert "--max-cycles-sans-progres 1 : un seul appel à claude" $?
  rm -rf "$d" "$bin"
}

test_supervisor_progres_remet_le_compteur_a_zero() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  cat > "$bin/claude" <<EOS
#!/usr/bin/env bash
compteur="\$(dirname "\$0")/compteur"
n=\$(cat "\$compteur" 2>/dev/null || echo 0)
n=\$((n+1)); echo "\$n" > "\$compteur"
bash "$ST" set "$d" tache "tache \$n"
exit 0
EOS
  chmod +x "$bin/claude"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true \
    bash "$SUP" "$d" --max-cycles 5 --sans-veilleur >/dev/null 2>&1
  [ $? -eq 1 ]; assert "un état qui avance à chaque cycle ne déclenche jamais le code 4" $?
  n=$(cat "$bin/compteur"); [ "$n" -eq 5 ]
  assert "un état qui avance : tous les cycles sont consommés" $?
  rm -rf "$d" "$bin"
}

test_supervisor_journalise_les_cycles_normaux() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  cat > "$bin/claude" <<EOS
#!/usr/bin/env bash
bash "$ST" set "$d" phase termine
exit 0
EOS
  chmod +x "$bin/claude"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true \
    bash "$SUP" "$d" --max-cycles 2 --sans-veilleur >/dev/null 2>&1
  grep -qi 'cycle 1' "$d/.autopilot/LEDGER.md"
  assert "un cycle sans incident laisse une trace au ledger" $?
  rm -rf "$d" "$bin"
}

test_supervisor_une_seule_interrogation_de_la_sonde() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  faux_claude "$bin/claude" "5 0"
  cat > "$bin/sleep" <<'EOS'
#!/usr/bin/env bash
echo "$1" >> "$(dirname "$0")/dodo"
EOS
  chmod +x "$bin/sleep"
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
echo "$1" >> "$(dirname "$0")/appels"
case "$1" in
  verdict) echo "1 2000000000 five_hour 99" ;;
  reset-epoch) echo "2000000000" ;;
esac
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP="$bin/sleep" AUTOPILOT_QUOTA="$bin/quota" \
    bash "$SUP" "$d" --max-cycles 2 --sans-veilleur >/dev/null 2>&1
  n=$(grep -c . "$bin/appels")
  [ "$n" -eq 1 ]
  assert "une sortie non nulle n'interroge la sonde qu'une seule fois" $?
  rm -rf "$d" "$bin"
}

test_supervisor_etat_illisible_sort_en_2() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  claude_espion "$bin/claude"
  printf '{"mode": "creat' > "$d/.autopilot/STATE.json"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP=true \
    bash "$SUP" "$d" --max-cycles 100 >/dev/null 2>&1
  [ $? -eq 2 ]; assert "état illisible : code 2, pas cent cycles à vide" $?
  [ ! -f "$bin/compteur" ]; assert "état illisible : ne lance jamais claude" $?
  grep -qi 'illisible' "$d/.autopilot/LEDGER.md"
  assert "état illisible : consigné au ledger" $?
  rm -rf "$d" "$bin"
}

# --- Veilleur : surveillance continue (nouvelle fonctionnalité) ---

test_supervisor_lance_le_veilleur_avant_claude_et_l_arrete_apres() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
echo "0 - five_hour 10"
EOS
  chmod +x "$bin/quota"
  cat > "$bin/claude" <<EOS
#!/usr/bin/env bash
tries=0
while [ ! -s "$d/.autopilot/watch.pid" ] && [ "\$tries" -lt 2000 ]; do
  date +%s%N >/dev/null 2>&1
  tries=\$((tries + 1))
done
[ -s "$d/.autopilot/watch.pid" ] && touch "$bin/veilleur_vu"
exit 0
EOS
  chmod +x "$bin/claude"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_QUOTA="$bin/quota" AUTOPILOT_SLEEP=true \
    bash "$SUP" "$d" --max-cycles 1 >/dev/null 2>&1
  [ -f "$bin/veilleur_vu" ]
  assert "le veilleur tourne déjà (watch.pid écrit) quand claude démarre" $?
  [ ! -f "$d/.autopilot/watch.pid" ]
  assert "le veilleur est arrêté (watch.pid nettoyé) après le retour de claude" $?
  rm -rf "$d" "$bin"
}

test_supervisor_tue_le_veilleur_meme_sur_interruption() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
echo "0 - five_hour 10"
EOS
  chmod +x "$bin/quota"
  cat > "$bin/sleep" <<'EOS'
#!/usr/bin/env bash
while :; do :; done
EOS
  chmod +x "$bin/sleep"
  cat > "$bin/claude" <<'EOS'
#!/usr/bin/env bash
while :; do :; done
EOS
  chmod +x "$bin/claude"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_QUOTA="$bin/quota" AUTOPILOT_SLEEP="$bin/sleep" \
    bash "$SUP" "$d" --max-cycles 1 >/dev/null 2>&1 &
  pid_sup=$!
  tries=0
  while [ ! -s "$d/.autopilot/watch.pid" ] && [ "$tries" -lt 2000 ]; do
    date +%s%N >/dev/null 2>&1
    tries=$((tries + 1))
  done
  pid_veilleur=$(cat "$d/.autopilot/watch.pid" 2>/dev/null || echo "")
  [ -n "$pid_veilleur" ] && kill -0 "$pid_veilleur" 2>/dev/null
  assert "le veilleur est bien vivant avant l'interruption" $?
  kill -TERM "$pid_sup" 2>/dev/null
  wait "$pid_sup" 2>/dev/null
  tries=0
  while kill -0 "$pid_veilleur" 2>/dev/null && [ "$tries" -lt 2000 ]; do
    date +%s%N >/dev/null 2>&1
    tries=$((tries + 1))
  done
  ! kill -0 "$pid_veilleur" 2>/dev/null
  assert "le veilleur est tué quand le superviseur reçoit SIGTERM" $?
  rm -rf "$d" "$bin"
}

test_supervisor_aucun_processus_orphelin_apres_interruption() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
echo "0 - five_hour 10"
EOS
  chmod +x "$bin/quota"
  cat > "$bin/sleep" <<'EOS'
#!/usr/bin/env bash
while :; do :; done
EOS
  chmod +x "$bin/sleep"
  cat > "$bin/claude" <<'EOS'
#!/usr/bin/env bash
while :; do :; done
EOS
  chmod +x "$bin/claude"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_QUOTA="$bin/quota" AUTOPILOT_SLEEP="$bin/sleep" \
    bash "$SUP" "$d" --max-cycles 1 >/dev/null 2>&1 &
  pid_sup=$!
  tries=0
  while [ ! -s "$d/.autopilot/watch.pid" ] && [ "$tries" -lt 2000 ]; do
    date +%s%N >/dev/null 2>&1
    tries=$((tries + 1))
  done
  # SIGTERM, pas SIGINT : un job lancé en arrière-plan (« & ») a SIGINT
  # ignoré par convention POSIX dès l'entrée dans le shell, et un signal
  # ignoré à l'entrée ne peut plus être piégé ni réarmé (comportement
  # documenté de bash) — ce n'est pas testable dans ce harnais, qui lance
  # forcément le superviseur en arrière-plan. SIGTERM n'est pas concerné par
  # cette règle et reste le signal réaliste pour arrêter un démon.
  kill -TERM "$pid_sup" 2>/dev/null
  wait "$pid_sup" 2>/dev/null
  tries=0
  while ps -p "$pid_sup" >/dev/null 2>&1 && [ "$tries" -lt 2000 ]; do
    date +%s%N >/dev/null 2>&1
    tries=$((tries + 1))
  done
  restants=$(ps -eo pid,command | grep -F "$bin/" | grep -v grep || true)
  [ -z "$restants" ]
  assert "aucun processus orphelin (claude ou veilleur) après interruption du superviseur" $?
  rm -rf "$d" "$bin"
}

test_supervisor_attend_sur_alerte_meme_sans_verdict_epuise() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  printf 'alerte de test\n' > "$d/.autopilot/QUOTA_ALERTE"
  cat > "$bin/claude" <<EOS
#!/usr/bin/env bash
bash "$ST" set "$d" phase termine
exit 0
EOS
  chmod +x "$bin/claude"
  cat > "$bin/sleep" <<'EOS'
#!/usr/bin/env bash
echo "$1" >> "$(dirname "$0")/dodo"
EOS
  chmod +x "$bin/sleep"
  # 40 %, volontairement bas : le veilleur (relancé au cycle suivant, une
  # fois l'alerte effacée) ne doit pas la recréer aussitôt de lui-même avec
  # son propre seuil (90 % par défaut) — ce test porte sur la décision du
  # superviseur, pas sur celle du veilleur.
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
case "$1" in
  verdict) echo "0 - five_hour 40" ;;
esac
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP="$bin/sleep" AUTOPILOT_QUOTA="$bin/quota" \
    bash "$SUP" "$d" --max-cycles 5 >/dev/null 2>&1
  [ $? -eq 0 ]; assert "superviseur : attend sur l'alerte puis termine normalement" $?
  [ -f "$bin/dodo" ]
  assert "superviseur : a dormi à cause de l'alerte alors que la sonde ne dit pas épuisé (0)" $?
  attente=$(head -1 "$bin/dodo")
  [ "$attente" = "900" ]
  assert "superviseur : attente par défaut (900s) faute d'heure de reset connue" $?
  [ ! -f "$d/.autopilot/QUOTA_ALERTE" ]
  assert "superviseur : l'alerte est effacée après l'attente, avant de relancer" $?
  grep -qi 'alerte' "$d/.autopilot/LEDGER.md"
  assert "superviseur : l'attente sur alerte est consignée au ledger" $?
  rm -rf "$d" "$bin"
}

test_supervisor_sans_veilleur_ignore_une_alerte_existante() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  printf 'alerte de test\n' > "$d/.autopilot/QUOTA_ALERTE"
  cat > "$bin/claude" <<EOS
#!/usr/bin/env bash
bash "$ST" set "$d" phase termine
exit 0
EOS
  chmod +x "$bin/claude"
  cat > "$bin/sleep" <<'EOS'
#!/usr/bin/env bash
echo "$1" >> "$(dirname "$0")/dodo"
EOS
  chmod +x "$bin/sleep"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_SLEEP="$bin/sleep" \
    bash "$SUP" "$d" --max-cycles 2 --sans-veilleur >/dev/null 2>&1
  [ $? -eq 0 ]; assert "--sans-veilleur : termine normalement malgré une alerte présente" $?
  [ ! -f "$bin/dodo" ]
  assert "--sans-veilleur : n'attend pas sur une alerte existante (comportement réactif d'avant)" $?
  [ ! -f "$d/.autopilot/watch.pid" ]
  assert "--sans-veilleur : aucun watch.pid n'est jamais créé" $?
  rm -rf "$d" "$bin"
}

test_supervisor_seuil_alerte_et_intervalle_veille_reglables() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
echo "0 - five_hour 10"
EOS
  chmod +x "$bin/quota"
  faux_claude "$bin/claude" "0"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_QUOTA="$bin/quota" AUTOPILOT_SLEEP=true \
    bash "$SUP" "$d" --max-cycles 1 --seuil-alerte 80 --intervalle-veille 5 >/dev/null 2>&1
  [ $? -eq 1 ]; assert "--seuil-alerte et --intervalle-veille sont acceptés sans erreur" $?
  rm -rf "$d" "$bin"
}

# --- Défaut signalé en revue (2026-09-20) : dossier disparu PENDANT un
# sommeil de quota, pas seulement entre deux cycles. Sans surveillant
# dédié, le superviseur dormait jusqu'au bout d'une attente pouvant durer
# jusqu'à 8 jours (ATTENTE_MAX) pour un dossier qui n'existait plus depuis
# longtemps. AUTOPILOT_VERIF_DOSSIER (doublure dédiée, distincte de
# AUTOPILOT_SLEEP) rend la cadence de vérification du surveillant instantanée
# pour le test, sans jamais dormir réellement.

test_supervisor_dossier_disparait_pendant_un_sommeil_de_quota() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  faux_claude "$bin/claude" "7"
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
[ "$1" = "verdict" ] && echo "1 - five_hour 99"
EOS
  chmod +x "$bin/quota"
  # Sommeil principal qui ne rendrait jamais la main de lui-même : sans le
  # surveillant de dossier, ce test ne terminerait jamais.
  cat > "$bin/sleep" <<'EOS'
#!/usr/bin/env bash
while :; do :; done
EOS
  chmod +x "$bin/sleep"
  AUTOPILOT_CLAUDE="$bin/claude" AUTOPILOT_QUOTA="$bin/quota" AUTOPILOT_SLEEP="$bin/sleep" \
    AUTOPILOT_VERIF_DOSSIER=true \
    bash "$SUP" "$d" --sans-veilleur --max-cycles 1 >/dev/null 2>&1 &
  pid_sup=$!
  # Attendre que le superviseur soit bien entré dans le sommeil de quota
  # (ligne de ledger déjà écrite) avant de supprimer le dossier sous ses
  # pieds — sinon on supprimerait un dossier pas encore utilisé et le test
  # ne prouverait rien sur le sommeil lui-même.
  tries=0
  while ! grep -q "Attente de quota" "$d/.autopilot/LEDGER.md" 2>/dev/null && [ "$tries" -lt 2000 ]; do
    date +%s%N >/dev/null 2>&1
    tries=$((tries + 1))
  done
  rm -rf "$d"
  tries=0
  while kill -0 "$pid_sup" 2>/dev/null && [ "$tries" -lt 2000 ]; do
    date +%s%N >/dev/null 2>&1
    tries=$((tries + 1))
  done
  ! kill -0 "$pid_sup" 2>/dev/null
  assert "dossier supprimé pendant un sommeil de quota (infini ici) : le surveillant coupe le sommeil, le superviseur sort" $?
  kill -9 "$pid_sup" 2>/dev/null
  pkill -9 -P "$pid_sup" 2>/dev/null
  rm -rf "$bin"
}
