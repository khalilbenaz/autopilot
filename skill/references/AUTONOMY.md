# AUTONOMY — trancher et consigner

autopilot est conçue pour ne jamais s'arrêter en attente d'un avis humain,
sauf dans les quatre cas listés plus bas. Tout le reste — choix de nom de
variable, choix de bibliothèque, interprétation d'un point ambigu de la
demande, ordre des tâches, format d'une donnée — se tranche seul et se
consigne dans le ledger au moment où la décision est prise, pas
seulement au checkpoint de fin de tâche décrit dans `SKILL.md`.

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
2. **toute écriture hors du dossier de travail, réversible ou non** —
   toute modification d'un système, d'un compte ou de données en dehors
   du répertoire cible, même mineure et même facile à annuler. La
   réversibilité ne rattrape rien : une écriture réversible au mauvais
   endroit reste une écriture au mauvais endroit, et personne ne saura
   qu'il faut la défaire. Ceci ne concerne que l'**écriture** : lire hors
   du dossier de travail reste normal et ne déclenche jamais cet arrêt —
   les scripts de la skill vivent sous `~/.claude/skills/autopilot`, la
   sonde de quota lit le trousseau macOS, et rien de tout cela n'écrit
   hors du dossier cible ;
3. **une action sensible côté sécurité** — ce qui touche à
   l'authentification, aux secrets, aux permissions ou à l'exposition de
   données, où une erreur autonome ferait plus de dégâts qu'un arrêt ;
