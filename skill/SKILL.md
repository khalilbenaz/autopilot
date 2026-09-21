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
   en **Bounded**. Ceci s'applique à **chaque** cycle du run, pas
   seulement au premier : un nouveau cycle ouvert en cours de run
   (section 9) traverse `brainstorming` à son tour, et s'y classe
   architectural exactement comme le cycle initial. Le chemin Bounded s'arrête à un « oui » en chat et ne
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

Elle couvre en revanche **tout le run**, cycles successifs compris. Un
nouveau cycle (section 9) n'est pas une nouvelle invocation de la skill
par l'utilisateur : c'est autopilot elle-même qui rouvre la conception en
cours de run, parce qu'une demande dépasse ce que couvrait le cycle
précédent. L'invocation initiale vaut donc accord aussi pour ce nouveau
passage par `brainstorming` et sa classification imposée en
architectural, sans quoi le run s'arrêterait à la première demande venant
après l'épuisement d'un plan — ce qui romprait justement l'autonomie que
cette pré-approbation existe pour garantir.

## 2. Démarrage ou reprise : l'aiguillage

Avant tout autre chose, teste si `<dossier-cible>/.autopilot/STATE.json`
existe déjà :

- il existe → c'est une **reprise**, pas un démarrage : aller directement
  à la section 6, sans exécuter ce qui suit ;
- il n'existe pas → c'est un **démarrage**, la suite de cette section
  s'applique.

Un nouveau cycle ouvert en cours de run (section 9) n'est ni l'un ni
l'autre : `STATE.json` existe déjà et continue d'exister, seules sa phase
et ses clés `spec`/`plan` changent, sans repasser par cet aiguillage ni
par la section 3. Une coupure survenant **pendant** un cycle ainsi rouvert
se traite comme toute autre reprise, sans traitement particulier — voir
`references/RESUMING.md`.

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

Une demande qui arrive en cours de run et que le cycle courant ne couvre
pas ne s'ajoute jamais à ce tableau comme une tâche de plus, à l'étape 4
ou ailleurs : elle rouvre ce tableau depuis l'étape 2, dans un nouveau
cycle — voir section 9, « Nouvelle demande en cours de run : un nouveau
cycle ».

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

**Chacune de ces écritures met aussi à jour le battement de coeur** :
immédiatement après chaque `set <dossier> phase ...` de la table ci-dessus,

```
date +%s > "<dossier-cible>/.autopilot/HEARTBEAT"
```

C'est ce battement, lu par le superviseur (section 8, « Le battement de
coeur »), qui l'empêche de lancer une session concurrente pendant que
celle-ci travaille encore.

### À la fin de chaque tâche

Après chaque tâche terminée du plan, dans cet ordre :

1. un commit git sur la branche de travail (jamais de merge ni de push de
   sa propre initiative — voir `references/AUTONOMY.md`) ;
2. `scripts/autopilot-state.sh set <dossier> <clé> <valeur>` pour faire
   avancer la phase et la tâche courante dans `STATE.json` ;
3. `scripts/autopilot-state.sh ledger <dossier> "<ligne>"` pour consigner
   la fin de cette tâche ;
4. `date +%s > "<dossier-cible>/.autopilot/HEARTBEAT"` pour rafraîchir le
   battement de coeur — entre chaque tâche, pas seulement aux transitions
   de phase, sinon une tâche longue laisserait le battement périmer alors
   que la session travaille toujours (voir section 8).

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

Une skill qui promet de mener un run seul de bout en bout ne peut pas
dépendre d'un humain pour installer son propre filet de survie : c'est donc
**la skill elle-même** qui lance le superviseur, dès que l'état existe
(après la section 3 ou 2) et que la phase d'exécution commence (l'étape 4,
section 4).

### Anti-récursion : si un superviseur la surveille déjà, elle n'en lance pas

