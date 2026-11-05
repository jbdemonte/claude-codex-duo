# duo

Claude Code et Codex CLI travaillent ensemble sur tes projets, sans copier-coller. Chacun peut demander à l'autre de relire, de coder ou de donner son avis, avec tes abonnements et sans clé API.

## Prérequis

- macOS, avec `git` et `/usr/bin/python3`.
- Claude Code, connecté avec un compte claude.ai : `claude auth login`.
- Codex CLI, connecté avec un compte ChatGPT : `codex login`. Les identifiants doivent être dans `~/.codex/auth.json`.
- `CLAUDE_CONFIG_DIR` et `CODEX_HOME` non définis : `install.sh` s'arrête sinon.

## Avant de commencer : coupe l'usage payant

Les scripts vérifient que tu utilises un abonnement, mais ils ne voient pas ce qui se passe au-delà du quota. Si l'usage payant est actif, les agents continuent au lieu de s'arrêter :

- **Claude :** avec les crédits d'usage, Claude Code passe au tarif à l'usage. Désactive-les dans [Settings > Usage](https://claude.ai/settings/usage).
- **Codex :** une fois les limites du forfait atteintes, l'usage puise dans le solde de crédits. Vérifie ce solde et le rechargement automatique dans Codex Settings > Usage Dashboard.

## Installation

```sh
git clone <adresse-du-depot> duo
cd duo
./install.sh
```

Ouvre ensuite une nouvelle session `claude` ou `codex` pour charger les consignes.

Garde ce dossier : les consignes installées pointent vers lui. Si tu le déplaces, relance `./install.sh`.

`install.sh` peut être relancé sans risque. Il fait quatre choses :

- Il ajoute les consignes à `~/.claude/CLAUDE.md` et `~/.codex/AGENTS.md`, entre deux balises `duo`, sans toucher au reste de ces fichiers.
- Il interdit à Claude d'appeler `codex` directement, dans `~/.claude/settings.json`.
- Il enregistre les emplacements de `claude` et de `codex` dans `chemins.sh`, qui n'est pas versionné.
- Il vérifie les deux logins.

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
- Un agent appelé ne peut pas rappeler son collègue, donc ils ne peuvent pas s'appeler en boucle.
- `codex-safe lire` tourne en lecture seule, dans le sandbox de Codex.

Ces protections réduisent le risque sans le supprimer :

- `claude-safe lire` interdit à Claude ses outils d'édition. Une commande déjà autorisée dans ses réglages pourrait quand même écrire.
- `claude-safe coder` bloque les formes courantes de commit, push, merge, rebase et reset. Claude a accès au shell, donc un autre moyen reste possible.
- `settings.json` bloque les appels habituels à `codex`, mais pas par exemple `npx @openai/codex`.

Ces règles sont seulement des consignes, qu'un agent peut oublier :

- Attendre ton accord avant de coder.
- Limiter la relecture à trois tours.
- Écrire le bilan de fin de tâche.
- Ne jamais pousser ni fusionner, et ne pas créer de branche sans demande.
- Ne pas appeler `claude` directement depuis Codex.

Trois limites à connaître :

- Aucun script n'empêche l'usage payant au-delà du quota : voir « Avant de commencer ».
- Un `claude` ou un `codex` que tu lances toi-même ne passe pas par ces scripts. Il utilise le login actif : vérifie-le avec `codex login status` et `claude auth status`.
- `codex-safe review` n'est pas en lecture seule. Codex peut y exécuter du code et modifier le projet.

## Les scripts

Les agents les utilisent eux-mêmes. Tu n'as pas à les lancer.

| Commande | Rôle |
|---|---|
| `codex-safe lire "message"` | Codex lit et répond, sans rien modifier |
| `codex-safe coder "message"` | Codex modifie le projet, sans commiter |
| `codex-safe review <sha>` | Codex relit un commit |
| `codex-safe check` | Vérifie les logins Claude et Codex |
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

Ces scripts dépendent de formats internes à `claude` et `codex`, qui peuvent changer sans prévenir. Après une mise à jour de l'un des deux, fais un essai sur un dépôt jetable : demande une petite modification à Codex, puis une relecture par Claude. `codex-safe check` ne vérifie que les logins.

## Désinstallation

1. Retire le bloc entre les balises `duo` dans `~/.claude/CLAUDE.md` et `~/.codex/AGENTS.md`.
2. Retire les deux règles `deny` sur `codex` dans `~/.claude/settings.json`.
3. Supprime ce dossier et `~/.local/state/duo`.
