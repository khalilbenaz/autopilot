# DELIVERY — la définition de « fini »

Un run autopilot n'est déclaré terminé que lorsque toutes les conditions
ci-dessous sont réunies. Le rapport final suit le gabarit donné en fin de
ce fichier.

## Preuve, pas affirmation

Cette section applique l'étape 8 (`verification-before-completion`) au
rapport final lui-même : aucune phrase n'y affirme un succès sans citer,
juste en dessous, la sortie réelle de la commande qui le prouve. « Les
tests passent » n'est pas une preuve ; le collage exact de la sortie de la
commande de test (nombre de tests, verdict, code de sortie) l'est. Même
règle pour toute autre vérification citée : la commande réellement lancée
et sa sortie réelle, jamais une paraphrase, et jamais une vérification
listée sans avoir été exécutée.

Affirmer un succès sans preuve collée est une erreur récurrente et
coûteuse : elle ne demande aucun effort à écrire dans l'instant et ne se
découvre que tard, une fois la confiance déjà rompue. Cette règle ne
laisse aucune place à ce contournement — s'il n'y a pas de sortie collée,
il n'y a pas d'affirmation.

Concrètement, le rapport final doit contenir, chacun avec sa sortie
réelle :

- la commande de test complète du projet livré et son verdict final ;
- chaque vérification supplémentaire réellement lancée pendant l'étape 8
  (par exemple lint, build ou `shellcheck`, selon ce que le projet livré
  utilise déjà) — jamais une liste générique de vérifications possibles.

## Traçabilité

Le rapport final nomme :

- la **branche** sur laquelle le travail a été livré (et, en mode
  amélioration, le worktree qui la porte) — écrite dans `STATE.json` à
  l'étape 1 en création ou 1′ en amélioration ;
- le chemin de la **spec** — écrit dans `STATE.json` à l'étape 2
  (`brainstorming`) ;
- le chemin du **plan** — écrit dans `STATE.json` à l'étape 3
  (`writing-plans`) ;
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

## Gabarit du rapport final

Le rapport final reprend ces cinq sections, dans cet ordre :

1. **Mode et demande** — le mode retenu (`creation`/`amelioration`) et la
   demande reformulée en une phrase.
2. **Traçabilité** — branche (et worktree si amélioration), chemin de la
   spec, chemin du plan.
3. **Rulings** — la liste complète, au format de `AUTONOMY.md`, dans
   l'ordre chronologique où ils ont été pris.
4. **Preuves** — chaque vérification réellement lancée, commande suivie
   immédiatement de sa sortie réelle collée : la commande de test d'abord,
   puis toute vérification supplémentaire de l'étape 8.
5. **Ce qui n'a pas eu lieu** — le rappel explicite : pas de merge, pas de
   push, pas de publication, pas de déploiement.
