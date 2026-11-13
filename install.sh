#!/bin/sh
# Install or update duo for the current user. Safe to run again.
set -eu

stop() { echo "STOP: $1" >&2; exit 1; }

case $(uname) in
  Darwin) windows= ;;
  MINGW*|MSYS*) windows=1 ;;
  *) stop "duo only works on macOS, or on Windows from Git Bash." ;;
esac
[ -z "${CLAUDE_CONFIG_DIR:-}${CODEX_HOME:-}" ] || stop "duo does not support CLAUDE_CONFIG_DIR or CODEX_HOME."
cd "$(dirname "$0")"
duo=$(pwd -P)
claude=$(command -v claude) || stop "Claude Code not found."
codex=$(command -v codex) || stop "Codex CLI not found."

# Python 3.14 or later can read compressed Codex logs.
has_zstd() { "$1" -I -c 'import compression.zstd' 2>/dev/null; }
if [ -z "$windows" ]; then
  python=/usr/bin/python3
  other=$(command -v python3 || true)
  if [ -n "$other" ] && ! has_zstd "$python" && has_zstd "$other"; then python=$other; fi
  bash_exe= duo_windows= python_windows=
else
  # Microsoft Store python aliases are not real Python installations: has_zstd rejects them.
  python=
  for candidate in $(command -v python3 python || true) \
      "$(cygpath -u "$LOCALAPPDATA")"/Programs/Python/Python3*/python.exe \
      "$(cygpath -u "$PROGRAMFILES")"/Python3*/python.exe; do
    if has_zstd "$candidate"; then python=$candidate; fi
  done
  [ -n "$python" ] || stop "Python 3.14 or later not found: winget install Python.Python.3.14"
  # Codex runs commands with PowerShell: it calls claude-safe through Git's bash.exe.
  bash_exe="$(cygpath -w /)bin\\bash.exe"
  [ -f "$(cygpath -u "$bash_exe")" ] || stop "Git for Windows bash.exe not found."
  duo_windows=$(cygpath -m "$duo") python_windows=$(cygpath -w "$python")
fi

# Paths must arrive unchanged: Git Bash would convert paths such as /c/...
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
backups = os.path.join(home, '.local/state/duo/backups', f'{stamp}-{os.getpid()}')
start, end = '<!-- duo:start -->', '<!-- duo:end -->'
# Older versions used these markers; replace their block during migration.
legacy_start, legacy_end = '<!-- duo:debut -->', '<!-- duo:fin -->'


def read(path):
    if not os.path.exists(path):
        return ''
    with open(path, encoding='utf-8') as source:
        return source.read()


if windows:
    # Claude runs codex-safe with its Bash tool; Codex runs claude-safe with PowerShell.
    commands = {
        '__CODEX_SAFE__': f'{duo}/codex-safe',
        '__USAGE_CLAUDE__': f'{shlex.quote(python)} -X utf8 {duo}/usage',
        '__CLAUDE_SAFE__': f"& '{bash_exe}' '{duo_windows}/claude-safe'",
        '__USAGE_CODEX__': f"& '{python_windows}' -X utf8 '{duo_windows}/usage'",
        # Codex's sandbox runs under another Windows account that cannot see Python or the logs.
        '__USAGE_SANDBOX__': 'Run this outside the sandbox too (`require_escalated`): on Windows, the sandbox cannot see Python or the logs.',
    }
else:
    # usage runs /usr/bin/python3: name a newer Python explicitly.
    usage = f'{duo}/usage' if python == '/usr/bin/python3' else f'{shlex.quote(python)} {duo}/usage'
    commands = {
        '__CODEX_SAFE__': f'{duo}/codex-safe',
        '__USAGE_CLAUDE__': usage,
        '__CLAUDE_SAFE__': f'{duo}/claude-safe',
        '__USAGE_CODEX__': usage,
        '__USAGE_SANDBOX__': 'Keep this script inside the sandbox.',
    }


def instructions(template):
    text = read(template)
    # Keep Windows sections on Windows and remove them elsewhere.
    text = re.sub(r'<!-- windows -->\n(.*?)<!-- /windows -->\n', r'\1' if windows else '', text, flags=re.S)
    for name, command in commands.items():
        text = text.replace(name, command)
    return text.strip()


def with_block(template, path):
    block = f"{start}\n{instructions(template)}\n{end}\n"
    old = read(path)
    markers = [marker for marker in (start, end, legacy_start, legacy_end) if marker in old]
    if markers:
        opening, closing = (legacy_start, legacy_end) if legacy_start in markers else (start, end)
        if (set(markers) != {opening, closing} or old.count(opening) != 1
                or old.count(closing) != 1 or old.index(opening) > old.index(closing)):
            sys.exit(f'STOP: inconsistent duo markers in {path}. Nothing was changed.')
        before, rest = old.split(opening, 1)
        return before + block + rest.split(closing, 1)[1].lstrip('\n')
    return old.rstrip('\n') + '\n\n' + block if old.strip() else block


def with_rules(path):
    text = read(path)
    try:
        settings = json.loads(text) if text.strip() else {}
    except ValueError:
        sys.exit(f'STOP: {path} is not valid JSON. Nothing was changed.')
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
        print(f'Unchanged: {path}')
        return
    # Keep symbolic links in place: change their target file.
    target = os.path.realpath(path)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    # Create temporary files with mode 0600: they may contain private settings.
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
    print(f'Updated: {path}')


# Compute everything before the first write, and replace each file atomically.
# If a write fails, files already replaced stay valid: just run the installer again.
claude_md = os.path.join(home, '.claude/CLAUDE.md')
agents_md = os.path.join(home, '.codex/AGENTS.md')
settings_json = os.path.join(home, '.claude/settings.json')
if same_file(claude_md, agents_md):
    sys.exit('STOP: ~/.claude/CLAUDE.md and ~/.codex/AGENTS.md point to the same file. Nothing was changed.')
changes = [
    (claude_md, with_block('instructions/claude.md', claude_md)),
    (agents_md, with_block('instructions/codex.md', agents_md)),
    (settings_json, with_rules(settings_json)),
]
for path, text in changes:
    save(path, text)
# Without newline, Python would write CRLF endings on Windows, which sh cannot read.
with open('paths.sh', 'w', encoding='utf-8', newline='\n') as paths:
    paths.write(f'CODEX={shlex.quote(codex)}\nCLAUDE={shlex.quote(claude)}\nPYTHON={shlex.quote(python)}\n')
# Remove the old generated file so it does not become an untracked file.
if os.path.exists('chemins.sh'):
    os.unlink('chemins.sh')
EOF

echo "Installed. Open a new claude or codex session to load the instructions."
"$duo/codex-safe" check || stop "duo will refuse calls until this issue is resolved."
