W="$ROOT/skill/scripts/autopilot-watch.sh"
ST="$ROOT/skill/scripts/autopilot-state.sh"

# --- Cas limites d'invocation ---

test_watch_usage_sans_argument() {
  out=$(bash "$W" 2>&1)
  [ $? -eq 2 ]; assert "sans argument : code 2" $?
  case "$out" in *sage*) r=0 ;; *) r=1 ;; esac
  assert "sans argument : message d'usage affiché" $r
}

test_watch_dossier_introuvable() {
  bash "$W" /tmp/autopilot-veilleur-absent-$$ >/dev/null 2>&1
  [ $? -eq 2 ]; assert "dossier introuvable : code 2" $?
}

test_watch_sans_etat_prealable() {
  d=$(mktemp -d)
  bash "$W" "$d" >/dev/null 2>&1
  [ $? -eq 2 ]; assert "aucun état autopilot : code 2, ne boucle pas dans le vide" $?
  rm -rf "$d"
}

test_watch_option_inconnue_rejetee() {
  d=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  bash "$W" "$d" --option-bidon >/dev/null 2>&1
  [ $? -eq 2 ]; assert "option inconnue : code 2" $?
  rm -rf "$d"
}

test_watch_seuil_non_numerique_rejete() {
  d=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  bash "$W" "$d" --seuil abc >/dev/null 2>&1
  [ $? -eq 2 ]; assert "--seuil non numérique : code 2" $?
  rm -rf "$d"
}

test_watch_intervalle_non_numerique_rejete() {
  d=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  bash "$W" "$d" --intervalle abc >/dev/null 2>&1
  [ $? -eq 2 ]; assert "--intervalle non numérique : code 2" $?
  rm -rf "$d"
}

# --- Arrêts propres, sans jamais interroger la sonde s'ils sont déjà vrais ---

test_watch_s_arrete_si_phase_termine_des_le_depart() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  bash "$ST" set "$d" phase termine
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
touch "$(dirname "$0")/appele"
echo "0 - five_hour 10"
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_QUOTA="$bin/quota" AUTOPILOT_SLEEP=true bash "$W" "$d" >/dev/null 2>&1
  [ $? -eq 0 ]; assert "phase termine dès le départ : arrêt propre en code 0" $?
  [ ! -f "$bin/appele" ]; assert "phase termine dès le départ : la sonde n'est jamais interrogée" $?
  rm -rf "$d" "$bin"
}

test_watch_s_arrete_si_phase_bloque_des_le_depart() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  bash "$ST" set "$d" phase bloque
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
touch "$(dirname "$0")/appele"
echo "0 - five_hour 10"
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_QUOTA="$bin/quota" AUTOPILOT_SLEEP=true bash "$W" "$d" >/dev/null 2>&1
  [ $? -eq 0 ]; assert "phase bloque dès le départ : arrêt propre en code 0" $?
  [ ! -f "$bin/appele" ]; assert "phase bloque dès le départ : la sonde n'est jamais interrogée" $?
  rm -rf "$d" "$bin"
}

test_watch_s_arrete_si_etat_illisible_des_le_depart() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  printf '{"mode": "creat' > "$d/.autopilot/STATE.json"
  cat > "$bin/quota" <<'EOS'
#!/usr/bin/env bash
touch "$(dirname "$0")/appele"
echo "0 - five_hour 10"
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_QUOTA="$bin/quota" AUTOPILOT_SLEEP=true bash "$W" "$d" >/dev/null 2>&1
  [ $? -eq 0 ]; assert "STATE.json illisible dès le départ : arrêt propre" $?
  [ ! -f "$bin/appele" ]; assert "STATE.json illisible dès le départ : la sonde n'est jamais interrogée" $?
  rm -rf "$d" "$bin"
}

test_watch_s_arrete_si_dossier_disparait_en_cours_de_route() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  cat > "$bin/quota" <<EOS
#!/usr/bin/env bash
rm -rf "$d"
echo "0 - five_hour 10"
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_QUOTA="$bin/quota" AUTOPILOT_SLEEP=true bash "$W" "$d" --intervalle 1 >/dev/null 2>&1
  [ $? -eq 0 ]; assert "dossier disparu en cours de route : arrêt propre" $?
  rm -rf "$bin"
}

# --- Alerte : franchissement du seuil, redescente, sonde en panne ---

test_watch_seuil_franchi_cree_alerte() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  cat > "$bin/quota" <<EOS
#!/usr/bin/env bash
compteur="\$(dirname "\$0")/compteur"
n=\$(cat "\$compteur" 2>/dev/null || echo 0)
n=\$((n+1)); echo "\$n" > "\$compteur"
if [ "\$n" -eq 1 ]; then
  echo "0 - five_hour 60"
else
  bash "$ST" set "$d" phase termine
  echo "1 - five_hour 96"
fi
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_QUOTA="$bin/quota" AUTOPILOT_SLEEP=true \
    bash "$W" "$d" --seuil 90 --intervalle 1 >/dev/null 2>&1
  [ -f "$d/.autopilot/QUOTA_ALERTE" ]
  assert "seuil franchi (96 >= 90) : QUOTA_ALERTE créée" $?
  rm -rf "$d" "$bin"
}

test_watch_utilisation_redescendue_supprime_alerte() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  cat > "$bin/quota" <<EOS
#!/usr/bin/env bash
compteur="\$(dirname "\$0")/compteur"
n=\$(cat "\$compteur" 2>/dev/null || echo 0)
n=\$((n+1)); echo "\$n" > "\$compteur"
if [ "\$n" -eq 1 ]; then
  echo "1 - five_hour 96"
