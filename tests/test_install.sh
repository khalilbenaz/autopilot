I="$ROOT/install.sh"

test_install_cree_le_lien() {
  faux_home=$(mktemp -d)
  HOME="$faux_home" bash "$I" >/dev/null 2>&1
  [ -L "$faux_home/.claude/skills/autopilot" ]
  assert "install.sh crée le lien symbolique" $?
  [ -f "$faux_home/.claude/skills/autopilot/SKILL.md" ]
  assert "le lien pointe sur une skill lisible" $?
  rm -rf "$faux_home"
}

test_install_idempotent() {
  faux_home=$(mktemp -d)
  HOME="$faux_home" bash "$I" >/dev/null 2>&1
  HOME="$faux_home" bash "$I" >/dev/null 2>&1
  assert "deux installations de suite ne cassent rien" $?
  rm -rf "$faux_home"
}

test_install_refuse_d_ecraser_un_vrai_dossier() {
  faux_home=$(mktemp -d)
  mkdir -p "$faux_home/.claude/skills/autopilot"
  echo "contenu précieux" > "$faux_home/.claude/skills/autopilot/garde.md"
  HOME="$faux_home" bash "$I" >/dev/null 2>&1
  [ -f "$faux_home/.claude/skills/autopilot/garde.md" ]
  assert "un dossier existant n'est jamais écrasé" $?
  rm -rf "$faux_home"
}

test_tous_les_scripts_sont_executables() {
  manquants=0
  for s in "$ROOT"/skill/scripts/*.sh; do
    [ -x "$s" ] || manquants=$((manquants+1))
  done
  [ "$manquants" -eq 0 ]; assert "tous les scripts sont exécutables" $?
}

test_shellcheck_propre() {
  command -v shellcheck >/dev/null || { assert "shellcheck absent, ignoré" 0; return; }
  # tests/*.sh sont exclus : ces fichiers sont sourcés par tests/run.sh (pas
  # exécutés directement) et n'ont donc pas de shebang, ce qui fait hurler
  # shellcheck (SC2148) et produit du bruit sans rapport avec le code
  # (SC2319, SC1010 liés au harnais). Seuls les scripts réellement exécutés
  # de façon autonome sont vérifiés ici.
  shellcheck "$ROOT"/skill/scripts/*.sh "$ROOT"/install.sh "$ROOT"/tests/run.sh
  assert "shellcheck ne signale rien" $?
}

test_install_gere_un_chemin_avec_espace() {
  faux_home=$(mktemp -d "/tmp/autopilot home XXXXXX")
  HOME="$faux_home" bash "$I" >/dev/null 2>&1
  [ -L "$faux_home/.claude/skills/autopilot" ]
  assert "install.sh fonctionne même si \$HOME contient une espace" $?
  rm -rf "$faux_home"
}

test_install_remplace_un_lien_qui_pointe_ailleurs() {
  faux_home=$(mktemp -d)
  autre_cible=$(mktemp -d)
  mkdir -p "$faux_home/.claude/skills"
  ln -s "$autre_cible" "$faux_home/.claude/skills/autopilot"
  HOME="$faux_home" bash "$I" >/dev/null 2>&1
  lien_cible=$(readlink "$faux_home/.claude/skills/autopilot")
  [ "$lien_cible" = "$ROOT/skill" ]
  assert "un lien existant vers ailleurs est remplacé par le bon" $?
  rm -rf "$faux_home" "$autre_cible"
}

test_install_sans_dossier_claude() {
  faux_home=$(mktemp -d)
  HOME="$faux_home" bash "$I" >/dev/null 2>&1
  [ -L "$faux_home/.claude/skills/autopilot" ]
  assert "un \$HOME sans .claude préexistant fonctionne aussi" $?
  rm -rf "$faux_home"
}

test_install_ne_ment_pas_en_cas_d_echec() {
  if [ "$(id -u)" -eq 0 ]; then
    assert "root ignore les permissions, test sauté" 0
    return
  fi
  faux_home=$(mktemp -d)
  chmod 500 "$faux_home"
  sortie=$(HOME="$faux_home" bash "$I" 2>&1)
  code=$?
  chmod 700 "$faux_home"
  [ "$code" -ne 0 ]
  assert "\$HOME non inscriptible : code de sortie non nul" $?
  ! printf '%s' "$sortie" | grep -q 'installée'
  assert "\$HOME non inscriptible : n'affiche rien qui ressemble à un succès" $?
  rm -rf "$faux_home"
}

test_install_verifie_reellement_le_lien_pose() {
  faux_home=$(mktemp -d)
  HOME="$faux_home" bash "$I" >/dev/null 2>&1
  cible=$(readlink "$faux_home/.claude/skills/autopilot")
  [ "$cible" = "$ROOT/skill" ]
  assert "après succès, readlink rend bien le chemin de skill/" $?
  rm -rf "$faux_home"
}
