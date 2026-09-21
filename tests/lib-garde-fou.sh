# Fonctions du garde-fou anti-orphelin (autopilot-watch.sh /
# autopilot-supervisor.sh), extraites de tests/run.sh pour être testées
# isolément par tests/test_garde_fou.sh.
#
# Principe : un superviseur de production peut légitimement tourner sur la
# machine (autre projet, lancé par la skill) pendant qu'on exécute la suite.
# Ce n'est un orphelin DE LA SUITE que s'il est apparu pendant son exécution —
# jamais s'il était déjà là avant le premier test.

GARDE_FOU_MOTIF='autopilot-watch\.sh|autopilot-supervisor\.sh'

garde_fou_relever() {
  # Affiche les PID actuellement vivants correspondant au motif, un par ligne.
  pgrep -f "$GARDE_FOU_MOTIF" 2>/dev/null
  return 0
}

garde_fou_nouveaux() {
  # $1 = PID relevés avant la période surveillée (un par ligne, éventuellement
  # une chaîne vide). Affiche une ligne "PID COMMANDE" par processus vivant
  # qui n'était PAS dans cette liste, donc apparu pendant la période. N'affiche
  # rien si tous les survivants étaient déjà présents avant.
  local avant pid reste
  avant=" $(printf '%s' "$1" | tr '\n' ' ') "
  pgrep -fl "$GARDE_FOU_MOTIF" 2>/dev/null | while IFS=' ' read -r pid reste; do
    case "$avant" in
      *" $pid "*) ;;
      *) printf '%s %s\n' "$pid" "$reste" ;;
    esac
  done
  return 0
}
