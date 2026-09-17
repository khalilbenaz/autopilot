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
jamais — la branche reste locale, à livrer à un humain qui décidera de la
suite.

## 2. Démarrage

Sur le dossier cible :

1. `scripts/autopilot-detect.sh <dossier>` rend `creation` ou
   `amelioration`. Lire `references/MODES.md` avant d'agir sur ce
   résultat : la règle de détection y est fixée et ne se discute pas.
2. `scripts/autopilot-state.sh init <dossier> <mode> "<demande>"` crée
   l'état sous `.autopilot/`. Cet appel est idempotent : s'il existe déjà
   un état, il ne l'écrase pas (sauf `--force`, jamais utilisé au
   démarrage normal).
3. Amorcer le projet selon le mode retenu, comme décrit dans
   `references/MODES.md` (dépôt et échafaudage en création, worktree
   isolé via `using-git-worktrees` en amélioration).

## 3. Le flux

Chaque étape délègue à une skill superpowers ; autopilot orchestre,
n'exécute pas la méthode elle-même.

| # | Étape | Skill superpowers | Mode |
|---|---|---|---|
| 0 | détection du mode et de la pile technique | — | les deux |
| 1 | amorçage : dépôt, échafaudage, baseline verte | — | création |
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

L'étape 2 est auto-approuvée : la spec est écrite et commitée avant toute
ligne de code, ce qui laisse la possibilité de la relire, mais autopilot
n'attend pas d'accord pour continuer.

## 4. Autonomie

Tout choix rencontré en route se tranche seul et se consigne — voir
`references/AUTONOMY.md` pour le détail. Le format est toujours :

```
Ruling: <décision> — <pourquoi> — <coût si faux>
```

Seules quatre situations arrêtent le travail : identifiants ou accès
réseau manquants, opération irréversible hors du dossier de travail,
action sensible côté sécurité, ou demande si vague qu'aucune
interprétation n'est défendable. Tout le reste — y compris ce qui donne
l'impression qu'il faudrait demander — se résout par un Ruling.

## 5. Checkpoints

Après chaque tâche terminée du plan :

1. un commit git sur la branche de travail (jamais de merge ni de push) ;
2. `scripts/autopilot-state.sh set <dossier> <clé> <valeur>` pour faire
   avancer la phase et la tâche courante dans `STATE.json` ;
3. `scripts/autopilot-state.sh ledger <dossier> "<ligne>"` pour consigner
   l'événement ou le Ruling qui vient d'être pris.

`references/RESUMING.md` décrit le contenu exact de `.autopilot/` et la
procédure de reprise qui s'appuie sur ces checkpoints.

## 6. Reprise

Quand autopilot est invoquée avec « reprise », elle ne repart jamais d'un
souvenir de conversation : la conversation qui a produit l'état peut avoir
disparu (coupure, redémarrage, nouvelle session). Elle lit uniquement
`.autopilot/RESUME.md` et `.autopilot/STATE.json` dans le dossier cible
pour savoir où elle en est et quelle est la prochaine action, complète ce
qui reste du plan, puis continue le flux normalement à partir de la phase
constatée. Voir `references/RESUMING.md`.

## 7. Quota

Pour un run long, lancer en arrière-plan
`scripts/autopilot-supervisor.sh <dossier> [--max-cycles N] [--budget-attente S]` :
il relance autopilot en boucle, attend la réinitialisation du quota quand
`scripts/autopilot-quota.sh verdict` la signale épuisée, et s'arrête
proprement une fois `autopilot-state.sh done` vrai. Quand autopilot,
invoquée par le superviseur, constate elle-même un épuisement de quota en
plein travail, elle doit sortir avec le code 7 pour que le superviseur
reconnaisse la situation et dorme jusqu'au reset plutôt que de la traiter
comme une erreur ordinaire.

## 8. Fin

Une fois toutes les tâches du plan terminées et vérifiées, la phase passe
à `termine` dans `STATE.json` et le rapport final suit exactement le
format exigé par `references/DELIVERY.md` : aucune affirmation de succès
sans la sortie réelle de la commande qui la prouve, et rappel explicite
qu'aucun merge, push, publication ni déploiement n'a eu lieu.