Avant tout lancement — et en fait dès son démarrage, puisque cette
condition ne change jamais en cours de run —, la skill teste la variable
d'environnement `AUTOPILOT_SUPERVISE`. **Si elle vaut `1`, la skill ne
lance aucun superviseur**, ni maintenant ni plus tard dans ce run : elle
sait qu'un superviseur la surveille déjà, puisque c'est lui qui a exporté
cette variable en lançant `claude -p` (voir plus bas). Sans ce garde-fou,
une skill reprise sous surveillance relancerait un nouveau superviseur à
chaque cycle, empilant les superviseurs indéfiniment — le piège de la
récursion.

### La commande de lancement

Détaché de la session courante pour qu'il lui survive — c'est tout l'intérêt
d'un filet de survie —, en arrière-plan et avec ses sorties redirigées vers
un journal dédié. Sur macOS :

```
nohup bash "$HOME/.claude/skills/autopilot/scripts/autopilot-supervisor.sh" "<dossier-cible>" [--max-cycles N] [--budget-attente S] [--permission-mode MODE] [--max-cycles-sans-progres N] [--seuil-alerte N] [--intervalle-veille S] [--seuil-battement S] [--sans-veilleur] > "<dossier-cible>/.autopilot/supervisor.log" 2>&1 &
```

Immédiatement après, `$!` donne le PID du superviseur lancé ; la skill le
consigne au ledger :

```
scripts/autopilot-state.sh ledger <dossier-cible> "Superviseur lancé en arrière-plan, PID <pid>, journal dans .autopilot/supervisor.log."
```

