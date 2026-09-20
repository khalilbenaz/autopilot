---
name: autopilot
description: Crée un projet neuf ou améliore un projet existant à partir d'une demande, de bout en bout et sans interruption — détection du mode, conception, plan, exécution en TDD, revue, vérification, livraison sur une branche locale. Reprend seule après une coupure ou un épuisement de quota. À utiliser quand la demande est « construis-moi X », « améliore X », « livre X de A à Z », ou toute demande de projet à mener sans surveillance.
---

# autopilot

## 1. Ce que fait la skill

autopilot prend une demande en langage naturel et livre, sans poser de
question et sans surveillance humaine, une branche locale avec des tests
verts, en enchaînant les skills superpowers du Basic Workflow. Elle ne
s'arrête que sur l'une des quatre situations décrites dans
`references/AUTONOMY.md` ; pour tout le reste, elle tranche et consigne.
Elle ne merge jamais, ne pousse jamais, ne publie jamais et ne déploie
jamais de sa propre initiative — la branche reste locale par défaut, à
livrer à un humain qui décidera de la suite. Quand la demande de
l'utilisateur réclame explicitement l'un de ces actes, c'est une partie du livrable comme une autre,
et elle le fait, dans les limites décrites dans
`references/AUTONOMY.md` (section « Actes sortants »).

Note sur les chemins : partout ci-dessous, `scripts/...` désigne un
script du dossier de la skill (celui qui contient ce fichier
`SKILL.md`), pas du dossier cible où se déroule le travail. Le dossier
de la skill est `~/.claude/skills/autopilot` (le lien symbolique posé
par l'installation) ; le dossier de travail et le dossier de la skill
sont deux endroits différents. Depuis le dossier de travail, invoque
chaque script par son chemin absolu, par exemple :

```
bash "$HOME/.claude/skills/autopilot/scripts/autopilot-detect.sh" "<dossier-cible>"
```

### Pré-approbation : invoquer autopilot vaut l'accord humain

Ce qui suit est une **instruction utilisateur**, pas une suggestion, et
s'applique à tout le run. `superpowers:using-superpowers` le dit
textuellement : « User instructions take precedence over skills. » Les
portes d'approbation des skills déléguées sont donc levées ici, par
avance et explicitement, parce qu'un run autopilot tourne typiquement
sous `claude -p`, sans personne devant le terminal pour répondre.

1. **`superpowers:brainstorming` (étape 2).** Son `<HARD-GATE>` exige
   que le partenaire humain ait approuvé l'intention avant toute action
   d'implémentation, et sa checklist « architectural » demande en plus
   que l'utilisateur relise la spec écrite. Ceci aussi est une
   **instruction utilisateur**, pas une préférence, avec la même force
   que le reste de cette pré-approbation : la classification à l'étape 2
   se tranche toujours en **architectural**, quelle que soit la taille
   apparente de la demande — même un drapeau, un endpoint, ou un
   correctif dans un seul fichier, que `brainstorming` classerait sinon
   en **Bounded**. Le chemin Bounded s'arrête à un « oui » en chat et ne
   produit ni spec ni plan ; le flux d'autopilot a besoin des deux — la
   spec écrite de l'étape 2, le plan de `writing-plans` à l'étape 3 — et
   `STATE.json` porte les clés `spec` et `plan` que seul le chemin
   architectural remplit. Sur une demande d'amélioration modeste, classer
   Bounded briserait donc ce flux. L'invocation d'autopilot par
   l'utilisateur **constitue cette approbation**, donnée d'avance et
   valable pour tout le run, y compris pour la relecture de la spec. La
   conception se mène, la spec s'écrit sous `docs/superpowers/specs/` et
   se commite, puis le travail enchaîne immédiatement sur `writing-plans`
   **sans attendre un « oui »** qui ne viendra jamais. Rien n'est sauté :
   les questions de cadrage se posent et se tranchent seules par des
   Rulings (`references/AUTONOMY.md`), et la spec, écrite et commitée
   avant toute ligne de code, reste lisible et interruptible par un
   humain — simplement, elle ne bloque pas.
2. **`superpowers:using-git-worktrees` (étape 1′).** Cette skill ne
   demande le consentement que si l'utilisateur n'a pas déjà déclaré sa
   **préférence** dans ses instructions. Elle est déclarée ici, et elle
   vaut consentement : oui, créer un espace isolé ; utiliser l'outil
   natif de worktree s'il en existe un (`EnterWorktree` ou équivalent),
   sinon le repli `git worktree add` dans `.worktrees/` à la racine du
   projet, ajouté au `.gitignore` s'il n'y est pas déjà. La question
   « Would you like me to set up an isolated worktree? » **ne se pose donc pas** :
   la réponse est donnée d'avance, c'est oui.
3. **Baseline rouge (étape 3 de `using-git-worktrees`).** Cette skill
   prévoit de demander s'il faut continuer quand le harnais existant
   échoue. La réponse est donnée d'avance elle aussi : ne pas continuer,
   et traiter ce rouge comme le prescrit `references/MODES.md` (étape 5b,
   `systematic-debugging`) avant de toucher au code — sans poser la
   question.

Cette pré-approbation ne couvre rien d'autre. Les quatre arrêts de
`references/AUTONOMY.md` restent entiers, et aucun des quatre actes
sortants — merge, push, publication, déploiement — n'est approuvé par
avance ici : chacun exige d'être nommé explicitement par la demande de
l'utilisateur, comme le prescrit `references/AUTONOMY.md` (section
« Actes sortants »).

