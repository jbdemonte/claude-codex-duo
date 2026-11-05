# Travailler avec Claude

Claude est ton collègue sur ce poste. Appelle-le toi-même : l'utilisateur ne doit jamais copier-coller quoi que ce soit entre vous.

## Quand l'appeler

- Quand l'utilisateur le demande avec ses mots : « demande à Claude », « fais-le faire par Claude », « qu'en pense Claude ».
- Sans qu'on te le demande, pour faire relire une spec ou du code non trivial que tu viens d'écrire.
- Pas pour une question, une petite correction ou de l'exploration.

## Nouvelle fonctionnalité ou changement important

1. Écris la spec, dans `tasks/` avec le numéro suivant si le projet utilise ce dossier.
2. Fais-la relire par Claude et corrige ce qui le mérite.
3. Résume-la et attends l'accord explicite de l'utilisateur. N'écris aucun code avant. Si la spec change ensuite, redemande son accord.
4. Par défaut, tu codes et Claude relit. L'utilisateur peut inverser les rôles en le disant.
5. Lance les tests du projet. Celui qui n'a pas codé relit. Corrigez et relisez, trois tours au maximum, puis demande à l'utilisateur comment continuer.

Une demande simple se traite directement, sans spec ni relecture.

## Comment l'appeler

Passe toujours par `__DUO__/claude-safe`, jamais par `claude` directement :

- `claude-safe lire "message"` : Claude lit et répond, sans rien modifier. Pour une relecture, indique-lui le commit à relire ou demande-lui de relire les changements non commités : il sait lancer `git show` et `git diff`.
- `claude-safe coder "message"` : Claude modifie le projet, sans commiter.
- `claude-safe oublie` : à lancer au début d'une nouvelle tâche. Sinon, Claude garde le fil de la conversation dans ce projet.

Pour un autre modèle, préfixe l'appel avec `DUO_MODEL=<modèle>`.

Lance toujours `claude-safe` hors du sandbox (`require_escalated`), dès le premier essai et même pour `oublie` : il a besoin du réseau, du trousseau et de son dossier d'état. Justification : « Relecture par Claude avec l'abonnement de l'utilisateur, clés API retirées. » Une relecture peut durer plusieurs minutes : attends la fin de la commande.

Si `claude-safe` répond qu'un agent appelé ne peut pas rappeler son collègue, continue seul. Si l'autorisation est refusée, ne cherche pas d'autre moyen, même `claude -p` : dis-le à l'utilisateur et rappelle-lui qu'il peut taper `/approve`. S'il échoue autrement, arrête-toi et explique pourquoi en une phrase. Ne contourne pas l'échec : ces contrôles gardent les appels sur les abonnements.

## Bilan de fin de tâche

Dès qu'une tâche a modifié du code ou une spec, même pour une demande simple, termine ta réponse par ce bilan :

- **Relu par :** Claude, ou « personne » avec la raison.
- **Tours de relecture :** le nombre, trois au maximum.
- **Tests :** les commandes lancées et leur résultat, ou « aucun ».
- **Reste ouvert :** ce qui n'est ni corrigé ni vérifié, ou « rien ».
- **Tokens :** la sortie de `__DUO__/conso`, recopiée telle quelle. Ce script reste dans le sandbox.

## Règles communes

- Raconte ce que fait Claude en une ou deux phrases de français courant.
- Commite toi-même après avoir vérifié le diff, sur la branche courante, en suivant les règles du projet. Ajoute seulement les fichiers de la tâche.
- Si un fichier à modifier contient déjà des changements non commités, signale-le avant de commencer.
- Ne crée pas de branche sans qu'on te le demande. Ne fais jamais de push ni de merge.
