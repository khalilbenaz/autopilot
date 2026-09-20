# autopilot — skill de livraison autonome

## Problème

Livrer un projet, neuf ou existant, demande aujourd'hui d'enchaîner à la main
une dizaine de skills superpowers et de relancer le travail à chaque
interruption. Deux manques précis :

1. superpowers suppose un dépôt existant — rien ne couvre le démarrage d'un
   projet neuf.
2. le flux s'arrête deux fois pour demander un avis, ce qui interdit une
   exécution longue sans surveillance.

S'y ajoute une contrainte propre à l'environnement : quand le quota Claude est
épuisé, la session s'arrête et tout le travail en cours est perdu s'il ne vit
que dans la conversation.

## Ce qui est livré

Une skill personnelle `autopilot`, installée dans `~/.claude/skills/autopilot`,
qui prend une demande en langage naturel et livre une branche locale avec des
tests verts, sans rien demander en route.

## Portée

### Inclus
- détection automatique du mode : création d'un projet neuf, ou amélioration
  d'un projet existant
- amorçage d'un projet neuf : dépôt, `.gitignore`, premier commit — sans rien
  présumer de la pile technique, que la conception choisit. Il n'y a pas encore
  de harnais de test à ce stade : la baseline verte est une exigence du **mode
  amélioration**, où un harnais existe déjà et doit passer avant qu'on y touche.
- traversée du Basic Workflow superpowers, gates retirées
- reprise après n'importe quelle interruption, depuis l'état sur disque
- un superviseur qui attend la réinitialisation du quota et relance le travail
- un veilleur optionnel (activé par défaut) qui surveille le quota
  **pendant** qu'une session travaille, pour que la skill s'arrête d'elle-même
  entre deux tâches plutôt que de se faire couper au milieu

### Conditionnel
- merge, push, publication, déploiement — jamais de la propre initiative
  d'autopilot ; exécutés seulement quand la demande de l'utilisateur les
  réclame explicitement, un par un, après tests verts, dépôt créé privé
  par défaut, opérations git destructives toujours nommées à part — voir
  `skill/references/AUTONOMY.md` (section « Actes sortants »)

### Exclu
- toute modification hors du répertoire de travail du projet, réversible ou non
- remplacement des skills superpowers : autopilot les appelle, ne les réécrit
  pas

## Architecture

```
~/Projects/autopilot/              dépôt de développement
  skill/
    SKILL.md                       orchestrateur
    references/
      MODES.md                     création vs amélioration
      AUTONOMY.md                  Rulings et vrais blocages
      DELIVERY.md                  définition de « fini »
      RESUMING.md                  protocole de reprise
    scripts/
      autopilot-detect.sh          mode création ou amélioration
      autopilot-state.sh           état, journal, document de reprise
      autopilot-quota.sh           quota annoncé et heure de reset
      autopilot-supervisor.sh      attente du reset et relance
  tests/                           harnais bash
~/.claude/skills/autopilot -> ~/Projects/autopilot/skill
```

Le lien symbolique rend la skill vivante sans dupliquer les fichiers.

### Unités et responsabilités

| Unité | Fait | Dépend de |
|---|---|---|
| `SKILL.md` | décide du mode, ordonne les étapes, délègue | les 4 références |
| `MODES.md` | règles de détection, ce qui change entre les 2 modes | — |
| `AUTONOMY.md` | ce qui se tranche seul, ce qui arrête, format des Rulings | — |
| `DELIVERY.md` | preuves exigées avant de dire « fini » | — |
| `RESUMING.md` | format de l'état, comment repartir | — |
| `autopilot-supervisor.sh` | boucle de relance, attente du reset | état sur disque |

Chaque référence est lisible seule et ne connaît pas les autres. `SKILL.md` est
le seul point qui les compose.

## Flux

| # | Étape | Skill superpowers | Mode |
|---|---|---|---|
| 0 | détection du mode | — | les deux |
| 1 | amorçage neutre : dépôt, `.gitignore`, premier commit | — | création |
| 1′ | espace isolé sur une branche | `using-git-worktrees` | amélioration |
| 2 | conception, auto-approuvée, spec écrite | `brainstorming` | les deux |
| 3 | plan en tâches de 2 à 5 minutes | `writing-plans` | les deux |
| 4 | exécution, un sous-agent par tâche | `subagent-driven-development` | les deux |
| 5 | rouge-vert-refactor dans chaque tâche | `test-driven-development` | les deux |
| 5b | cause racine avant tout correctif | `systematic-debugging` | si un test casse |
| 6 | revue contre le plan | `requesting-code-review` | les deux |
| 7 | traitement des retours | `receiving-code-review` | les deux |
| 8 | preuves avant toute affirmation | `verification-before-completion` | les deux |
| 9 | rapport final | — | les deux |

