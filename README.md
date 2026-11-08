# duo

Claude Code et Codex CLI travaillent ensemble sur tes projets, sans copier-coller. Chacun peut demander à l'autre de relire, de coder ou de donner son avis, avec tes abonnements et sans clé API.

## Prérequis

- macOS, avec `git` et `/usr/bin/python3`.
- Ou Windows, avec [Git for Windows](https://git-scm.com/download/win) et Python 3.14 ou plus : `winget install Python.Python.3.14`. Les raccourcis `python` du Microsoft Store ne suffisent pas.
- Claude Code, connecté avec un compte claude.ai : `claude auth login`.
- Codex CLI, connecté avec un compte ChatGPT : `codex login`. Les identifiants doivent être dans `~/.codex/auth.json`.
- `CLAUDE_CONFIG_DIR` et `CODEX_HOME` non définis : `install.sh` s'arrête sinon.

## Avant de commencer : coupe l'usage payant

Au-delà du quota, l'usage payant peut prendre le relais au lieu de tout arrêter. Les scripts ont un verrou contre ça, mais il est partiel et ne protège pas un `claude` ou un `codex` lancé à la main :

- **Claude :** avec les crédits d'usage, Claude Code passe au tarif à l'usage. Désactive-les dans [Settings > Usage](https://claude.ai/settings/usage), puis lance `claude auth login` pour mettre à jour le compte local. `claude-safe` refuse de tourner tant qu'ils sont activés.
- **Codex :** une fois les limites du forfait atteintes, l'usage puise dans le solde de crédits. Vérifie ce solde et le rechargement automatique dans Codex Settings > Usage Dashboard. `codex-safe` s'arrête à 90 % du quota, d'après les journaux locaux.

Sur une nouvelle machine, lance une fois `codex` à la main : sans journal, le quota est inconnu et `codex-safe` refuse de tourner.

## Installation

```sh
git clone <adresse-du-depot> duo
cd duo
./install.sh
```

Ouvre ensuite une nouvelle session `claude` ou `codex` pour charger les consignes.

Sous Windows, lance ces commandes dans Git Bash. Claude appelle Codex avec son outil Bash. Codex, qui travaille sous PowerShell, appelle Claude par le `bash.exe` de Git et lui passe le message dans la variable `DUO_MESSAGE` : PowerShell 5.1 coupe les arguments qui contiennent des guillemets. Les consignes installées expliquent tout cela à Codex.

Garde ce dossier : les consignes installées pointent vers lui. Si tu le déplaces, relance `./install.sh`.

`install.sh` peut être relancé sans risque. Il fait quatre choses :

- Il ajoute les consignes à `~/.claude/CLAUDE.md` et `~/.codex/AGENTS.md`, entre deux balises `duo`, sans toucher au reste de ces fichiers.
- Il interdit à Claude d'appeler `codex` directement, dans `~/.claude/settings.json`. Sous Windows, la règle vaut aussi pour son outil PowerShell.
- Il enregistre les emplacements de `claude`, de `codex` et de Python dans `chemins.sh`, qui n'est pas versionné.
- Il lance `codex-safe check`, qui vérifie les logins, les réglages et le verrou de dépense. Si ce contrôle échoue, l'installation reste faite, mais duo refuse les appels tant que le point signalé n'est pas réglé.

Avant de modifier l'un de ces trois fichiers de réglages, il le copie dans `~/.local/state/duo/sauvegardes`. `chemins.sh` est simplement recréé.

## Utilisation

Lance `claude` ou `codex` dans ton projet et parle normalement. Il n'y a aucune commande à retenir :

- « qu'en pense Codex ? »
- « fais-le faire par Codex »
- « fais relire ton code par Claude »

Pour une nouvelle fonctionnalité, l'agent écrit une spec, la fait relire par son collègue et attend ton accord. Ensuite, l'un code, l'autre relit, en trois tours au maximum. Une demande simple se traite directement, sans spec ni relecture.

Quand une tâche a modifié du code ou une spec, l'agent termine par un bilan : qui a relu, combien de tours, quels tests ont été lancés, ce qui reste ouvert et les tokens utilisés.

Avec `approvals_reviewer = "auto_review"` dans la config Codex, un relecteur automatique décide si Codex peut lancer `claude-safe`. Demande donc la relecture explicitement : un appel que Codex décide seul peut être refusé. Après un refus, `/approve` autorise cette action une fois.

## Ce qui est garanti

Les scripts imposent ces protections :

- Les clés API et les adresses de fournisseur sont retirées de l'environnement.
- L'appel est refusé si le login n'est pas celui d'un abonnement.
- L'appel est refusé si les réglages visent une autre destination : `openai_base_url`, `chatgpt_base_url`, `profile` ou un autre `model_provider` dans `~/.codex/config.toml`, `~/.codex/managed_config.toml` ou leurs équivalents système (`/etc/codex` sur Mac, `%ProgramData%\OpenAI\Codex` sous Windows), même dans un profil inactif, `ANTHROPIC_BASE_URL`, une clé, `apiKeyHelper` ou un fournisseur cloud dans les réglages de Claude. Seul le nom du réglage est affiché, jamais sa valeur.
- L'appel est refusé si `CLAUDE_CONFIG_DIR` ou `CODEX_HOME` sont définis, ou si `DUO_MODEL` n'est pas un simple nom de modèle.
- Un agent appelé ne peut pas rappeler son collègue, donc ils ne peuvent pas s'appeler en boucle.
- `codex-safe lire` tourne en lecture seule, dans le sandbox de Codex.

Ces protections réduisent le risque sans le supprimer :

- `claude-safe` refuse de tourner si l'usage supplémentaire est activé ou inconnu dans `~/.claude.json`. Ce champ interne reflète le compte à sa dernière mise à jour locale.
- `codex-safe` refuse de tourner à partir de 90 % du quota, d'après le dernier relevé des journaux locaux. Un appel déjà lancé n'est pas interrompu, et l'usage d'une autre machine n'est pas vu. Juste après un changement de login, le relevé peut être celui de l'ancien compte.
- Les réglages déployés par une entreprise avec un outil de gestion des Mac, ou sous Windows par les stratégies du registre, ne sont pas lus.
- `claude-safe lire` interdit à Claude ses outils d'édition. Une commande déjà autorisée dans ses réglages pourrait quand même écrire.
- `claude-safe coder` bloque les formes courantes de commit, push, merge, rebase et reset. Claude a accès au shell, donc un autre moyen reste possible.
- `settings.json` bloque les appels habituels à `codex`, mais pas par exemple `npx @openai/codex`.
- Codex compresse désormais ses journaux. Pour les lire, `controle` a besoin de Python 3.14 ou plus. Sinon, il refuse les appels. Le `/usr/bin/python3` de macOS est plus ancien : si ce refus apparaît sur Mac, installe un Python récent, par exemple avec `brew install python`, puis relance `./install.sh`.

Ces règles sont seulement des consignes, qu'un agent peut oublier :

- Attendre ton accord avant de coder.
- Limiter la relecture à trois tours.
- Écrire le bilan de fin de tâche.
- Ne jamais pousser ni fusionner, et ne pas créer de branche sans demande.
- Ne pas appeler `claude` directement depuis Codex.

Quatre limites à connaître :

- Le verrou de dépense lit des formats internes. S'ils changent, le verrou peut d'abord se fier à un ancien relevé, puis il refuse les appels jusqu'à la mise à jour de `controle`.
- Un `claude` ou un `codex` que tu lances toi-même ne passe pas par ces scripts. Il utilise le login actif : vérifie-le avec `codex login status` et `claude auth status`.
- `codex-safe review` n'est pas en lecture seule. Codex peut y exécuter du code et modifier le projet.
- Sous Windows, le sandbox de Codex tourne sous un autre compte, qui ne voit ni Python ni les journaux : Codex lance donc `conso` hors du sandbox, avec ton accord.

## Les scripts

Les agents les utilisent eux-mêmes. Tu n'as pas à les lancer.

| Commande | Rôle |
|---|---|
| `codex-safe lire "message"` | Codex lit et répond, sans rien modifier |
| `codex-safe coder "message"` | Codex modifie le projet, sans commiter |
| `codex-safe review <sha>` | Codex relit un commit |
| `codex-safe check` | Vérifie les logins, les réglages et le verrou de dépense |
| `claude-safe lire "message"` | Claude lit et répond, sans rien modifier |
| `claude-safe coder "message"` | Claude modifie le projet, sans commiter |
| `codex-safe oublie`, `claude-safe oublie` | La prochaine demande repart de zéro |
| `conso` | Donne les tokens de la session et du fil du collègue, d'après les journaux locaux |

`DUO_MODEL=<modèle>` choisit un autre modèle pour un appel.

## Mise à jour

```sh
git pull && ./install.sh
```

Ouvre ensuite une nouvelle session.

Ces scripts dépendent de formats internes à `claude` et `codex`, qui peuvent changer sans prévenir. Après une mise à jour de l'un des deux, fais un essai sur un dépôt jetable : demande une petite modification à Codex, puis une relecture par Claude. `codex-safe check` ne prouve pas qu'un appel complet fonctionne.

## Désinstallation

1. Retire le bloc entre les balises `duo` dans `~/.claude/CLAUDE.md` et `~/.codex/AGENTS.md`.
2. Retire les deux règles `deny` sur `codex` dans `~/.claude/settings.json`, sauf si tu les avais avant duo.
3. Supprime ce dossier et `~/.local/state/duo`.
