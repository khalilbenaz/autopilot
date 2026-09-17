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
  [ "$(bash "$D" "$d")" = "amelioration" ]
  assert "seulement un README.md : amélioration (fichier visible = conforme au brief)" $?
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
  if [ "$(id -u)" -eq 0 ]; then
    assert "dossier sans droit de lecture : ignoré (exécution en root)" 0
    return
  fi
  d=$(mktemp -d)
  chmod 000 "$d"
  [ "$(bash "$D" "$d")" = "amelioration" ]
  assert "dossier sans droit de lecture : amélioration par prudence" $?
  chmod 700 "$d"
  rm -rf "$d"
}

# --- C2 : un composant caché dans le chemin d'invocation ne doit rien changer ---

test_detect_parent_cache_dans_le_chemin() {
  base=$(mktemp -d)
  d="$base/.cache/monprojet"
  mkdir -p "$d"
  echo 'print(1)' > "$d/main.py"
  [ "$(bash "$D" "$d")" = "amelioration" ]
  assert "code sous un dossier parent caché : amélioration" $?
  rm -rf "$base"
}

test_detect_parent_cache_et_dossier_vide() {
  base=$(mktemp -d)
  d="$base/.config/monprojet"
  mkdir -p "$d"
  [ "$(bash "$D" "$d")" = "creation" ]
  assert "dossier vide sous un parent caché : création" $?
  rm -rf "$base"
}

test_detect_fichier_visible_dans_sous_dossier_cache() {
  d=$(mktemp -d)
  mkdir -p "$d/.venv"
  echo 'x' > "$d/.venv/pyvenv.cfg"
  [ "$(bash "$D" "$d")" = "creation" ]
  assert "fichier visible sous un sous-dossier caché : création (contenu caché non compté)" $?
  rm -rf "$d"
}