L'étape 2 est auto-approuvée : la spec est écrite et commitée avant toute ligne
de code, ce qui laisse la possibilité de la lire et d'interrompre, mais la skill
n'attend pas.

« Auto-approuvée » n'est pas un adjectif : c'est un mécanisme. Les skills
déléguées portent des portes d'approbation explicites — le `<HARD-GATE>` de
`brainstorming`, la demande de consentement de `using-git-worktrees`, sa
question sur une baseline rouge — qui, sous `claude -p`, attendraient une
réponse que personne ne donnera. `SKILL.md` lève ces portes une à une, par
écrit et à l'avance, en s'appuyant sur la règle de `using-superpowers` selon
laquelle les instructions de l'utilisateur priment sur les skills : invoquer
autopilot **vaut** l'approbation humaine attendue, et la préférence de worktree
est déclarée au lieu d'être demandée. Sans cette levée écrite, le premier run
s'arrête à l'étape 2.

## Détection du mode

Sur le répertoire cible :

- absent, vide, ou ne contenant que des fichiers cachés → **création**
- contenant au moins un fichier visible → **amélioration**, avec ou sans dépôt git

La présence d'un dépôt git n'entre pas dans la décision, et aucun type de fichier
n'est privilégié : un dossier ne contenant qu'un `README.md` est une amélioration.
Se tromper vers `création` ferait échafauder par-dessus une intention déjà écrite,
ce qui coûte bien plus cher que l'erreur inverse.

Aucune question n'est posée pour trancher. Le mode retenu est annoncé en une
ligne et consigné dans l'état.

## Autonomie

Tout choix se tranche et se consigne :

```
Ruling: <décision> — <pourquoi> — <coût si faux>
```

Quatre situations, et seulement elles, arrêtent le travail :

1. identifiants ou accès réseau manquants
2. toute **écriture** hors du répertoire de travail, réversible ou non
3. action sensible côté sécurité
4. demande si vague qu'aucune interprétation n'est défendable

## État et reprise

Sous `.autopilot/` à la racine du projet, hors du suivi git :

| Fichier | Contenu |
|---|---|
| `STATE.json` | mode, phase, tâche courante, chemins de la spec et du plan, branche, worktree, compteur de cycles |
| `LEDGER.md` | journal append-only des Rulings et des événements |
| `RESUME.md` | lisible par un humain : où on en est, quelle est la suite |

Un commit git par tâche terminée. La reprise lit ces fichiers et le journal git,
jamais un souvenir de conversation. Elle vaut pour toute interruption, pas
seulement le quota.

`STATE.json` est toujours réécrit **atomiquement** — fichier temporaire dans le
même dossier, puis `os.replace` — parce qu'une écriture qui tronque avant
d'écrire laisserait, sur la coupure que cette reprise est censée couvrir, un
état corrompu donc un run irrécupérable. Un état illisible ne se confond jamais
avec « pas terminé » : `autopilot-state.sh` le signale en français avec un code
de sortie dédié, et le superviseur s'arrête (code `2`) en le consignant, au lieu
de brûler ses cycles sur un état mort.

`set` n'accepte que les clés du schéma et, pour `phase`, les seules phases
légales ; tout le reste est refusé en code non nul.

## Superviseur

`autopilot-supervisor.sh <dossier>` boucle :

1. si `STATE.json` est marqué terminé → sortir
2. lancer `claude -p "autopilot reprise"` dans le dossier
3. sortie propre → retour à 1
4. sortie non nulle → **interroger la sonde de quota** ; si le compte est épuisé,
   obtenir l'heure de réinitialisation, dormir jusque-là avec une marge, retour
   à 2 ; sinon, courte pause d'erreur et retour à 2

Le superviseur ne peut pas se fier à un code de sortie convenu : un agent lancé
par `claude -p` ne choisit pas le code de sortie du processus, et `claude` n'en
documente aucun pour l'épuisement de quota. C'est donc la sonde qui tranche, et
elle seule. Un code de sortie dédié reste accepté comme raccourci, jamais comme
unique signal.

Source de l'heure de réinitialisation, **vérifiée en direct le 17/09/2026**
contre l'API et alignée sur l'implémentation éprouvée de `doublure` :

