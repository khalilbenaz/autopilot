# DELIVERY — la définition de « fini »

Un run autopilot n'est déclaré terminé que lorsque toutes les conditions
ci-dessous sont réunies. Le rapport final les couvre dans cet ordre.

## Preuve, pas affirmation

Aucune phrase du rapport final n'affirme un succès sans citer, juste en
dessous, la sortie réelle de la commande qui le prouve. « Les tests
passent » n'est pas une preuve ; le collage exact de la sortie de la
commande de test (nombre de tests, verdict, code de sortie) l'est. Même
règle pour un build, un linter, ou toute autre vérification : la commande
lancée et sa sortie réelle, jamais une paraphrase.

Cette règle existe parce qu'elle a déjà été contournée sur ce projet même :
deux rapports produits par des implémenteurs de ce dépôt ont affirmé des
vérifications qui n'avaient pas été faites. `DELIVERY.md` ne laisse pas de
place à ce contournement — s'il n'y a pas de sortie collée, il n'y a pas
d'affirmation.

Concrètement, le rapport final doit contenir, chacun avec sa sortie
réelle :

- la commande de test complète du projet livré et son verdict final ;
- toute vérification supplémentaire pertinente (lint, build, shellcheck,
  etc.) réellement lancée pendant l'étape 8 (`verification-before-completion`).

## Traçabilité

Le rapport final nomme :

- la **branche** sur laquelle le travail a été livré (et, en mode
  amélioration, le worktree qui la porte) ;
- le chemin de la **spec** écrite à l'étape 2 (`brainstorming`) ;
- le chemin du **plan** écrit à l'étape 3 (`writing-plans`) ;
- la liste des **Rulings** pris pendant le run (au format défini dans
  `AUTONOMY.md`), pour qu'une relecture humaine puisse les revoir sans
  avoir à fouiller tout le ledger.

## Ce qui n'a jamais lieu

Le rapport final rappelle explicitement, sans exception, qu'aucune des
opérations suivantes n'a été effectuée :

- **merge** vers une autre branche ;
- **push** vers un dépôt distant ;
- **publication** d'un paquet, d'une release ou d'un artefact ;
- **déploiement** vers un environnement quelconque.

La branche livrée reste locale. Ces quatre opérations relèvent d'une
décision humaine, jamais d'autopilot — voir aussi `SKILL.md`, section 1.
