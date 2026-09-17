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
  [ $? -ne 0 ]
  assert "toutes fenêtres nulles : sonde en panne, code non nul (jamais « compte sain »)" $?
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

# --- C3 : épuisement et heure de réveil sont deux questions distinctes ---

test_quota_reveil_sur_la_fenetre_bloquante_la_plus_proche() {
  cat > "$FIX/deux_bloquantes.json" <<'J'
{"five_hour":{"utilization":96.0,"resets_at":"2026-09-18T01:40:00+00:00"},
 "seven_day":{"utilization":99.0,"resets_at":"2026-09-22T14:00:00+00:00"},
 "seven_day_opus":null,"seven_day_sonnet":null}
J
  out=$(bash "$Q" verdict "$FIX/deux_bloquantes.json")
  [ "${out%% *}" = "1" ]; assert "deux fenêtres au-dessus du seuil : épuisé" $?
  epoch=$(bash "$Q" reset-epoch "$FIX/deux_bloquantes.json")
  [ "$epoch" = "1789695600" ]
  assert "réveil sur le reset le plus proche des fenêtres bloquantes, pas la plus consommée" $?
}

test_quota_fenetre_bloquante_sans_reset_ignoree_pour_le_reveil() {
  cat > "$FIX/bloquante_sans_reset.json" <<'J'
{"five_hour":{"utilization":99.0,"resets_at":null},
 "seven_day":{"utilization":97.0,"resets_at":"2026-09-22T14:00:00+00:00"},
 "seven_day_opus":null,"seven_day_sonnet":null}
J
  out=$(bash "$Q" verdict "$FIX/bloquante_sans_reset.json")
  [ "${out%% *}" = "1" ]; assert "fenêtre bloquante sans resets_at : toujours épuisé" $?
  epoch=$(bash "$Q" reset-epoch "$FIX/bloquante_sans_reset.json")
  case "$epoch" in ''|-|*[!0-9]*) r=1 ;; *) r=0 ;; esac
  assert "réveil pris sur la seule fenêtre bloquante qui annonce un reset" $r
}

test_quota_reponse_401_traitee_comme_une_panne() {
  cat > "$FIX/401.json" <<'J'
{"type":"error","error":{"type":"authentication_error","message":"invalid bearer token"}}
J
  sortie=$(bash "$Q" verdict "$FIX/401.json" 2>&1)
  code=$?
  [ "$code" -ne 0 ]
  assert "réponse sans aucune fenêtre (401) : code de sortie non nul" $?
  case "$sortie" in *"0 - aucune"*) r=1 ;; *) r=0 ;; esac
  assert "réponse sans aucune fenêtre : ne prétend jamais que le compte est sain" $r
  case "$sortie" in *fenêtre*) r=0 ;; *) r=1 ;; esac
  assert "réponse sans aucune fenêtre : message d'erreur en français" $r
}

test_quota_seuil_documente_dans_la_spec() {
  grep -q '95' "$ROOT/docs/superpowers/specs/2026-09-17-autopilot-design.md"
  assert "le seuil de 95 % est documenté dans la spec, pas seulement dans le script" $?
}