| Élément | Valeur constatée |
|---|---|
| Endpoint | `https://api.anthropic.com/api/oauth/usage` |
| En-têtes | `Authorization: Bearer <jeton>`, `anthropic-beta: oauth-2025-04-20` |
| Jeton | trousseau macOS, service `Claude Code-credentials`, champ `claudeAiOauth.accessToken` |
| Fenêtres | `five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet` |
| Champs | `utilization` (0 à 100), `resets_at` (ISO 8601) |
| Secours | tableau `limits[]` : `kind`, `percent`, `resets_at` |

`seven_day_opus` et `seven_day_sonnet` valent `null` sur ce compte : une
fenêtre absente ou nulle est ignorée sans erreur, une par une.

La sonde répond à **deux questions distinctes**, qu'elle ne confond jamais :

| Question | Réponse |
|---|---|
| le compte est-il épuisé ? | oui si **au moins une** fenêtre atteint le seuil de **95 %** |
| quand se réveiller ? | le `resets_at` **le plus proche parmi les fenêtres bloquantes** |

Le seuil est de **95 %** d'utilisation annoncée. Il vaut d'être écrit ici et
pas seulement dans le script : c'est lui qui décide de sommeils pouvant durer
plusieurs jours.

Retenir « la fenêtre la plus consommée » pour les deux questions à la fois est
faux dans les deux sens : une fenêtre `seven_day` à 96 % ferait dormir six
jours alors qu'une fenêtre `five_hour` bloquante rouvre dans l'heure, et un
relevé sans aucune fenêtre — une réponse 401, l'endpoint modifié, toutes les
fenêtres à `null` — ressemblerait à un compte à 0 %, donc sain. Un relevé sans
**aucune** fenêtre exploitable est donc traité comme une **sonde en panne** :
code de sortie non nul, message en français, jamais « compte sain ». Le
superviseur retombe alors sur son attente à intervalle fixe.

Si la sonde échoue — réseau, jeton absent, endpoint modifié — le superviseur
retombe sur une attente à intervalle fixe et le consigne, plutôt que de traiter
un silence comme une autorisation de repartir.

Garde-fous : nombre maximal de cycles, budget d'attente cumulée, journal de ses
propres décisions dans `LEDGER.md`, arrêt net si le dossier disparaît.

Le superviseur lance `claude -p` avec un **mode de permission explicite**,
`acceptEdits` par défaut, réglable par `--permission-mode` : sous `--print`,
sans mode, toute opération demandant une permission est refusée et l'agent ne
peut rien écrire. `bypassPermissions` reste disponible mais n'est pas le
défaut — un agent non surveillé qui accepte les éditions de fichiers est ce
qu'on veut, un agent qui contourne toute permission ne l'est pas.

Un cycle qui se termine en code 0 sans que `phase` ni `tache` n'aient bougé est
un cycle stérile. Le superviseur relève l'état avant et après chaque cycle et
abandonne après `--max-cycles-sans-progres` cycles stériles consécutifs (3 par
défaut), au lieu d'enchaîner des sessions vides sans une ligne de journal.

Codes de sortie : `0` travail terminé, `1` plafond de cycles ou budget d'attente
épuisé, `2` dossier ou état absent, `3` phase `bloque` — un blocage réel qui
demande une décision humaine —, `4` aucun progrès pendant plusieurs cycles
consécutifs. La phase `bloque` est terminale : le superviseur
sort sans lancer `claude`, et `RESUME.md` doit dire qu'aucune reprise
automatique n'aura lieu.

### Veilleur : surveillance continue pendant qu'une session travaille

Ce qui précède est **réactif** : la sonde n'est interrogée qu'**après** une
sortie non nulle de `claude -p`, jamais pendant qu'il travaille. Une session
peut donc être coupée par l'épuisement du quota au milieu de ce qu'elle
faisait ; ce qui est commité survit, le reste est refait au cycle suivant —
indolore, mais gaspilleur.

`autopilot-watch.sh <dossier> [--seuil N] [--intervalle S]` tourne **en
parallèle** d'une session `claude -p`, lancé par le superviseur juste avant
chaque appel et arrêté juste après (jamais par la skill elle-même). Boucle :
interroger `autopilot-quota.sh verdict`, écrire l'état du tour dans
`.autopilot/QUOTA.json` (utilisation constatée, fenêtre concernée,
`resets_at`, si la sonde a répondu, horodatage), dormir `--intervalle`
secondes (5 min par défaut), recommencer. Il s'arrête de lui-même si le
dossier disparaît, si `STATE.json` devient illisible, ou si la phase vaut
`termine` ou `bloque`. Il écrit son PID dans `.autopilot/watch.pid`.