4. **une demande si vague qu'aucune interprétation n'est défendable** —
   pas « ambiguë » (l'ambiguïté se résout par un Ruling), mais un vide
   d'information tel qu'aucun choix raisonnable ne peut être défendu en
   revue.

Hors de ces quatre cas, il n'y a pas de cinquième situation qui justifie
d'attendre.

### Le mécanisme de l'arrêt

Un arrêt n'est pas qu'une intention : il a une sortie concrète, toujours
la même, dans l'ordre :

1. `scripts/autopilot-state.sh set <dossier> phase bloque` — la phase
   `bloque` est une valeur légale de `STATE.json`, voir
   `references/RESUMING.md` pour son rang dans le tableau des phases ;
2. `scripts/autopilot-state.sh ledger <dossier> "<ligne>"` avec ce
   format dédié, distinct du Ruling puisqu'il n'y a justement pas de
   décision prise :

   ```
   Arrêt: <situation rencontrée> — <ce qui manque ou est en jeu> — <ce qu'il faut pour reprendre>
   ```

3. s'arrêter là : ne pas retenter l'opération bloquante, ne pas
   improviser de contournement, ne rien afficher qui laisse croire que le
   travail continue.

Une fois la phase à `bloque`, `autopilot-state.sh done` continue de rendre
faux (le run n'est pas *terminé*, il est *arrêté*) : `autopilot-supervisor.sh`
reconnaît cette phase comme un état terminal et sort en code 3 sans relancer
`claude` — voir `SKILL.md`, section « Superviseur et quota », pour les
cinq codes de sortie du superviseur.

### Ce n'est pas un arrêt : la pause de quota

Un épuisement de quota constaté en plein travail n'entre pas dans les
quatre cas ci-dessus et n'écrit jamais `bloque`. C'est une pause
opérationnelle, pas une décision qui manque d'information : la phase
courante reste inchangée, l'épuisement est simplement consigné au ledger,
et c'est `autopilot-supervisor.sh` qui gère l'attente et la relance — voir
`SKILL.md`, section « Superviseur et quota ». Confondre les deux romprait
la reprise : un « arrêt »
attend un humain, une « pause de quota » n'attend qu'un reset et repart
seule.

## Signaux d'alarme

Certaines situations donnent l'impression, sur le moment, qu'il vaudrait
mieux demander. Ce sont précisément les cas où trancher et consigner est
la bonne réponse :

| Signal ressenti | Réflexe à ne pas suivre | Ce qu'il faut faire |
|---|---|---|
| « Je ferais mieux de demander quelle bibliothèque utiliser. » | Attendre une réponse. | Choisir la plus adaptée au contexte déjà présent dans le dossier, Ruling à l'appui. |
| « Le nom donné au projet est ambigu, je devrais confirmer. » | Poser la question. | Retenir l'interprétation la plus littérale de la demande, Ruling à l'appui. |
| « Ce refactor va casser une convention existante, difficile à annuler, je préfère vérifier. » | Suspendre le travail. | Documenter le changement de convention en Ruling et continuer — c'est le **lieu** qui compte, pas la réversibilité : irréversible mais à l'intérieur du dossier de travail n'est pas un des quatre arrêts. |
| « Je ne suis pas sûr que ce soit ce que l'utilisateur voulait vraiment. » | Interrompre pour clarifier. | Tant qu'une interprétation reste défendable en revue, elle se prend et se consigne. Ce n'est un arrêt que si aucune interprétation ne l'est. |
| « Cette dépendance nécessite une clé API que je n'ai pas. » | Improviser une clé factice et continuer en silence. | C'est un vrai arrêt (cas 1) : `phase bloque`, un `Arrêt:` au ledger, et s'arrêter là. |
| « Cette commande supprimerait des données hors du dossier de travail. » | La lancer parce qu'elle semble nécessaire. | C'est un vrai arrêt (cas 2) : `phase bloque`, un `Arrêt:` décrivant ce qui serait perdu, et s'arrêter là. |
| « Ce script ajouterait juste une ligne à un fichier de configuration hors du dossier, c'est mineur et je peux la retirer après. » | La lancer parce qu'elle semble anodine et réversible. | C'est quand même un vrai arrêt (cas 2) : toute écriture hors du dossier de travail arrête, même mineure et même réversible — `phase bloque`, un `Arrêt:` au ledger, et s'arrêter là. |
| « Je dois lire la configuration de l'utilisateur hors du dossier pour comprendre le contexte. » | S'arrêter par prudence, en confondant lecture et écriture. | Ce n'est pas un arrêt : lire hors du dossier de travail est normal et attendu (scripts de la skill, documentation, trousseau pour la sonde de quota). Seule l'écriture hors du dossier est concernée par le cas 2. |
| « L'utilisateur a demandé le push, mais pousser est une écriture, je devrais m'arrêter au cas 2. » | S'arrêter en `bloque`. | Ce n'est pas le cas 2 : un push demandé est un acte sortant couvert par la demande, pas une écriture faite à l'insu de l'utilisateur — voir « Actes sortants » plus bas. Il a lieu après tests verts, pas avant. |

La règle générale : le doute sur *comment faire* se résout seul avec un
Ruling ; le doute sur *si c'est sûr de continuer* se résout selon les
quatre cas ci-dessus par un arrêt en `bloque`, jamais par défaut vers
l'attente.

## Actes sortants : merge, push, publication, déploiement

Autopilot ne merge, ne pousse, ne publie et ne déploie jamais de sa propre initiative.
Ce sont des actes sortants, une catégorie à part des quatre arrêts
ci-dessus : ils ne bloquent pas le run, ils exigent seulement d'être
couverts par la demande de l'utilisateur avant d'avoir lieu.

Le cas 2 (toute écriture hors du dossier de travail) ne les concerne pas.
Une écriture hors dossier au sens du cas 2 est une modification faite à
l'insu de l'utilisateur, sur un système ou des données qui n'ont rien à
voir avec la livraison. Un push, un merge, une publication ou un
déploiement sont l'inverse : la destination normale d'une branche
terminée, jamais faits en silence, toujours en réponse à une demande.
Ce n'est pas l'écriture qui distingue les deux, c'est l'absence
d'autorisation — et ici, l'autorisation existe dès que l'utilisateur l'a
nommée.

Quand l'utilisateur demande explicitement un de ces actes — « pousse »,
« mets à jour la version installée et GitHub », « publie la release »,
« déploie en prod » — c'est une partie du livrable comme une autre, et
autopilot le fait. Rien de plus n'est approuvé par avance, et rien de
moins n'est retenu par prudence excessive une fois la demande couverte.

### Garde-fous

1. **Strictement ce qui est nommé.** Une demande de push n'autorise pas un déploiement ;
   une demande de mise à jour de l'application installée n'autorise pas
   une publication de release. Chaque acte se prend un par un, et seul
   celui que la demande couvre a lieu.
2. **Jamais avant que les preuves soient réunies.** Ces actes n'ont lieu
   qu'après l'étape 8 (vérification), avec la sortie réelle des tests à
   l'appui. Pousser du rouge est interdit, même si l'utilisateur a demandé
   le push : dans ce cas, `phase bloque`, un `Arrêt:` au ledger, et la
   décision revient à l'humain.
3. **L'implicite ne vaut pas autorisation.** « Livre-le », « termine »,
   « fais le nécessaire » ne sont pas des demandes de push. Dans le doute,
   la branche reste locale, et le rapport final le dit au lieu de deviner.
4. **Un dépôt créé est privé par défaut.** Si la demande implique de créer
   un dépôt distant, il est créé privé, sauf si l'utilisateur a demandé
   explicitement qu'il soit public. Rendre public est un acte à part, qui
   doit être nommé pour lui-même.
5. **Les opérations git destructives restent des arrêts**, même sous une
   demande générale de push : `push --force`, réécriture d'historique,
   suppression de branche distante. Elles exigent d'être nommées pour
   elles-mêmes ; à défaut, `phase bloque` et un `Arrêt:` au ledger.
6. **Tout acte de ce type est consigné au ledger** au moment où il a lieu
   — au format Ruling, `<pourquoi>` étant la formulation de la demande qui
   le couvre — et listé dans le rapport final avec cette même couverture,
   voir `DELIVERY.md`.
