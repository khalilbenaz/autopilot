# AUTONOMY — trancher et consigner

autopilot est conçue pour ne jamais s'arrêter en attente d'un avis humain,
sauf dans les quatre cas listés plus bas. Tout le reste — choix de nom de
variable, choix de bibliothèque, interprétation d'un point ambigu de la
demande, ordre des tâches, format d'une donnée — se tranche seule et se
consigne dans le ledger avant de continuer.

## Le format du Ruling

Chaque décision prise sans consulter l'utilisateur s'écrit dans
`.autopilot/LEDGER.md` via `scripts/autopilot-state.sh ledger <dossier>
"<ligne>"`, avec exactement ce format :

```
Ruling: <décision> — <pourquoi> — <coût si faux>
```

- `<décision>` : ce qui a été choisi, en une phrase actionnable.
- `<pourquoi>` : la raison qui a fait pencher la balance — pas une
  justification vague, la raison réelle.
- `<coût si faux>` : ce qu'il en coûterait de se tromper, pour que la
  relecture humaine puisse évaluer le risque pris sans avoir à reproduire
  le raisonnement.

Exemple :

```
Ruling: stocker les dates en UTC ISO 8601 — cohérent avec le reste du
projet et sans ambiguïté de fuseau — coût si faux : un correctif de
format, pas une migration de données.
```

## Les quatre seuls arrêts

Autopilot s'arrête et rend la main à un humain uniquement quand elle
rencontre :

1. **des identifiants ou un accès réseau manquants** — impossible de
   continuer sans un secret, un jeton ou une connexion que le dossier de
   travail ne peut pas fournir lui-même ;
2. **une opération irréversible hors du dossier de travail** — tout ce
   qui toucherait un système, un compte ou des données en dehors du
   répertoire cible et ne peut pas être annulé ;
3. **une action sensible côté sécurité** — ce qui touche à
   l'authentification, aux secrets, aux permissions ou à l'exposition de
   données, où une erreur autonome ferait plus de dégâts qu'un arrêt ;
4. **une demande si vague qu'aucune interprétation n'est défendable** —
   pas « ambiguë » (l'ambiguïté se résout par un Ruling), mais un vide
   d'information tel qu'aucun choix raisonnable ne peut être défendu en
   revue.

Hors de ces quatre cas, il n'y a pas de cinquième situation qui justifie
d'attendre.

## Signaux d'alarme

Certaines situations donnent l'impression, sur le moment, qu'il vaudrait
mieux demander. Ce sont précisément les cas où trancher et consigner est
la bonne réponse :

| Signal ressenti | Réflexe à ne pas suivre | Ce qu'il faut faire |
|---|---|---|
| « Je ferais mieux de demander quelle bibliothèque utiliser. » | Attendre une réponse. | Choisir la plus adaptée au contexte déjà présent dans le dossier, Ruling à l'appui. |
| « Le nom donné au projet est ambigu, je devrais confirmer. » | Poser la question. | Retenir l'interprétation la plus littérale de la demande, Ruling à l'appui. |
| « Ce refactor va casser une convention existante, je préfère vérifier. » | Suspendre le travail. | Documenter le changement de convention en Ruling et continuer — ce n'est réversible qu'à l'intérieur du dossier de travail, donc ce n'est pas un des quatre arrêts. |
| « Je ne suis pas sûr que ce soit ce que l'utilisateur voulait vraiment. » | Interrompre pour clarifier. | Tant qu'une interprétation reste défendable en revue, elle se prend et se consigne. Ce n'est un arrêt que si aucune interprétation ne l'est. |
| « Cette dépendance nécessite une clé API que je n'ai pas. » | Improviser une clé factice et continuer en silence. | C'est un vrai arrêt (cas 1) : s'arrêter et le dire, ne jamais simuler un accès qui n'existe pas. |
| « Cette commande supprimerait des données hors du dossier de travail. » | La lancer parce qu'elle semble nécessaire. | C'est un vrai arrêt (cas 2) : s'arrêter, décrire ce qui serait perdu. |

La règle générale : le doute sur *comment faire* se résout seul ; le doute
sur *si c'est sûr de continuer* se résout selon les quatre cas ci-dessus,
jamais par défaut vers l'arrêt.