Dès que l'utilisation atteint le **seuil d'alerte** (**90 %** par défaut,
réglable par `--seuil`), il crée `.autopilot/QUOTA_ALERTE`, et l'efface dès
que l'utilisation redescend en dessous. Ce seuil est **volontairement sous**
le seuil d'épuisement de la sonde (95 %, voir plus haut) : la **marge** de
5 points laisse à la skill le temps de finir la tâche en cours et de
commiter avant que le compte ne soit réellement coupé. Une sonde en panne ne
crée **jamais** d'alerte — un silence réseau ne doit pas suspendre le
travail — et n'efface pas non plus une alerte déjà posée ; la panne est
consignée dans `QUOTA.json` et au ledger, une seule fois par série de pannes
consécutives, jamais à chaque tour.

Le fichier `QUOTA_ALERTE` est un pur signal, lu à deux endroits :

1. **La skill, entre deux tâches du plan.** Avant de démarrer la tâche
   suivante, elle lit `.autopilot/QUOTA_ALERTE`. S'il existe : elle ne
   démarre pas la tâche suivante, s'assure que la tâche terminée est
   commitée et que `phase`/`tache` reflètent l'état réel, consigne au
   ledger un arrêt volontaire avant épuisement en nommant l'utilisation
   constatée, et rend la main. La phase **reste celle en cours** — ce n'est
   pas un des quatre arrêts de `AUTONOMY.md`, pas une décision humaine à
   attendre, juste une pause technique dont le superviseur se charge ; la
   reprise suivante enchaîne donc normalement.
2. **Le superviseur, avant chaque nouveau cycle.** Si `QUOTA_ALERTE` existe,
   il attend la réinitialisation du quota **même si la sonde ne dit pas
   encore « épuisé »** (même mécanisme d'attente que la voie réactive :
   interroger la sonde pour l'heure de réveil, dormir avec budget). Sans ce
   garde-fou, la skill se serait arrêtée proprement à 90 % et le
   superviseur l'aurait relancée aussitôt, annulant tout le bénéfice de
   s'être arrêtée tôt. L'alerte est effacée après cette attente, juste
   avant de relancer.

**Limite assumée, documentée plutôt que masquée** : l'arrêt ne peut avoir
lieu qu'**entre deux tâches**, jamais au milieu d'une. Interrompre en cours
de tâche laisserait du travail à moitié fait et non commité — pire que la
coupure brutale que cette fonctionnalité cherche à éviter. La surveillance
sert donc à ne pas *démarrer* une tâche qu'on ne pourra pas finir, pas à
couper en cours de route ; une tâche anormalement longue peut donc encore se
faire couper par le quota réel, exactement comme avant.

`--sans-veilleur` désactive tout ceci et restaure le comportement
purement réactif décrit plus haut : aucun `autopilot-watch.sh` n'est lancé,
et une alerte déjà présente sur disque est ignorée. `--seuil-alerte N`
(défaut 90) et `--intervalle-veille S` (défaut 300) règlent le veilleur
depuis le superviseur.

Nettoyage du veilleur, **le risque principal de cette fonctionnalité** : un
veilleur orphelin qui sonderait l'API indéfiniment serait pire que
l'absence de la fonctionnalité. Le superviseur pose un `trap` sur `EXIT`,
`INT` et `TERM` qui tue le veilleur par son PID — vérifié vivant avant
d'être tué, toléré déjà mort, fichier PID nettoyé dans tous les cas.
`claude` lui-même est lancé en arrière-plan puis attendu par `wait` plutôt
qu'au premier plan : sous bash, un trap n'est vérifié qu'aux limites de
commande, et l'exécution au premier plan d'un `claude -p` qui ne rend
jamais la main aurait retardé ce nettoyage indéfiniment.

## Tests

Harnais bash sans dépendance, dans `tests/`, lancé par `tests/run.sh`.

| Cible | Vérifie |
|---|---|
| détection du mode | les trois cas : dossier absent, vide, dépôt avec code |
| état | écriture, relecture, reprise après coupure simulée |
| superviseur | boucle, sortie propre, plafond de cycles, dossier disparu, attente sur alerte, veilleur tué sans orphelin |
| veilleur | seuil franchi/redescendu, sonde en panne sans alerte, arrêts de lui-même, PID écrit et nettoyé |
| qualité | `shellcheck` sans avertissement sur tous les scripts |
| skill | front-matter valide, toutes les références citées existent |

## Risques

| Risque | Traitement |
|---|---|
| détection de l'épuisement non vérifiable | repli sur intervalle fixe, limite documentée |
| boucle de relance emballée | plafond de cycles et journal |
| la skill construit dans la mauvaise direction | spec écrite et commitée avant tout code |
| dérive par rapport à superpowers | autopilot délègue, ne recopie aucune méthode |
