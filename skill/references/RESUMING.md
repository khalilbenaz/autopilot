# RESUMING — l'état vit sur disque, jamais dans la conversation

## Le contenu de `.autopilot/`

À la racine du dossier cible, hors du suivi git. L'étape d'amorçage
(`SKILL.md`, section « Démarrage ») ajoute `.autopilot/` au `.gitignore`
du projet livré avant le premier commit, en création comme en
amélioration :

| Fichier | Contenu |
|---|---|
| `STATE.json` | mode (`creation`/`amelioration`), phase courante, tâche en cours, chemins de la spec et du plan, nom de la branche, chemin du worktree, compteur de cycles |
| `LEDGER.md` | journal **append-only** de tous les événements, de tous les Rulings et des arrêts, jamais tronqué, jamais réécrit |
| `RESUME.md` | résumé lisible par un humain, régénéré à chaque `set` : où en est le travail, quelle est la prochaine action |

La « prochaine action » de `RESUME.md` et la table des phases ci-dessous sont
deux vues de la même règle et ne peuvent pas diverger : un test du harnais
compare, phase par phase, le numéro d'étape annoncé par l'une et par l'autre.

Ces trois fichiers sont gérés exclusivement par
`scripts/autopilot-state.sh` (`init`, `set`, `get`, `ledger`, `done`).
Autopilot ne les modifie jamais à la main.

`set` n'accepte ni clé ni phase inventée : la clé doit appartenir au schéma
de `STATE.json` et, pour `phase`, la valeur doit être l'une des phases
légales listées plus bas. Tout autre appel est refusé en code non nul, avec
un message qui nomme les valeurs acceptées — une clé mal orthographiée
créerait un champ fantôme à côté du vrai, et une phase inventée ferait
relancer `claude` indéfiniment par le superviseur, puisqu'elle ne serait ni
`termine` ni `bloque`.

Le champ `cycles` de `STATE.json` appartient exclusivement à
`autopilot-supervisor.sh` : c'est lui qui l'incrémente à chaque relance.
La skill peut le lire, mais ne l'écrit jamais — ce n'est pas une donnée
de son ressort.

## Les phases légales

`phase` ne prend que les valeurs ci-dessous — aucun autre libellé n'est
inventé, celles-ci sont les mêmes que celles déjà produites par
`autopilot-state.sh` (fonction `ecrire_resume`), plus `bloque` :

| Phase | Correspond à, dans le tableau de `SKILL.md` |
|---|---|
| `init` | étapes 0 et 1/1′ : détection du mode, amorçage ou isolation |
| `conception` | étape 2 : `brainstorming`, spec écrite, pile choisie |
| `plan` | étape 3 : `writing-plans` |
| `execution` | étapes 4, 5 et 5b : `subagent-driven-development`, `test-driven-development`, `systematic-debugging` si besoin |
| `revue` | étapes 6 et 7 : `requesting-code-review`, `receiving-code-review` |
| `verification` | étape 8 : `verification-before-completion` |
| `termine` | étape 9 : rapport final envoyé, run terminé (`autopilot-state.sh done` devient vrai) |
| `bloque` | un des quatre arrêts de `AUTONOMY.md` a été rencontré ; le run est arrêté, pas terminé |

La phase inscrite dans `STATE.json` est la phase **en cours**, jamais celle
qui vient d'être terminée. Elle s'écrit donc à l'**entrée** de chaque phase
(voir `SKILL.md`, section « Checkpoints et reprise »), et pas seulement au
checkpoint de fin de tâche : sans ça, la phase resterait `init` pendant toute
la conception et toute la planification, et une coupure dans cet intervalle
renverrait la reprise à l'étape 0 — ré-amorçage et spec réécrite.

Une reprise lit cette phase et reprend l'étape correspondante du tableau,
jamais une étape avant (travail déjà commité refait en double) ni après
(une vérification sautée).

## Un commit par tâche

Chaque tâche terminée du plan se ferme par un commit git sur la branche de
travail, immédiatement suivi de `autopilot-state.sh set` (pour avancer la
phase/tâche courante) et `autopilot-state.sh ledger` (pour consigner
l'événement de fin de tâche). L'ordre est important : le commit d'abord,
puis la mise à jour de l'état, pour que l'état ne prétende jamais qu'une
tâche est faite avant que git ne le confirme.

Les Rulings, eux, ne sont jamais mis en attente jusqu'à ce checkpoint : ils
sont consignés au ledger au moment où la décision est prise, pendant la
tâche, pas seulement à sa clôture. Voir `AUTONOMY.md`.

## `--force` : seulement sur demande explicite

`autopilot-state.sh init <dossier> <mode> "<demande>" --force` écrase un
état existant (phase remise à `init`, tâche et branche vidées) sans
toucher au ledger, qui n'est jamais tronqué. Ni le démarrage normal ni la
reprise n'appellent jamais `--force` : cet appel n'a lieu que si
l'utilisateur demande explicitement d'abandonner le run en cours et de
repartir de zéro sur le même dossier. En dehors de cette demande
explicite, un état déjà présent signifie toujours une reprise (voir plus
bas), jamais une réinitialisation.

## Procédure de reprise, pas à pas

Quand autopilot est invoquée avec « reprise » — que ce soit par le
superviseur ou manuellement — elle exécute, dans l'ordre :

1. lire `.autopilot/RESUME.md` pour la vue d'ensemble lisible ;
2. lire `.autopilot/STATE.json` pour les valeurs exactes (`phase`,
   `tache`, `mode`, `spec`, `plan`, `branche`, `worktree`) ;
3. si le mode est `amelioration`, se replacer dans le worktree (clé
   `worktree`, chemin absolu) et sur la branche (clé `branche`) nommés dans
   `STATE.json`, pas dans l'arbre de travail principal ;
4. si la phase vaut `bloque`, ne rien reprendre automatiquement : lire au
   ledger la raison de l'arrêt et attendre une décision humaine (c'est
   l'un des quatre cas de `AUTONOMY.md`, pas une interruption ordinaire) ;
5. sinon, reprendre le flux décrit dans `SKILL.md` exactement à l'étape du
   tableau associée à la phase constatée, en repartant de la tâche nommée
   dans `STATE.json` (celle-ci n'a pas encore de commit qui la clôture) ;
6. consigner la reprise elle-même dans le ledger avant de continuer, pour
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

Un sommeil réel de plusieurs jours (le cas où `autopilot-supervisor.sh`
attend la réinitialisation d'un quota hebdomadaire) ne survit ni à un
redémarrage de la machine ni à un `SIGTERM` envoyé au superviseur : le
processus qui dort meurt, et rien ne le relance de lui-même. **Ce n'est
pas au superviseur de couvrir ce cas.** C'est la reprise depuis le disque,
décrite ci-dessus, qui le couvre : comme l'état complet du run vit dans
`.autopilot/` et non dans la mémoire du processus qui dormait, relancer
`autopilot-supervisor.sh <dossier>` après une coupure de ce genre est une
**opération normale et sans perte**. Le superviseur relancé au
redémarrage retrouve exactement la même phase, la même tâche courante et
le même ledger que juste avant la coupure, et reprend le travail comme
n'importe quelle autre interruption — il n'y a rien de spécial à faire, et
rien à récupérer à la main.
