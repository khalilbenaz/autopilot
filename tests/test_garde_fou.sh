# Le garde-fou anti-orphelin de tests/run.sh ne doit signaler que les
# processus autopilot-watch.sh / autopilot-supervisor.sh apparus PENDANT la
# suite, jamais un superviseur de production déjà présent avant (voir
# tests/lib-garde-fou.sh, source dans tests/run.sh avant le premier test).

garde_fou_attendre_vivant() { # pid
  tries=0
  while ! kill -0 "$1" 2>/dev/null && [ "$tries" -lt 2000 ]; do
    date +%s%N >/dev/null 2>&1
    tries=$((tries + 1))
  done
}

test_garde_fou_process_avant_la_suite_ne_fait_pas_echouer() {
  bin=$(mktemp -d)
  cat > "$bin/autopilot-supervisor.sh" <<'EOS'
#!/usr/bin/env bash
while :; do :; done
EOS
  chmod +x "$bin/autopilot-supervisor.sh"
  "$bin/autopilot-supervisor.sh" &
  pid_avant=$!
  garde_fou_attendre_vivant "$pid_avant"

  # La baseline est relevée APRÈS le démarrage : exactement le cas d'un
  # superviseur de production déjà en cours quand la suite démarre.
  avant=$(garde_fou_relever)
  nouveaux=$(garde_fou_nouveaux "$avant")

  case "$nouveaux" in *"$pid_avant"*) r=1 ;; *) r=0 ;; esac
  assert "garde-fou : processus déjà présent avant la période n'est pas signalé" $r

  kill "$pid_avant" 2>/dev/null
  wait "$pid_avant" 2>/dev/null
  rm -rf "$bin"
}

test_garde_fou_process_pendant_la_suite_fait_echouer() {
  bin=$(mktemp -d)
  # Baseline relevée AVANT tout démarrage : le processus qui suit n'y figure
  # pas, donc apparaît « pendant » du point de vue du garde-fou.
  avant=$(garde_fou_relever)

  cat > "$bin/autopilot-watch.sh" <<'EOS'
#!/usr/bin/env bash
while :; do :; done
EOS
  chmod +x "$bin/autopilot-watch.sh"
  "$bin/autopilot-watch.sh" &
  pid_pendant=$!
  garde_fou_attendre_vivant "$pid_pendant"

  nouveaux=$(garde_fou_nouveaux "$avant")

  case "$nouveaux" in *"$pid_pendant"*) r=0 ;; *) r=1 ;; esac
  assert "garde-fou : processus apparu pendant la période est signalé" $r
  case "$nouveaux" in *"autopilot-watch.sh"*) r=0 ;; *) r=1 ;; esac
  assert "garde-fou : la ligne de commande du fautif est incluse dans le signalement" $r

  kill "$pid_pendant" 2>/dev/null
  wait "$pid_pendant" 2>/dev/null
  rm -rf "$bin"
}

test_garde_fou_aucun_survivant_avant_ni_pendant() {
  avant=$(garde_fou_relever)
  nouveaux=$(garde_fou_nouveaux "$avant")
  [ -z "$nouveaux" ]
  assert "garde-fou : rien à signaler quand aucun orphelin n'apparaît" $?
}