## 2. Démarrage ou reprise : l'aiguillage

Avant tout autre chose, teste si `<dossier-cible>/.autopilot/STATE.json`
existe déjà :

- il existe → c'est une **reprise**, pas un démarrage : aller directement
  à la section 6, sans exécuter ce qui suit ;
- il n'existe pas → c'est un **démarrage**, la suite de cette section
  s'applique.

## 3. Démarrage

Sur le dossier cible :

1. `scripts/autopilot-detect.sh <dossier>` rend `creation` ou
   `amelioration`. Lire `references/MODES.md` avant d'agir sur ce
   résultat : la règle de détection y est fixée et ne se discute pas.
2. `scripts/autopilot-state.sh init <dossier> <mode> "<demande>"` crée
   l'état sous `.autopilot/`. Cet appel est idempotent : s'il existe déjà
   un état, il ne l'écrase pas (sauf `--force`, qui n'est utilisé qu'à la
   demande explicite de l'utilisateur — voir `references/RESUMING.md`,
   jamais au démarrage normal).
3. Amorcer le projet selon le mode retenu, comme décrit dans
   `references/MODES.md` : dépôt, `.gitignore` excluant `.autopilot/` et
   premier commit en création (sans présumer de la pile, et sans
   baseline verte — il n'y a pas encore de harnais de test à ce stade),
   worktree isolé via `using-git-worktrees` puis harnais existant vérifié
   vert en amélioration. La branche de travail ainsi obtenue est écrite
   dans `STATE.json` (clé `branche`) à cette étape. En mode amélioration,
   le chemin absolu du worktree créé y est écrit aussi, dans la clé `worktree` —
   sans cette clé, une reprise après redémarrage ne saurait pas où
   travailler et repartirait dans l'arbre de travail de l'utilisateur.

## 4. Le flux

Chaque étape délègue à une skill superpowers ; autopilot orchestre,
n'exécute pas la méthode elle-même.

| # | Étape | Skill superpowers | Mode |
|---|---|---|---|
| 0 | détection du mode | — | les deux |
| 1 | amorçage neutre, sans présumer de la pile : dépôt, `.gitignore`, premier commit | — | création |
| 1′ | espace isolé sur une branche, harnais existant vérifié vert avant tout changement | `using-git-worktrees` | amélioration |
| 2 | conception, auto-approuvée : pile choisie, spec écrite | `brainstorming` | les deux |
| 3 | plan en tâches de 2 à 5 minutes | `writing-plans` | les deux |
| 4 | exécution, un sous-agent par tâche (première tâche, en création : échafaudage propre à la pile choisie) | `subagent-driven-development` | les deux |
| 5 | rouge-vert-refactor dans chaque tâche | `test-driven-development` | les deux |
| 5b | cause racine avant tout correctif | `systematic-debugging` | si un test casse |
| 6 | revue contre le plan | `requesting-code-review` | les deux |
| 7 | traitement des retours | `receiving-code-review` | les deux |
| 8 | preuves avant toute affirmation | `verification-before-completion` | les deux |
| 9 | rapport final | — | les deux |

L'étape 2 est auto-approuvée : la spec est écrite et commitée avant toute
ligne de code, ce qui laisse la possibilité de la relire, mais autopilot
n'attend pas d'accord pour continuer. C'est aussi à cette étape que la
pile technique est choisie (voir `references/MODES.md`) et que le chemin
de la spec est écrit dans `STATE.json` (clé `spec`) ; le chemin du plan
(clé `plan`) est écrit à l'étape 3.

## 5. Autonomie

Tout choix rencontré en route se tranche seul et se consigne, **au moment
où la décision est prise** — pas seulement au checkpoint de fin de tâche
de la section 6 — voir `references/AUTONOMY.md` pour le détail. Le format
est toujours :

```
Ruling: <décision> — <pourquoi> — <coût si faux>
```

Seules quatre situations arrêtent le travail : identifiants ou accès
réseau manquants, toute écriture hors du dossier de travail (réversible
ou non — la lecture hors du dossier, elle, reste normale), action
sensible côté sécurité, ou demande si vague qu'aucune interprétation
n'est défendable. Tout le reste — y compris ce qui donne l'impression
qu'il faudrait demander — se résout par un Ruling.

Quand l'un de ces quatre cas survient, la skill écrit la phase `bloque`
dans `STATE.json`, consigne la raison au ledger, et s'arrête net — le
mécanisme complet (format de la ligne, ordre des opérations) est spécifié
dans `references/AUTONOMY.md`, pas ici.

## 6. Checkpoints et reprise

### La phase s'écrit à l'entrée, pas seulement à la fin d'une tâche

`phase` nomme toujours la phase **en cours**, jamais celle qui vient d'être
terminée. Elle s'écrit donc **à l'entrée de chaque phase**, avant d'en faire
le travail :

| Au moment d'entrer dans… | Écrire immédiatement |
|---|---|
| l'étape 2, `brainstorming` | `scripts/autopilot-state.sh set <dossier> phase conception` |
| l'étape 3, `writing-plans` | `scripts/autopilot-state.sh set <dossier> phase plan` |
| l'étape 4, la première tâche | `scripts/autopilot-state.sh set <dossier> phase execution` |
| les étapes 6 et 7, la revue | `scripts/autopilot-state.sh set <dossier> phase revue` |
| l'étape 8, la vérification | `scripts/autopilot-state.sh set <dossier> phase verification` |

Sans ces écritures, la phase **reste `init`** de la fin de l'amorçage jusqu'à
la fin de la première tâche du plan — c'est-à-dire pendant toute la conception
et toute la planification. Une coupure dans cet intervalle renverrait la
reprise à l'étape 0 : ré-amorçage du dossier et spec réécrite, exactement ce
que `references/RESUMING.md` interdit.

### À la fin de chaque tâche

Après chaque tâche terminée du plan, dans cet ordre :

1. un commit git sur la branche de travail (jamais de merge ni de push de
   sa propre initiative — voir `references/AUTONOMY.md`) ;
2. `scripts/autopilot-state.sh set <dossier> <clé> <valeur>` pour faire
   avancer la phase et la tâche courante dans `STATE.json` ;
3. `scripts/autopilot-state.sh ledger <dossier> "<ligne>"` pour consigner
   la fin de cette tâche.

Les Rulings pris pendant la tâche ne sont pas gardés pour ce moment-là :
ils sont déjà au ledger depuis l'instant où ils ont été décidés (section
5). Le champ `cycles` de `STATE.json` n'apparaît jamais dans cette liste :
il appartient au superviseur (section 8), la skill ne l'écrit jamais.

