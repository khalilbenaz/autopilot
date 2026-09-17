# MODES — création ou amélioration

## La règle de détection

`scripts/autopilot-detect.sh <dossier>` tranche, sans jamais poser de
question :

- dossier absent, illisible, vide, ou dépôt git sans aucun fichier
  visible → **création** ;
- dossier contenant au moins un fichier ou un lien symbolique visible
  (caché à `.` non compté), avec ou sans dépôt git → **amélioration**.

Un dossier illisible (droits refusés) est traité comme une **amélioration**
par prudence : ne pouvant pas voir ce qu'il contient, autopilot ne propose
jamais de repartir de zéro par-dessus un contenu qu'elle n'a pas pu
inspecter.

### Le cas du simple README

Un dossier qui ne contient qu'un `README.md` compte comme un projet
**existant**, donc **amélioration** — pas création. Cette décision a été
tranchée en revue et n'est pas négociable au moment de l'exécution : un
`README.md`, même seul, porte déjà une intention écrite (nom du projet,
description, parfois des choix déjà faits). Se tromper vers *création*
ferait échafauder un projet neuf par-dessus une intention déjà posée,
ce qui est plus coûteux à défaire qu'un déclenchement prudent vers
*amélioration* qui, au pire, lit un peu de contexte supplémentaire avant
d'agir. Entre les deux erreurs possibles, une seule est acceptable, et
`autopilot-detect.sh` est écrit pour ne jamais commettre l'autre.

Aucune des deux branches ne pose de question à l'utilisateur : le mode
retenu est annoncé en une ligne, consigné dans `STATE.json` via
`autopilot-state.sh init`, et le travail continue.

## Amorçage en mode création

Quand le mode est `creation`, avant d'entrer dans le flux commun (étape 2,
`brainstorming`), autopilot amorce le projet elle-même :

1. initialiser un dépôt git dans le dossier cible ;
2. poser l'échafaudage minimal correspondant à la pile technique choisie
   (structure de dossiers, fichier de dépendances, configuration du
   harnais de test) ;
3. faire un premier commit de cet échafaudage, avant toute ligne de
   logique métier ;
4. établir une baseline de tests verte — même un seul test trivial qui
   passe — pour que la première vraie tâche du plan parte d'un état déjà
   vérifié, jamais d'un chantier qui ne compile pas.

Ce n'est qu'après cette baseline verte que le flux commun démarre à
l'étape 2.

## Amorçage en mode amélioration

Quand le mode est `amelioration`, autopilot ne travaille jamais
directement sur l'arbre de travail existant : elle délègue à la skill
superpowers `using-git-worktrees` la création d'un espace isolé sur une
branche dédiée, à partir du dépôt déjà présent dans le dossier cible.
Toute la suite du flux — conception, plan, exécution, revue,
vérification — se déroule dans cet espace isolé, ce qui laisse l'arbre de
travail de l'utilisateur intact jusqu'à la livraison finale décrite dans
`DELIVERY.md`.
