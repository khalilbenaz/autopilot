# autopilot

Skill Claude Code qui prend une demande en langage naturel et livre, sans
poser de question et sans surveillance humaine continue, une branche locale
avec des tests verts — en enchaînant les skills superpowers du Basic
Workflow (détection du mode, conception, plan, exécution en TDD, revue,
vérification, rapport final).

Elle ne s'arrête que sur une des quatre situations décrites dans
`skill/references/AUTONOMY.md` (identifiants ou accès réseau manquants,
toute écriture hors du dossier de travail, action sensible côté
sécurité, ou demande trop vague pour être tranchée) ; pour tout le reste,
elle décide seule et consigne son choix.

**Elle ne merge jamais, ne pousse jamais, ne publie jamais et ne déploie
jamais de sa propre initiative.** Quand la demande le réclame
explicitement, c'est une partie du livrable comme une autre, et elle le
fait — voir `skill/references/AUTONOMY.md` (section « Actes sortants »)
pour les garde-fous : couverture stricte de la demande, tests verts
d'abord, dépôt créé privé par défaut, opérations git destructives
toujours nommées à part. Sinon, la branche produite reste locale ; c'est
un humain qui décide de la suite.

## Installation

```bash
./install.sh
```

Ce script pose un lien symbolique de `~/.claude/skills/autopilot` vers le
dossier `skill/` de ce dépôt — aucun fichier n'est copié ni dupliqué. Il est
idempotent (le relancer ne casse rien) et **ne remplace jamais un dossier
réel** : si `~/.claude/skills/autopilot` existe déjà et n'est pas un lien,
l'installation refuse et sort en erreur plutôt que d'écraser quoi que ce
soit. Il faut alors déplacer ou supprimer ce dossier à la main avant de
relancer.

Vérifier le résultat :

```bash
ls -l ~/.claude/skills/autopilot
```

## Invocation

Une fois installée, la skill se déclenche dans Claude Code sur une demande
du type « construis-moi X », « améliore X », « livre X de A à Z ». Elle
lit elle-même `skill/SKILL.md` et ses références pour dérouler le flux ;
aucune commande manuelle n'est nécessaire pour le démarrage ou la reprise
d'un run — c'est la skill qui invoque au besoin
`autopilot-detect.sh`, `autopilot-state.sh`, etc.

## Le superviseur : lancé par un humain, pas par la skill

Pour un run long (qui peut traverser une coupure de quota, un
redémarrage de machine, ou plusieurs jours), un **humain** lance à part,
une fois que l'état existe déjà (c'est-à-dire une fois que la skill a
tourné au moins jusqu'à créer `.autopilot/STATE.json`) :

```bash
bash ~/.claude/skills/autopilot/scripts/autopilot-supervisor.sh <dossier-cible> [--max-cycles N] [--budget-attente S] [--permission-mode MODE] [--max-cycles-sans-progres N] [--seuil-alerte N] [--intervalle-veille S] [--sans-veilleur]
```

La skill ne lance **jamais** ce superviseur elle-même. S'il ne trouve pas
`<dossier-cible>/.autopilot/STATE.json`, il refuse et sort en code `2` —
il faut donc que la skill ait déjà amorcé le projet avant.

Le superviseur relance autopilot en boucle, en attendant si besoin la
réinitialisation du quota Claude, jusqu'à ce que le travail soit terminé.

### Deux régimes : réactif seul, ou surveillance continue

Par défaut, le superviseur ne se contente pas d'attendre qu'une session
`claude -p` rende la main pour interroger le quota : il lance en plus
`autopilot-watch.sh` en arrière-plan **avant** chaque `claude -p` et
l'arrête juste **après**. Ce veilleur tourne **pendant** que la session
travaille et pose `<dossier-cible>/.autopilot/QUOTA_ALERTE` dès que
l'utilisation atteint `--seuil-alerte` (**90** par défaut — volontairement
sous le seuil d'épuisement de **95** utilisé par la sonde, pour laisser une
marge de manœuvre), en l'effaçant si l'utilisation redescend en dessous.
`--intervalle-veille` (**300** secondes par défaut) règle la fréquence de
ses tours. Une sonde en panne pendant un tour du veilleur ne crée **jamais**
d'alerte, et n'efface pas non plus une alerte déjà posée.