Quand la skill est invoquée avec « reprise » (aiguillée depuis la section
2), elle ne repart jamais d'un souvenir de conversation : la conversation
qui a produit l'état peut avoir disparu (coupure, redémarrage, nouvelle
session). Elle lit `.autopilot/RESUME.md` puis `.autopilot/STATE.json`
pour connaître la phase et la tâche exactes, reprend le flux de la
section 4 à l'étape associée à cette phase, en terminant d'abord la tâche
nommée dans `STATE.json` avant d'avancer à la suivante. Le mapping complet
entre phases et étapes, ainsi que la procédure détaillée, sont dans
`references/RESUMING.md`.

### Entre deux tâches : lire l'alerte de quota

Quand le superviseur tourne avec sa surveillance continue (section 8), un
veilleur interroge le quota **pendant** que la skill travaille et pose
`.autopilot/QUOTA_ALERTE` dès que l'utilisation approche l'épuisement.
**Entre chaque tâche du plan, avant d'en démarrer une nouvelle**, la skill
teste si ce fichier existe. Il n'y a rien à faire tant qu'il n'existe pas.
S'il existe :

1. elle ne démarre **pas** la tâche suivante ;
2. elle s'assure que la tâche qui vient de se terminer est commitée et que
   `phase`/`tache` reflètent bien l'état réel (section « À la fin de
   chaque tâche » ci-dessus, si ce n'est pas déjà fait) ;