else
  bash "$ST" set "$d" phase termine
  echo "0 - five_hour 40"
fi
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_QUOTA="$bin/quota" AUTOPILOT_SLEEP=true \
    bash "$W" "$d" --seuil 90 --intervalle 1 >/dev/null 2>&1
  [ ! -f "$d/.autopilot/QUOTA_ALERTE" ]
  assert "utilisation redescendue sous le seuil : QUOTA_ALERTE supprimée" $?
  rm -rf "$d" "$bin"
}

test_watch_sonde_en_panne_ne_cree_jamais_alerte() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  cat > "$bin/quota" <<EOS
#!/usr/bin/env bash
compteur="\$(dirname "\$0")/compteur"
n=\$(cat "\$compteur" 2>/dev/null || echo 0)
n=\$((n+1)); echo "\$n" > "\$compteur"
if [ "\$n" -ge 3 ]; then
  bash "$ST" set "$d" phase termine
fi
exit 1
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_QUOTA="$bin/quota" AUTOPILOT_SLEEP=true \
    bash "$W" "$d" --seuil 90 --intervalle 1 >/dev/null 2>&1
  [ ! -f "$d/.autopilot/QUOTA_ALERTE" ]
  assert "sonde en panne à chaque tour : jamais d'alerte créée" $?
  compte_sonde=$(grep -ic 'sonde' "$d/.autopilot/LEDGER.md")
  [ "$compte_sonde" -eq 1 ]
  assert "sonde en panne répétée : une seule ligne de ledger, pas une par tour" $?
  rm -rf "$d" "$bin"
}

test_watch_sonde_en_panne_preserve_une_alerte_deja_presente() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  cat > "$bin/quota" <<EOS
#!/usr/bin/env bash
compteur="\$(dirname "\$0")/compteur"
n=\$(cat "\$compteur" 2>/dev/null || echo 0)
n=\$((n+1)); echo "\$n" > "\$compteur"
if [ "\$n" -eq 1 ]; then
  echo "1 - five_hour 97"
else
  bash "$ST" set "$d" phase termine
  exit 1
fi
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_QUOTA="$bin/quota" AUTOPILOT_SLEEP=true \
    bash "$W" "$d" --seuil 90 --intervalle 1 >/dev/null 2>&1
  [ -f "$d/.autopilot/QUOTA_ALERTE" ]
  assert "sonde en panne après une alerte déjà créée : l'alerte n'est pas effacée à l'aveugle" $?
  rm -rf "$d" "$bin"
}

# --- QUOTA.json et watch.pid ---

test_watch_ecrit_quota_json_a_chaque_tour() {
  d=$(mktemp -d); bin=$(mktemp -d)
  bash "$ST" init "$d" creation "x" >/dev/null
  cat > "$bin/quota" <<EOS
#!/usr/bin/env bash
bash "$ST" set "$d" phase termine
echo "0 - five_hour 42"
EOS
  chmod +x "$bin/quota"
  AUTOPILOT_QUOTA="$bin/quota" AUTOPILOT_SLEEP=true \
    bash "$W" "$d" --intervalle 1 >/dev/null 2>&1
  [ -f "$d/.autopilot/QUOTA.json" ]; assert "QUOTA.json est écrit" $?
  grep -q '42' "$d/.autopilot/QUOTA.json"; assert "QUOTA.json contient l'utilisation constatée" $?
  grep -q 'five_hour' "$d/.autopilot/QUOTA.json"; assert "QUOTA.json contient la fenêtre concernée" $?
  grep -qi 'horodatage' "$d/.autopilot/QUOTA.json"; assert "QUOTA.json contient un horodatage" $?
  grep -qi 'sonde' "$d/.autopilot/QUOTA.json"; assert "QUOTA.json dit si la sonde a répondu" $?
  rm -rf "$d" "$bin"
}

test_watch_ecrit_et_nettoie_son_pid() {
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
  AUTOPILOT_QUOTA="$bin/quota" AUTOPILOT_SLEEP="$bin/sleep" \
    bash "$W" "$d" --intervalle 1 >/dev/null 2>&1 &
  pid=$!
  tries=0
  while [ ! -s "$d/.autopilot/watch.pid" ] && [ "$tries" -lt 2000 ]; do
    date +%s%N >/dev/null 2>&1
    tries=$((tries + 1))
  done
  contenu=$(cat "$d/.autopilot/watch.pid" 2>/dev/null || echo "")
  [ "$contenu" = "$pid" ]; assert "watch.pid contient le PID du veilleur" $?
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  tries=0
  while [ -f "$d/.autopilot/watch.pid" ] && [ "$tries" -lt 2000 ]; do
    date +%s%N >/dev/null 2>&1
    tries=$((tries + 1))
  done
  [ ! -f "$d/.autopilot/watch.pid" ]; assert "watch.pid est nettoyé quand le veilleur s'arrête" $?
  rm -rf "$d" "$bin"
}

# --- Documentation ---

test_watch_seuil_alerte_documente_dans_la_spec() {
  S="$ROOT/docs/superpowers/specs/2026-09-17-autopilot-design.md"
  grep -q '90' "$S"; assert "le seuil d'alerte de 90 est documenté dans la spec" $?
  grep -qi 'marge' "$S"; assert "la spec explique la marge entre 90 et le seuil d'épuisement 95" $?
}
