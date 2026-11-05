#!/bin/sh
# Installe ou met à jour duo pour l'utilisateur courant. Peut être relancé sans risque.
set -eu

stop() { echo "ARRÊT : $1" >&2; exit 1; }

[ "$(uname)" = Darwin ] || stop "duo ne fonctionne que sur macOS pour l'instant."
[ -z "${CLAUDE_CONFIG_DIR:-}${CODEX_HOME:-}" ] || stop "duo ne gère pas CLAUDE_CONFIG_DIR ni CODEX_HOME."
cd "$(dirname "$0")"
duo=$(pwd -P)
claude=$(command -v claude) || stop "Claude Code est introuvable."
codex=$(command -v codex) || stop "Codex CLI est introuvable."

/usr/bin/python3 - "$duo" "$codex" "$claude" <<'EOF'
import datetime
import json
import os
import shlex
import shutil
import sys

duo, codex, claude = sys.argv[1:]
home = os.path.expanduser('~')
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
backups = os.path.join(home, '.local/state/duo/sauvegardes', f'{stamp}-{os.getpid()}')
start, end = '<!-- duo:debut -->', '<!-- duo:fin -->'


def read(path):
    if not os.path.exists(path):
        return ''
    with open(path, encoding='utf-8') as source:
        return source.read()


def with_block(template, path):
    block = f"{start}\n{read(template).replace('__DUO__', duo).strip()}\n{end}\n"
    old = read(path)
    if old.count(start) != old.count(end) or old.count(start) > 1:
        sys.exit(f'ARRÊT : balises duo incohérentes dans {path}. Rien n\'a été modifié.')
    if start in old:
        before, rest = old.split(start, 1)
        return before + block + rest.split(end, 1)[1].lstrip('\n')
    return old.rstrip('\n') + '\n\n' + block if old.strip() else block


def with_rules(path):
    text = read(path)
    try:
        settings = json.loads(text) if text.strip() else {}
    except ValueError:
        sys.exit(f'ARRÊT : {path} n\'est pas un JSON valide. Rien n\'a été modifié.')
    deny = settings.setdefault('permissions', {}).setdefault('deny', [])
    missing = [rule for rule in ('Bash(codex *)', f'Bash({codex} *)') if rule not in deny]
    if not missing:
        return text
    deny += missing
    return json.dumps(settings, indent=2, ensure_ascii=False) + '\n'


def same_file(first, second):
    if os.path.exists(first) and os.path.exists(second):
        return os.path.samefile(first, second)
    return os.path.realpath(first) == os.path.realpath(second)


def save(path, text):
    if text == read(path):
        print(f'Inchangé : {path}')
        return
    if os.path.exists(path):
        os.makedirs(backups, exist_ok=True)
        shutil.copy2(path, backups)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as target:
        target.write(text)
    print(f'Mis à jour : {path}')


# Tout est calculé avant la première écriture : une erreur ne laisse rien à moitié installé.
claude_md = os.path.join(home, '.claude/CLAUDE.md')
agents_md = os.path.join(home, '.codex/AGENTS.md')
settings_json = os.path.join(home, '.claude/settings.json')
if same_file(claude_md, agents_md):
    sys.exit('ARRÊT : ~/.claude/CLAUDE.md et ~/.codex/AGENTS.md pointent vers le même fichier. Rien n\'a été modifié.')
changes = [
    (claude_md, with_block('consignes/claude.md', claude_md)),
    (agents_md, with_block('consignes/codex.md', agents_md)),
    (settings_json, with_rules(settings_json)),
]
for path, text in changes:
    save(path, text)
with open('chemins.sh', 'w', encoding='utf-8') as paths:
    paths.write(f'CODEX={shlex.quote(codex)}\nCLAUDE={shlex.quote(claude)}\n')
EOF

"$duo/codex-safe" check || stop "connecte-toi avec claude auth login et codex login, puis relance ./install.sh."
echo "Terminé. Ouvre une nouvelle session claude ou codex pour charger les consignes."
