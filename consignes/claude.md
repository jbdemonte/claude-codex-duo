# Travailler avec Codex

Codex est ton collègue sur ce poste. Appelle-le toi-même : l'utilisateur ne doit jamais copier-coller quoi que ce soit entre vous.

## Quand l'appeler

- Quand l'utilisateur le demande avec ses mots : « demande à Codex », « fais-le faire par Codex », « qu'en pense Codex ».
- Sans qu'on te le demande, pour faire relire une spec ou du code non trivial que tu viens d'écrire.
- Pas pour une question, une petite correction ou de l'exploration.

## Nouvelle fonctionnalité ou changement important

1. Écris la spec, dans `tasks/` avec le numéro suivant si le projet utilise ce dossier.
2. Fais-la relire par Codex et corrige ce qui le mérite.
3. Résume-la et attends l'accord explicite de l'utilisateur. N'écris aucun code avant. Si la spec change ensuite, redemande son accord.
4. Par défaut, Codex code et tu relis. L'utilisateur peut inverser les rôles en le disant.
5. Lance les tests du projet. Celui qui n'a pas codé relit. Corrigez et relisez, quinze tours au maximum, puis demande à l'utilisateur comment continuer.

Une demande simple se traite directement, sans spec ni relecture.

## Comment l'appeler

Passe toujours par `__CODEX_SAFE__`, jamais par `codex` directement :

- `codex-safe lire "message"` : Codex lit et répond, sans rien modifier.
- `codex-safe coder "message"` : Codex modifie le projet, sans commiter.
- `codex-safe review <sha>` : Codex relit un commit.
- `codex-safe oublie` : à lancer au début d'une nouvelle tâche. Sinon, Codex garde le fil de la conversation dans ce projet.

<!-- windows -->
Sous Windows, lance `codex-safe` et `conso` avec l'outil Bash, pas avec PowerShell.

<!-- /windows -->
Pour un autre modèle, préfixe l'appel avec `DUO_MODEL=<modèle>`. Lance `coder` et `review` en arrière-plan, car ils peuvent durer plus de dix minutes.

Si `codex-safe` répond qu'un agent appelé ne peut pas rappeler son collègue, continue seul. S'il échoue autrement, arrête-toi et explique pourquoi en une phrase. Ne contourne pas l'échec : ces contrôles gardent les appels sur les abonnements.

## Bilan de fin de tâche

Dès qu'une tâche a modifié du code ou une spec, même pour une demande simple, termine ta réponse par ce bilan :

- **Relu par :** Codex, ou « personne » avec la raison.
- **Tours de relecture :** le nombre, quinze au maximum.
- **Tests :** les commandes lancées et leur résultat, ou « aucun ».
- **Reste ouvert :** ce qui n'est ni corrigé ni vérifié, ou « rien ».
- **Tokens :** la sortie de `__CONSO_CLAUDE__`, recopiée telle quelle.

## Règles communes

- Raconte ce que fait Codex en une ou deux phrases de français courant.
- Commite toi-même après avoir vérifié le diff, sur la branche courante, en suivant les règles du projet. Ajoute seulement les fichiers de la tâche.
- Si un fichier à modifier contient déjà des changements non commités, signale-le avant de commencer.
- Ne crée pas de branche sans qu'on te le demande. Ne fais jamais de push ni de merge.
