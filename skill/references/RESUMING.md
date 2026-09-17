# RESUMING — l'état vit sur disque, jamais dans la conversation

## Le contenu de `.autopilot/`

À la racine du dossier cible, hors du suivi git (le `.gitignore` du
projet livré doit exclure ce dossier) :

| Fichier | Contenu |
|---|---|
| `STATE.json` | mode (`creation`/`amelioration`), phase courante, tâche en cours, chemins de la spec et du plan, nom de la branche, compteur de cycles |
| `LEDGER.md` | journal **append-only** de tous les événements et de tous les Rulings, jamais tronqué, jamais réécrit |
| `RESUME.md` | résumé lisible par un humain, régénéré à chaque `set` : où en est le travail, quelle est la prochaine action |

Ces trois fichiers sont gérés exclusivement par
`scripts/autopilot-state.sh` (`init`, `set`, `get`, `ledger`, `done`).
Autopilot ne les modifie jamais à la main.

## Un commit par tâche

Chaque tâche terminée du plan se ferme par un commit git sur la branche de
travail, immédiatement suivi de `autopilot-state.sh set` (pour avancer la
phase/tâche courante) et `autopilot-state.sh ledger` (pour consigner
l'événement). L'ordre est important : le commit d'abord, puis la mise à
jour de l'état, pour que l'état ne prétende jamais qu'une tâche est faite
avant que git ne le confirme.

## Procédure de reprise, pas à pas

Quand autopilot est invoquée avec « reprise » — que ce soit par le
superviseur ou manuellement — elle exécute, dans l'ordre :

1. lire `.autopilot/RESUME.md` pour la vue d'ensemble lisible ;
2. lire `.autopilot/STATE.json` pour les valeurs exactes (`phase`,
   `tache`, `mode`, `spec`, `plan`, `branche`) ;
3. si le mode est `amelioration`, se replacer dans le worktree/la branche
   nommée dans `STATE.json`, pas dans l'arbre de travail principal ;
4. reprendre le flux décrit dans `SKILL.md` exactement à la phase
   constatée — ni avant (ce qui referait un travail déjà commité), ni
   après (ce qui saute une vérification) ;
5. consigner la reprise elle-même dans le ledger avant de continuer, pour
   que l'historique montre où et quand le travail a été interrompu puis
   repris.

## L'obligation de ne jamais reconstruire l'état depuis la conversation

Une session de conversation peut disparaître à tout moment : fin de
contexte, redémarrage de la machine, nouvelle invocation sans lien avec la
précédente. `.autopilot/` est la seule source de vérité sur l'avancement
d'un run ; un souvenir de conversation — même très détaillé — ne l'est
jamais et ne doit jamais servir à décider de la reprise. Si `STATE.json`
et le souvenir de la conversation se contredisent, `STATE.json` a raison.

## Ce que couvre la reprise, et ce qu'elle ne couvre pas

Une revue technique a établi qu'un sommeil réel de plusieurs jours (le cas
où `autopilot-supervisor.sh` attend la réinitialisation d'un quota
hebdomadaire) ne survit ni à un redémarrage de la machine ni à un
`SIGTERM` envoyé au superviseur : le processus qui dort meurt, et rien ne
le relance de lui-même. **Ce n'est pas au superviseur de couvrir ce cas.**
C'est la reprise depuis le disque, décrite ci-dessus, qui le couvre :
comme l'état complet du run vit dans `.autopilot/` et non dans la mémoire
du processus qui dormait, relancer `autopilot-supervisor.sh <dossier>`
après une coupure de ce genre est une **opération normale et sans perte**.
Le superviseur relu au redémarrage retrouve exactement la même phase, la
même tâche courante et le même ledger que juste avant la coupure, et
reprend le travail comme n'importe quelle autre interruption — il n'y a
rien de spécial à faire, et rien à récupérer à la main.