C'est ce fichier `QUOTA_ALERTE` que la skill lit d'elle-même **entre deux
tâches** de son plan (jamais au milieu d'une tâche — voir
`skill/SKILL.md`, section « Entre deux tâches : lire l'alerte de quota ») :
s'il existe, elle ne démarre pas la tâche suivante, s'assure que la
dernière est commitée, consigne un arrêt volontaire au ledger et rend la
main proprement, phase inchangée. **Dès que `QUOTA_ALERTE` existe**, le
superviseur attend ensuite la réinitialisation du quota avant de relancer
— même si la sonde ne dit pas encore « épuisé » — puis efface l'alerte.
Sans ce garde-fou, une skill arrêtée à 90 % serait relancée aussitôt,
annulant tout le bénéfice de s'être arrêtée tôt.

**Limite assumée** : l'arrêt ne peut avoir lieu qu'entre deux tâches, jamais
au milieu. Interrompre une tâche en cours laisserait du travail non
commité — pire que la coupure par quota que cette fonctionnalité cherche à
éviter. Une tâche anormalement longue peut donc encore se faire couper par
le quota réel, exactement comme avant.

`--sans-veilleur` restaure le **régime réactif seul**, celui qui existait
avant cette fonctionnalité : aucun veilleur n'est lancé, et une alerte déjà
présente sur disque est ignorée.

Nettoyage du veilleur — le risque principal de cette fonctionnalité : un
veilleur orphelin qui sonderait l'API indéfiniment serait pire que
l'absence de la fonctionnalité. Le superviseur pose un `trap` sur `EXIT`,
`INT` et `TERM` qui le tue par son PID (vérifié vivant avant d'être tué,
toléré déjà mort, fichier PID nettoyé dans tous les cas).

Il lance `claude -p` avec `--permission-mode acceptEdits` par défaut : sous
`--print`, sans mode explicite, tout ce qui demanderait une permission est
refusé et l'agent ne peut rien écrire. `--permission-mode` accepte
`acceptEdits`, `auto`, `bypassPermissions`, `manual`, `dontAsk` et `plan` ;
`bypassPermissions` n'est pas le défaut, et ne le sera pas sans demande
explicite. `--max-cycles-sans-progres N` (3 par défaut) borne le nombre de
cycles consécutifs terminés en code 0 sans que `phase` ni `tache` ne bougent :
au-delà, le superviseur consigne l'abandon et sort en code `4`.

Ses cinq codes de sortie :

| Code | Signifie |
|---|---|
| `0` | travail terminé (`autopilot-state.sh done` devient vrai) |
| `1` | plafond de cycles atteint, ou budget d'attente cumulée épuisé |
| `2` | dossier ou état absent (`.autopilot/STATE.json` introuvable) |
| `3` | phase `bloque` constatée : décision humaine requise, aucune reprise automatique n'aura lieu |
| `4` | aucun progrès pendant plusieurs cycles consécutifs : sessions stériles, arrêt |

### Un sommeil qui ne survit pas à un redémarrage, ce n'est pas un problème

Quand le superviseur attend une réinitialisation de quota qui peut prendre
plusieurs jours, ce sommeil est un simple `sleep` : il ne survit ni à un
redémarrage de la machine ni à un `SIGTERM`. C'est normal et sans
conséquence — l'état complet du run vit sur disque, sous `.autopilot/`,
jamais en mémoire du processus. Si le superviseur est interrompu pendant
qu'il attend, rien n'est perdu : il suffit de le relancer avec la même
commande, il relit l'état et reprend l'attente ou le travail exactement
où il en était.

## Où vit l'état

Tout l'état d'un run vit dans `<dossier-cible>/.autopilot/` :

- `STATE.json` — mode, phase, tâche courante, branche, worktree, chemins de
  la spec et du plan, compteur de cycles ;
- `LEDGER.md` — journal chronologique des décisions (Rulings) et des
  événements (fin de tâche, quota épuisé, blocage) ;
- `RESUME.md` — document de reprise régénéré à chaque changement d'état,
  lisible par un humain ou par une nouvelle session sans mémoire de la
  conversation qui a produit l'état.

Quand la surveillance continue tourne (régime par défaut, sans
`--sans-veilleur`), trois fichiers de plus apparaissent, écrits par
`autopilot-watch.sh` :

- `QUOTA.json` — dernier tour du veilleur : utilisation constatée, fenêtre
  concernée, `resets_at`, si la sonde a répondu, horodatage ;
- `QUOTA_ALERTE` — présent seulement quand l'utilisation a atteint le
  seuil d'alerte ; c'est le signal que la skill lit entre deux tâches ;
- `watch.pid` — PID du veilleur en cours, nettoyé à l'arrêt.

Ce dossier est exclu du contrôle de version du projet cible (voir
`.gitignore` posé à l'amorçage).

## Lancer les tests

```bash
/bin/bash ./tests/run.sh
```

Le harnais source chaque `tests/test_*.sh` et exécute toutes les
fonctions `test_*` qu'il y trouve ; il affiche le nombre d'assertions
passées et échouées, et sort en erreur s'il y a au moins un échec.
