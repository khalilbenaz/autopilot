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

La recherche de fichiers visibles ne descend que sur les deux premiers
niveaux du dossier (`find ... -maxdepth 2` dans le script) : un fichier
visible enterré plus profondément que ça n'est pas vu par la détection et
ne change pas son verdict. Un dossier dont tout le contenu visible vit à
trois niveaux ou plus sera donc vu comme vide, donc `creation`.

### Le cas du simple README

Un dossier qui ne contient qu'un `README.md` compte comme un projet
**existant**, donc **amélioration** — pas création. Cette règle n'est pas
négociable au moment de l'exécution : un `README.md`, même seul, porte
déjà une intention écrite (nom du projet, description, parfois des choix
déjà faits). Se tromper vers *création* ferait échafauder un projet neuf
par-dessus une intention déjà posée, ce qui est plus coûteux à défaire
qu'un déclenchement prudent vers *amélioration* qui, au pire, lit un peu
de contexte supplémentaire avant d'agir. Entre les deux erreurs possibles,
une seule est acceptable, et `autopilot-detect.sh` est écrit pour ne
jamais commettre l'autre.

Aucune des deux branches ne pose de question à l'utilisateur : le mode
retenu est annoncé en une ligne, consigné dans `STATE.json` via
`autopilot-state.sh init`, et le travail continue.

## Amorçage en mode création

Quand le mode est `creation`, avant d'entrer dans le flux commun (étape 2,
`brainstorming`), autopilot amorce le projet elle-même, **sans présumer
de la pile technique** :

1. initialiser un dépôt git dans le dossier cible ;
2. écrire un `.gitignore` minimal qui exclut au moins `.autopilot/` ;
3. faire un premier commit de ce point de départ — dépôt et
   `.gitignore` seuls, aucune structure de dossiers ni fichier de
   dépendances spécifique à une pile ;
4. ce point de départ est déjà la baseline verte : rien n'y est cassé,
   puisque rien de spécifique à une pile n'y existe encore pour casser
   quoi que ce soit. Ce n'est pas une baseline au sens d'un harnais de
   test qui tourne réellement — ça, ça suppose une pile déjà choisie, et
   vient plus tard.

Le choix de la pile technique n'appartient pas à cette étape : c'est
`brainstorming` (étape 2) qui le tranche, comme n'importe quel autre choix
de conception. L'échafaudage propre à la pile retenue (structure de
dossiers, fichier de dépendances, harnais de test réel) vient ensuite,
comme première tâche du plan écrit à l'étape 3 — jamais avant, et jamais
par présomption sur un dossier qui pourrait encore devenir n'importe quoi.

## Amorçage en mode amélioration

Quand le mode est `amelioration`, autopilot ne travaille jamais
directement sur l'arbre de travail existant : elle délègue à la skill
superpowers `using-git-worktrees` la création d'un espace isolé sur une
branche dédiée, à partir du dépôt déjà présent dans le dossier cible. Le
même `.gitignore` (excluant au moins `.autopilot/`) est complété si besoin
dans cet espace isolé, avant le premier commit qui suit. Toute la suite du
flux — conception, plan, exécution, revue, vérification — se déroule dans
cet espace isolé, ce qui laisse l'arbre de travail de l'utilisateur intact
jusqu'à la livraison finale décrite dans `DELIVERY.md`.
