D="$ROOT/skill/scripts/autopilot-detect.sh"

test_detect_dossier_absent() {
  [ "$(bash "$D" /tmp/autopilot-inexistant-$$)" = "creation" ]
  assert "dossier absent : création" $?
}

test_detect_dossier_vide() {
  d=$(mktemp -d)
  [ "$(bash "$D" "$d")" = "creation" ]; assert "dossier vide : création" $?
  rm -rf "$d"
}

test_detect_seulement_caches() {
  d=$(mktemp -d); touch "$d/.DS_Store"
  [ "$(bash "$D" "$d")" = "creation" ]; assert "fichiers cachés seuls : création" $?
  rm -rf "$d"
}

test_detect_repo_avec_code() {
  d=$(mktemp -d); (cd "$d" && git init -q); echo 'print(1)' > "$d/main.py"
  [ "$(bash "$D" "$d")" = "amelioration" ]; assert "dépôt avec code : amélioration" $?
  rm -rf "$d"
}

test_detect_code_sans_git() {
  d=$(mktemp -d); echo 'print(1)' > "$d/main.py"
  [ "$(bash "$D" "$d")" = "amelioration" ]; assert "code sans dépôt : amélioration" $?
  rm -rf "$d"
}

test_detect_repo_vide() {
  d=$(mktemp -d); (cd "$d" && git init -q)
  [ "$(bash "$D" "$d")" = "creation" ]; assert "dépôt sans code : création" $?
  rm -rf "$d"
}

# --- Cas limites ajoutés ---

test_detect_chemin_avec_espace() {
  base=$(mktemp -d)
  d="$base/mon dossier"
  mkdir -p "$d"
  echo 'print(1)' > "$d/main.py"
  [ "$(bash "$D" "$d")" = "amelioration" ]; assert "chemin avec espace et code : amélioration" $?
  rm -rf "$base"
}

test_detect_chemin_avec_espace_vide() {
  base=$(mktemp -d)
  d="$base/mon dossier vide"
  mkdir -p "$d"
  [ "$(bash "$D" "$d")" = "creation" ]; assert "chemin avec espace, vide : création" $?
  rm -rf "$base"
}

test_detect_seulement_sous_dossier_vide() {
  d=$(mktemp -d)
  mkdir -p "$d/vide"
  [ "$(bash "$D" "$d")" = "creation" ]; assert "un seul sous-dossier vide : création" $?
  rm -rf "$d"
}

test_detect_seulement_readme() {
  d=$(mktemp -d)
  echo '# Mon projet' > "$d/README.md"
  [ "$(bash "$D" "$d")" = "creation" ]; assert "seulement un README.md : création" $?
  rm -rf "$d"
}

test_detect_readme_et_code() {
  d=$(mktemp -d)
  echo '# Mon projet' > "$d/README.md"
  echo 'print(1)' > "$d/main.py"
  [ "$(bash "$D" "$d")" = "amelioration" ]; assert "README.md + code : amélioration" $?
  rm -rf "$d"
}

test_detect_lien_symbolique_seul() {
  base=$(mktemp -d)
  echo 'print(1)' > "$base/main.py"
  d=$(mktemp -d)
  ln -s "$base/main.py" "$d/main.py"
  [ "$(bash "$D" "$d")" = "amelioration" ]; assert "lien symbolique seul : amélioration" $?
  rm -rf "$d" "$base"
}

test_detect_dossier_illisible() {
  d=$(mktemp -d)
  chmod 000 "$d"
  [ "$(bash "$D" "$d")" = "amelioration" ]
  assert "dossier sans droit de lecture : amélioration par prudence" $?
  chmod 700 "$d"
  rm -rf "$d"
}
