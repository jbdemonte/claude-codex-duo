#!/bin/sh
# Installe ou met à jour duo pour l'utilisateur courant. Peut être relancé sans risque.
set -eu

stop() { echo "ARRÊT : $1" >&2; exit 1; }

case $(uname) in
  Darwin) windows= ;;
  MINGW*|MSYS*) windows=1 ;;
  *) stop "duo ne fonctionne que sur macOS, et sous Windows depuis Git Bash." ;;
esac
[ -z "${CLAUDE_CONFIG_DIR:-}${CODEX_HOME:-}" ] || stop "duo ne gère pas CLAUDE_CONFIG_DIR ni CODEX_HOME."
cd "$(dirname "$0")"
duo=$(pwd -P)
claude=$(command -v claude) || stop "Claude Code est introuvable."
codex=$(command -v codex) || stop "Codex CLI est introuvable."

# Python 3.14 ou plus sait lire les journaux compressés de Codex.
has_zstd() { "$1" -I -c 'import compression.zstd' 2>/dev/null; }
if [ -z "$windows" ]; then
  python=/usr/bin/python3
  other=$(command -v python3 || true)
  if [ -n "$other" ] && ! has_zstd "$python" && has_zstd "$other"; then python=$other; fi
  bash_exe= duo_windows= python_windows=
else
  # Les raccourcis python du Microsoft Store ne sont pas de vrais Python : has_zstd les écarte.
  python=
  for candidate in $(command -v python3 python || true) \
      "$(cygpath -u "$LOCALAPPDATA")"/Programs/Python/Python3*/python.exe \
      "$(cygpath -u "$PROGRAMFILES")"/Python3*/python.exe; do
    if has_zstd "$candidate"; then python=$candidate; fi
  done
  [ -n "$python" ] || stop "Python 3.14 ou plus est introuvable : winget install Python.Python.3.14"
  # Codex lance ses commandes avec PowerShell : il appelle claude-safe par le bash.exe de Git.
  bash_exe="$(cygpath -w /)bin\\bash.exe"
  [ -f "$(cygpath -u "$bash_exe")" ] || stop "bash.exe de Git for Windows est introuvable."
  duo_windows=$(cygpath -m "$duo") python_windows=$(cygpath -w "$python")
fi

# Les chemins doivent arriver tels quels : Git Bash convertirait ceux de la forme /c/...
MSYS2_ARG_CONV_EXCL='*' "$python" -X utf8 - "$duo" "$codex" "$claude" "$python" \
  "$bash_exe" "$duo_windows" "$python_windows" <<'EOF'
import datetime
import json
import os
import re
import shlex
import shutil
import sys
import tempfile

duo, codex, claude, python, bash_exe, duo_windows, python_windows = sys.argv[1:]
windows = bool(duo_windows)
home = os.path.expanduser('~')
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
backups = os.path.join(home, '.local/state/duo/sauvegardes', f'{stamp}-{os.getpid()}')
start, end = '<!-- duo:debut -->', '<!-- duo:fin -->'


def read(path):
    if not os.path.exists(path):
        return ''
    with open(path, encoding='utf-8') as source:
        return source.read()


if windows:
    # Claude lance codex-safe avec son outil Bash, Codex lance claude-safe avec PowerShell.
    commands = {
        '__CODEX_SAFE__': f'{duo}/codex-safe',
        '__CONSO_CLAUDE__': f'{shlex.quote(python)} -X utf8 {duo}/conso',
        '__CLAUDE_SAFE__': f"& '{bash_exe}' '{duo_windows}/claude-safe'",
        '__CONSO_CODEX__': f"& '{python_windows}' -X utf8 '{duo_windows}/conso'",
        # Le sandbox de Codex tourne sous un autre compte Windows, qui ne voit ni Python ni les journaux.
        '__CONSO_SANDBOX__': 'Lance-le aussi hors du sandbox (`require_escalated`) : sous Windows, le sandbox ne voit ni Python ni les journaux.',
    }
else:
    # conso lance /usr/bin/python3 : un Python plus récent doit être nommé.
    conso = f'{duo}/conso' if python == '/usr/bin/python3' else f'{shlex.quote(python)} {duo}/conso'
    commands = {
        '__CODEX_SAFE__': f'{duo}/codex-safe',
        '__CONSO_CLAUDE__': conso,
        '__CLAUDE_SAFE__': f'{duo}/claude-safe',
        '__CONSO_CODEX__': conso,
        '__CONSO_SANDBOX__': 'Ce script reste dans le sandbox.',
    }


def instructions(template):
    text = read(template)
    # Les passages propres à Windows sont gardés sous Windows et retirés ailleurs.
    text = re.sub(r'<!-- windows -->\n(.*?)<!-- /windows -->\n', r'\1' if windows else '', text, flags=re.S)
    for name, command in commands.items():
        text = text.replace(name, command)
    return text.strip()


def with_block(template, path):
    block = f"{start}\n{instructions(template)}\n{end}\n"
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
    rules = ['Bash(codex *)', f'Bash({codex} *)']
    if windows:
        rules += ['Bash(codex.exe *)', f'Bash({codex}.exe *)', 'PowerShell(codex *)', 'PowerShell(codex.exe *)']
    missing = [rule for rule in rules if rule not in deny]
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
    # Un lien symbolique reste en place : c'est le fichier qu'il désigne qui change.
    target = os.path.realpath(path)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    # Le fichier temporaire est créé en 0600 : il peut contenir des réglages confidentiels.
    descriptor, temporary = tempfile.mkstemp(prefix='.duo-', dir=os.path.dirname(target))
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8') as output:
            output.write(text)
        if os.path.exists(target):
            shutil.copymode(target, temporary)
            os.makedirs(backups, exist_ok=True)
            shutil.copy2(target, os.path.join(backups, os.path.basename(path)))
        os.replace(temporary, target)
    except BaseException:
        os.unlink(temporary)
        raise
    print(f'Mis à jour : {path}')


# Tout est calculé avant la première écriture, et chaque fichier est remplacé d'un coup.
# Si une écriture échoue, les fichiers déjà remplacés restent corrects : il suffit de relancer.
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
# Sans newline, Python écrirait des fins de ligne CRLF sous Windows, que sh ne lit pas.
with open('chemins.sh', 'w', encoding='utf-8', newline='\n') as paths:
    paths.write(f'CODEX={shlex.quote(codex)}\nCLAUDE={shlex.quote(claude)}\nPYTHON={shlex.quote(python)}\n')
EOF

echo "Installé. Ouvre une nouvelle session claude ou codex pour charger les consignes."
"$duo/codex-safe" check || stop "duo refusera les appels tant que ce point n'est pas réglé."
