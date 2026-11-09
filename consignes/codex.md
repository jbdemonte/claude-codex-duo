# Travailler avec Claude

Claude est ton collègue sur ce poste. Appelle-le toi-même pour lire et relire : l'utilisateur ne doit pas copier-coller entre vous.

## Quand l'appeler

- Quand l'utilisateur le demande avec ses mots : « demande à Claude », « qu'en pense Claude ».
- Sans qu'on te le demande, pour faire relire une spec ou du code non trivial que tu viens d'écrire.
- Pas pour une question, une petite correction ou de l'exploration.

## Nouvelle fonctionnalité ou changement important

1. Écris la spec, dans `tasks/` avec le numéro suivant si le projet utilise ce dossier. Elle doit suffire à celui qui codera, sans le contexte de cette conversation.
2. Fais-la relire par Claude et corrige ce qui le mérite.
3. Résume-la et attends l'accord explicite de l'utilisateur. N'écris aucun code avant. Si la spec change ensuite, redemande son accord.
4. Par défaut, tu codes et Claude relit. Si l'utilisateur veut que Claude code, passe-lui la main, comme indiqué dans « Faire coder Claude ».
5. Lance les tests du projet. Celui qui n'a pas codé relit. Corrigez et relisez, vingt-cinq tours au maximum, puis demande à l'utilisateur comment continuer.

Si l'utilisateur te demande de coder une spec déjà validée, code-la sans refaire les étapes 1 à 3, puis passe à l'étape 5. Si elle doit changer, redemande son accord.

Une demande simple se traite directement, sans spec ni relecture.

## Faire coder Claude

L'utilisateur veut voir Claude travailler. Quand Claude doit coder, y compris s'il dit « fais-le faire par Claude », ne le lance pas, sauf s'il demande explicitement de le faire en arrière-plan. Donne-lui cette phrase à taper dans sa session Claude :

> La spec <chemin> est validée. Code-la dans cette session, lance les tests, puis fais relire ton code par Codex.

Avant de t'arrêter, commite la spec si elle a changé et termine par le bilan, avec l'implémentation dans « Reste ouvert ».

Pour une demande simple sans spec, donne seulement une phrase qui décrit le travail, sans demander de relecture.

## Comment l'appeler

Passe toujours par `__CLAUDE_SAFE__`, jamais par `claude` directement :

- `claude-safe lire "message"` : Claude lit et répond, sans rien modifier. Pour une relecture, indique-lui le commit à relire ou demande-lui de relire les changements non commités : il sait lancer `git show` et `git diff`.
- `claude-safe coder "message"` : Claude modifie le projet, sans commiter. L'utilisateur ne voit pas son travail : lance-le seulement s'il demande explicitement de le faire en arrière-plan.
- `claude-safe oublie` : à lancer au début d'une nouvelle tâche. Sinon, Claude garde le fil de la conversation dans ce projet.

<!-- windows -->
Sous Windows, ne mets pas le message en argument : PowerShell 5.1 coupe les arguments qui contiennent des guillemets. Mets-le dans `DUO_MESSAGE`, entre `@'` et `'@`, sans rien échapper. `'@` doit être seul en début de ligne :

```powershell
$env:DUO_MESSAGE = @'
Relis les changements non commités de ce dépôt.
'@
__CLAUDE_SAFE__ lire
```

<!-- /windows -->
Pour un autre modèle, préfixe l'appel avec `DUO_MODEL=<modèle>`.

Lance toujours `claude-safe` hors du sandbox (`require_escalated`), dès le premier essai et même pour `oublie` : il a besoin du réseau, du trousseau et de son dossier d'état. Justification : « Relecture par Claude avec l'abonnement de l'utilisateur, clés API retirées. » Une relecture peut durer plusieurs minutes : attends la fin de la commande.

Si `claude-safe` répond qu'un agent appelé ne peut pas rappeler son collègue, continue seul. Si l'autorisation est refusée, ne cherche pas d'autre moyen, même `claude -p` : dis-le à l'utilisateur et rappelle-lui qu'il peut taper `/approve`. S'il échoue autrement, arrête-toi et explique pourquoi en une phrase. Ne contourne pas l'échec : ces contrôles gardent les appels sur les abonnements.

## Bilan de fin de tâche

Dès qu'une tâche a modifié du code ou une spec, même pour une demande simple, termine ta réponse par ce bilan :

- **Relu par :** Claude, ou « personne » avec la raison.
- **Tours de relecture :** le nombre, vingt-cinq au maximum.
- **Tests :** les commandes lancées et leur résultat, ou « aucun ».
- **Reste ouvert :** ce qui n'est ni corrigé ni vérifié, ou « rien ».
- **Tokens :** la sortie de `__CONSO_CODEX__`, recopiée telle quelle. __CONSO_SANDBOX__

## Règles communes

- Raconte ce que fait Claude en une ou deux phrases de français courant.
- Commite toi-même après avoir vérifié le diff, sur la branche courante, en suivant les règles du projet. Ajoute seulement les fichiers de la tâche.
- Si un fichier à modifier contient déjà des changements non commités, signale-le avant de commencer.
- Ne crée pas de branche sans qu'on te le demande. Ne fais jamais de push ni de merge.
