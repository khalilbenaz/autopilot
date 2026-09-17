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
  assert "toutes fenêtres nulles : pas d'erreur" $?
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