Le superviseur refuse de démarrer sans état préalable (`.autopilot/STATE.json`
absent, code 2) : ce lancement n'a donc de sens qu'à partir du moment où la
section 3 (ou l'amorçage de la section 2) a déjà tourné, ce qui est toujours
le cas à l'entrée de l'étape 4.

**Recours manuel, conservé** : ce lancement automatique n'empêche pas un
humain de lancer ou relancer le superviseur à la main avec la même
commande — utile pour un run démarré avant cette fonctionnalité, ou pour
reprendre la main après un arrêt volontaire. Voir `README.md`.

### Verrou anti-collision : un seul superviseur actif par dossier

Le superviseur pose lui-même `<dossier-cible>/.autopilot/supervisor.pid`
(son propre PID) dès son démarrage, et s'arrête aussitôt, sans rien faire,
s'il trouve déjà dans ce fichier le PID d'un `autopilot-supervisor.sh`
**vivant** visant **ce même dossier** — les deux conditions à la fois,
vérifiées par sa ligne de commande complète, jamais par la seule présence
du fichier : un PID mort ou réutilisé entre-temps par un autre programme ne
bloque rien, ce verrou périmé est remplacé par le sien. La skill n'a donc
rien à vérifier elle-même avant de lancer la commande ci-dessus : un second
lancement, volontaire ou accidentel, se referme aussitôt sans effet si un
superviseur légitime tourne déjà. Le verrou est supprimé automatiquement à
la sortie du superviseur, y compris sur interruption (`INT`/`TERM`).

### Le battement de coeur : empêcher une collision avec la session en cours

Le verrou ci-dessus protège contre **deux superviseurs**. Il ne protège pas
contre le cas central de ce mécanisme : la skill vient tout juste de lancer
le superviseur (paragraphe précédent) et **continue de travailler** — le
superviseur, lui, ne le sait pas encore, et pourrait lancer sa propre
session `claude -p` en parallèle de celle qui l'a fait naître. Deux agents
sur le même dossier en même temps, c'est le risque que ce mécanisme existe
justement pour éviter : éditions concurrentes, commits en double, état
corrompu.

La parade est un battement de coeur. **À chaque écriture de `phase`** (table
de la section 6) **et entre chaque tâche** (« À la fin de chaque tâche »,
section 6), la skill écrit l'horodatage courant :

```
date +%s > "<dossier-cible>/.autopilot/HEARTBEAT"
```

Avant de lancer `claude -p`, le superviseur lit ce fichier :

- battement de moins de `--seuil-battement` secondes (600 par défaut) →
  une session travaille encore ; le superviseur **ne lance rien**, il
  attend et revérifie à intervalle court — sans consommer de cycle, sans
  entamer le budget d'attente : ce n'est pas une attente de quota, c'est
  une veille, journalisée une seule fois par période de veille ;
- battement absent ou plus vieux que le seuil → plus personne ne travaille,
  le superviseur lance `claude -p` normalement.

Sans ce battement à jour, un superviseur qui vient d'être lancé par une
session encore active la percuterait presque à coup sûr, puisque le
lancement a lieu au tout début de l'étape 4 — pas à sa fin.

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

## 9. Nouvelle demande en cours de run : un nouveau cycle

Une fois le plan du cycle courant terminé — ou même avant, si une
instruction arrive qui décrit une portée que ni la spec ni le plan du
cycle courant ne couvrent — l'utilisateur peut donner une demande
nouvelle en cours de run. Ce n'est jamais une rallonge, jamais une
« vague », jamais une tâche improvisée ajoutée à la suite de la dernière :
**toute demande non couverte par le plan en cours repasse par la conception
et la planification**, exactement comme la demande initiale.

**Note de vocabulaire**, pour éviter toute confusion avec la section 8 :
le « cycle » de cette section (conception → plan → exécution → revue →
vérification, potentiellement répété) n'a aucun rapport avec la clé
`cycles` de `STATE.json` ni avec les `--max-cycles` / `--max-cycles-sans-progres`
du superviseur — ceux-là comptent les relances de session `claude -p`
après une coupure de quota ou un redémarrage, un mécanisme entièrement
différent. Un run peut traverser vingt relances de superviseur pour un
seul cycle de conception, ou l'inverse.

### Reconnaître qu'une demande n'est pas couverte

Une demande n'est pas couverte par le cycle courant dans l'un de ces deux
cas :

- le plan du cycle courant est épuisé (`autopilot-state.sh done` vrai, ou
  toutes ses tâches à `complete`) et une nouvelle instruction arrive ;
- indépendamment de l'état du plan, l'instruction décrit une portée que la
  spec du cycle courant (fichier pointé par la clé `spec` de
  `STATE.json`) ne traite pas.

### La frontière avec une correction de revue

N'est **pas** une demande nouvelle : toute réponse à un retour produit par
les étapes 6/7 (`requesting-code-review` / `receiving-code-review`) du
cycle courant, sur un point que sa spec ou son plan couvraient déjà — un
bug relevé sur une tâche déjà faite, un test manquant, un ajustement de
nommage ou de style, une clarification qui n'ajoute aucune portée absente
de la spec écrite. Ceci se traite **dans le cycle courant**, sans
déclencher ce qui suit : pas de nouvelle entrée `Nouveau cycle` au ledger,
pas de nouvelle spec, pas de nouveau plan — c'est un correctif ordinaire
de l'étape 7.

Est en revanche une demande nouvelle toute instruction qui décrit une
portée absente de la spec, même si elle arrive dans le même message
qu'une correction de revue légitime, même si elle semble petite, même si
elle ressemble à une suite naturelle de ce qui vient d'être livré. Dans ce
cas mixte, le correctif se traite dans le cycle courant et la portée
nouvelle ouvre, séparément, le mécanisme ci-dessous.

### Ce que fait la skill

1. Elle consigne au ledger, **avant tout autre changement d'état**, une
   ligne dédiée, distincte du format `Ruling:` et du format `Arrêt:` :

   ```
   Nouveau cycle <N>: <demande reformulée en une phrase> — <raison : plan épuisé | hors du périmètre de la spec du cycle courant>
   ```

   `N` se calcule une fois pour toutes à cet instant : il vaut `2` la
   première fois que ce mécanisme se déclenche dans un run, puis
   s'incrémente de 1 à chaque déclenchement suivant — concrètement,
   `N` = 2 + le nombre de lignes `Nouveau cycle` déjà présentes dans
   `.autopilot/LEDGER.md` avant celle-ci. Le cycle initial du run, celui
   des sections 2 et 3, est le cycle 1 : il n'est jamais renuméroté ni
   réécrit, et cette section ne lui écrit jamais de ligne `Nouveau cycle`.
2. Elle repasse la phase à `conception` :
   `scripts/autopilot-state.sh set <dossier> phase conception`, puis
   rafraîchit le battement de coeur (section 6, ce même geste que pour
   toute entrée de phase).
3. Elle reprend le flux de la section 4 à l'étape 2, `brainstorming` —
   toujours classée **architectural** (section 1) —, puis l'étape 3,
   `writing-plans`, exactement comme pour le cycle initial.
4. Elle écrit une **nouvelle** spec et un **nouveau** plan, dans des
   fichiers **distincts** de ceux du ou des cycles précédents. Elle ne
   réécrit **jamais** un fichier de spec ou de plan d'un cycle antérieur :
   ces fichiers documentent un travail déjà livré. Nommage, sans
   exception : la convention de nommage déjà en usage chez
   `brainstorming` (pour la spec, sous `docs/superpowers/specs/`) et chez
   `writing-plans` (pour le plan, sous `docs/superpowers/plans/`), à
   laquelle s'ajoute le suffixe littéral `-cycle<N>` juste avant `.md` —
   avec le même `N` que celui écrit au ledger à l'étape 1 ci-dessus, par
   exemple `2026-09-21-calque-cycle2.md`. Le cycle 1 n'a pas de suffixe :
   c'est ce qui distingue déjà, sans ambiguïté, les fichiers d'un run à
   cycle unique de ceux d'un run qui en a ouvert d'autres. La numérotation
   des tâches du nouveau plan (`Task 1`, `Task 2`, …) repart de 1, comme
   tout plan écrit par `writing-plans` — elle ne poursuit jamais la
   numérotation du plan précédent.
5. Elle met à jour les clés `spec` et `plan` de `STATE.json` vers ces deux
   nouveaux fichiers (`scripts/autopilot-state.sh set <dossier> spec ...`,
   puis `... plan ...`) — les mêmes clés que celles déjà écrites aux
   étapes 2 et 3 pour le cycle initial, simplement réécrites :
   `STATE.json` ne porte jamais qu'un seul chemin de spec et un seul
   chemin de plan à la fois, ceux du cycle **courant**. Les chemins des
   cycles précédents restent lisibles dans le ledger (les lignes
   `Nouveau cycle`) et dans l'historique git ; ils ne sont jamais
   dupliqués dans `STATE.json`.
6. Elle reprend l'exécution normalement (étapes 4 à 9 de la section 4),
   avec son propre ledger SDD, exactement comme le cycle initial.

### Ce que ce mécanisme ne change pas

- **La pré-approbation couvre ce nouveau cycle** exactement comme le
  premier (section 1) : l'invocation initiale d'autopilot par
  l'utilisateur vaut accord pour tout le run, cycles successifs compris.
  La classification imposée en architectural à l'étape 2 s'applique donc
  à chaque cycle, jamais seulement au premier.
- **Le travail déjà livré n'est pas repris.** Le nouveau cycle porte sur
  la demande nouvelle, pas sur une refonte de l'existant : la spec du
  cycle précédent reste la référence de ce qui a déjà été fait, et rien
  dans ce mécanisme n'autorise à la corriger, la compléter ou la
  remplacer au nom de la cohérence — un besoin réel de revenir sur du
  travail déjà livré est lui-même une nouvelle demande, avec son propre
  cycle.
- **Une demande minuscule passe quand même par ce mécanisme.** Un plan
  d'une seule tâche est un plan. Le coût de ce passage se compte en
  quelques minutes ; le bénéfice est qu'aucun travail — même le plus
  petit — n'échappe au découpage en tâches, aux tests et à la revue qui
  font tout l'intérêt du Basic Workflow. C'est précisément le raccourci
  inverse — traiter une petite demande comme une rallonge dispensée de
  conception — qui a produit la dérive observée en production : une
  tâche improvisée, nommée en dehors de tout plan, sans spec, sans
  découpage, sans revue.