3. elle consigne au ledger un arrêt volontaire avant épuisement, en
   **nommant l'utilisation constatée** (lisible dans `.autopilot/QUOTA.json`,
   écrit par le veilleur) ;
4. elle rend la main proprement, sans rien exécuter de plus.

La phase **n'est pas** `bloque` : ce n'est pas un des quatre arrêts de la
section 5, personne n'a besoin de trancher quoi que ce soit, c'est une
pause technique dont le superviseur se charge (il attend la réinitialisation
du quota puis efface l'alerte avant de relancer — voir section 8). La phase
reste celle en cours, exactement comme pour toute autre interruption : la
reprise suivante enchaîne au même endroit, via `references/RESUMING.md`.

Cette vérification **ne coupe jamais une tâche en cours** : le point de
décision est strictement entre deux tâches, jamais au milieu. Interrompre
une tâche à moitié faite laisserait du travail non commité — pire que la
coupure par quota que cette vérification cherche justement à éviter. Une
tâche anormalement longue peut donc encore se faire couper par le quota
réel, exactement comme sans cette fonctionnalité.

## 7. Livraison

Une fois toutes les tâches du plan terminées et vérifiées à l'étape 8, la
phase passe à `termine` dans `STATE.json` et le rapport final suit le
gabarit décrit dans `references/DELIVERY.md` : aucune affirmation de
succès sans la sortie réelle de la commande qui la prouve, et la liste de
tout acte sortant (merge, push, publication, déploiement) effectué
au-delà de la branche locale, avec ce qui l'autorisait — ou son absence
explicite si rien de tel n'a été demandé.

## 8. Superviseur et quota

Pour un run long, c'est un **humain** qui lance, une fois que l'état
existe (après la section 3 ou 2), en arrière-plan :

```
bash "$HOME/.claude/skills/autopilot/scripts/autopilot-supervisor.sh" <dossier-cible> [--max-cycles N] [--budget-attente S] [--permission-mode MODE] [--max-cycles-sans-progres N] [--seuil-alerte N] [--intervalle-veille S] [--sans-veilleur]
```

### Deux régimes : réactif seul, ou surveillance continue

Par défaut, le superviseur lance en plus `scripts/autopilot-watch.sh` en
arrière-plan **avant** chaque `claude -p` et l'arrête juste **après** :
c'est la **surveillance continue**, celle qui permet à la skill de
s'arrêter d'elle-même entre deux tâches (section 6, « Entre deux tâches :
lire l'alerte de quota ») plutôt que de se faire couper au milieu. Le
veilleur écrit `.autopilot/QUOTA.json` à chaque tour et pose
`.autopilot/QUOTA_ALERTE` dès que l'utilisation atteint `--seuil-alerte`
(90 par défaut — volontairement sous le seuil d'épuisement de 95 utilisé
par la sonde, pour laisser une marge de manœuvre), en l'effaçant si
l'utilisation redescend. `--intervalle-veille` (300 s par défaut) règle la
fréquence de ses tours. Une sonde en panne ne crée jamais d'alerte.

`--sans-veilleur` restaure le régime **purement réactif** décrit dans le
reste de cette section : aucun veilleur n'est lancé, et une alerte déjà
présente sur disque est ignorée. C'est le seul comportement qui existait
avant cette fonctionnalité.

Que le veilleur soit actif ou non, **dès que `.autopilot/QUOTA_ALERTE`
existe**, le superviseur attend la réinitialisation du quota avant de
relancer `claude -p` — **même si la sonde ne dit pas encore « épuisé »** —
puis efface l'alerte. Sans ce garde-fou, une skill arrêtée proprement à
90 % serait relancée aussitôt, annulant tout le bénéfice de s'être
arrêtée tôt.

Nettoyage : le superviseur pose un `trap` sur `EXIT`, `INT` et `TERM` qui
tue le veilleur par son PID (vérifié vivant avant d'être tué, toléré déjà
mort, fichier PID nettoyé dans tous les cas) — un veilleur orphelin qui
sonderait l'API indéfiniment serait pire que l'absence de la
fonctionnalité.

Le superviseur lance `claude -p` avec un **mode de permission explicite** :
sous `--print`, tout ce qui demanderait une permission est refusé
automatiquement, et l'agent ne pourrait donc rien écrire. Le défaut est
`--permission-mode acceptEdits` : un agent non surveillé qui accepte les
éditions de fichiers est ce qu'on veut, un agent qui contourne toute
permission ne l'est pas. Les valeurs acceptées sont `acceptEdits`, `auto`,
`bypassPermissions`, `manual`, `dontAsk` et `plan`.

Il surveille aussi le **progrès réel** : `phase` et `tache` sont relevées
avant et après chaque cycle et, si rien n'a bougé pendant
`--max-cycles-sans-progres` cycles consécutifs terminés en code 0 (3 par
défaut), il le consigne au ledger et s'arrête en code `4` plutôt que
d'enchaîner des sessions stériles.

La skill elle-même ne se lance jamais ce superviseur. Sans état
préalable (`.autopilot/STATE.json` absent), le superviseur refuse et
sort en code 2 — il faut donc que la section 3 ait déjà tourné au moins
une fois.

Le superviseur relance autopilot en boucle et s'arrête proprement une
fois `autopilot-state.sh done` vrai. Après chaque sortie non nulle de la
skill, c'est le superviseur qui interroge lui-même
`scripts/autopilot-quota.sh verdict` pour savoir s'il s'agit d'un quota
épuisé ; la skill ne choisit pas de code de sortie convenu pour le lui
signaler, ça n'existe pas comme mécanisme fiable. Ce qui revient à la
skill quand elle constate elle-même, en plein travail, un épuisement de
quota : consigner ce constat au ledger et laisser la phase courante
intacte (ni `termine`, ni `bloque` — ce n'est pas un des quatre arrêts,
voir `references/AUTONOMY.md`), pour que la reprise suivante la retrouve
exactement où elle s'est arrêtée.

Le superviseur rend l'un de ces cinq codes de sortie :

| Code | Signifie |
|---|---|
| `0` | travail terminé (`autopilot-state.sh done` devient vrai) |
| `1` | plafond de cycles atteint, ou budget d'attente cumulée épuisé |
| `2` | dossier ou état absent (`.autopilot/STATE.json` introuvable) |
| `3` | phase `bloque` constatée : décision humaine requise, aucune reprise automatique n'aura lieu — voir `references/AUTONOMY.md` |
| `4` | aucun progrès (`phase` et `tache` inchangées) pendant plusieurs cycles consécutifs terminés en code 0 |
