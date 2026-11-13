# Functions shared by codex-safe and claude-safe.

stop() { echo "STOP: $1" >&2; exit 1; }

# install.sh creates paths.sh with the locations of claude, codex, and Python.
[ -r "$(dirname "$0")/paths.sh" ] || stop "run ./install.sh again."
. "$(dirname "$0")/paths.sh"
[ -n "${PYTHON:-}" ] || stop "run ./install.sh again."

# On Windows, Codex runs these scripts from PowerShell: Git Bash tools must come
# before Windows tools, which include a different find.
case $(uname) in
  MINGW*|MSYS*) windows=1 PATH=/usr/bin:$PATH ;;
  *) windows= ;;
esac

# Windows ignores case in variable names, but bash does not: to Codex, codex_home
# means CODEX_HOME. List existing variables with one of these names in a different case.
# Use awk: grep -i fails with multiple patterns in Git for Windows.
variants() {
  [ -n "$windows" ] || return 0
  env -0 | tr '\n\0' ' \n' | sed 's/=.*//' | awk -v names="$*" '
    BEGIN { split(names, list, " "); for (i in list) wanted[list[i]] = 1 }
    (toupper($0) in wanted) && !($0 in wanted)'
}

# The checks read ~/.codex and ~/.claude: a different folder would bypass them.
[ -z "${CLAUDE_CONFIG_DIR:-}${CODEX_HOME:-}$(variants CLAUDE_CONFIG_DIR CODEX_HOME)" ] ||
  stop "duo does not support CLAUDE_CONFIG_DIR or CODEX_HOME."

# The model must be a single word so it cannot add options to the command.
case ${DUO_MODEL:-} in
  -*|*[!A-Za-z0-9._:-]*) stop "invalid DUO_MODEL: expected a single model name." ;;
esac

# No API key or provider address may reach the agents.
# DUO_ACTIVE tells called agents they are already working for a colleague.
# CODEX_THREAD_ID would make usage mistake Claude for the Codex session that called it.
# DUO_IGNORE_QUOTA is only for the check, which receives it separately.
removed='OPENAI_API_KEY CODEX_API_KEY OPENAI_BASE_URL OPENAI_ORG_ID
  ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_PROFILE CODEX_THREAD_ID DUO_MESSAGE DUO_IGNORE_QUOTA'
safe_env() {
  # shellcheck disable=SC2046,SC2086
  env $(for name in $removed $(variants $removed); do echo "-u $name"; done) DUO_ACTIVE=1 "$@"
}

# Without this check, two agents could call each other endlessly and drain the quota.
refuse_nested() {
  [ -z "${DUO_ACTIVE:-}" ] || stop "an agent called by its colleague cannot call it back."
}

# -X utf8: otherwise Python would read and write in the local encoding on Windows.
run_python() {
  "$PYTHON" -I -X utf8 "$@"
}

# check asks the Codex server for the current quota, without API keys, just like agent calls.
check_codex() {
  safe_env DUO_IGNORE_QUOTA="${DUO_IGNORE_QUOTA:-}" "$PYTHON" -I -X utf8 "$(dirname "$0")/check" codex "$(shown "$CODEX")" ||
    exit 1
}

check_claude() {
  safe_env "$CLAUDE" auth status --json 2>/dev/null | run_python -c '
import json, os, sys
auth = json.loads(sys.stdin.buffer.read())
folder = os.path.normcase(os.path.normpath(auth.get("configDirectory") or ""))
ok = (auth.get("loggedIn") and auth.get("authMethod") == "claude.ai" and auth.get("apiProvider") == "firstParty"
      and folder == os.path.normcase(os.path.join(os.path.expanduser("~"), ".claude")))
sys.exit(0 if ok else 1)
' || stop "claude.ai login not found or cannot be checked, for example from a sandbox."
  run_python "$(dirname "$0")/check" claude || exit 1
}

# The message is the second argument. From PowerShell, use DUO_MESSAGE instead:
# PowerShell 5.1 splits arguments that contain quotes.
# Then pass it to the agent from a file on standard input.
message_file() {
  if [ $# -eq 2 ]; then text=$2
  elif [ $# -eq 1 ] && [ -n "${DUO_MESSAGE:-}" ]; then text=$DUO_MESSAGE
  else stop "usage: $(basename "$0") $1 \"message\", or the message in DUO_MESSAGE"
  fi
  file=$(temporary duo-message)
  printf '%s\n' "$text" >"$file"
  echo "$file"
}

temporary() {
  mktemp "${TMPDIR:-/tmp}/$1.XXXXXX"
}

# On Windows, a path that PowerShell can also read.
shown() {
  cygpath -w "$1" 2>/dev/null || echo "$1"
}

# One conversation per project and agent, forgotten after 12 hours.
memory_file() {
  # pwd -W gives C:/..., like git and usage on Windows.
  root=$(git rev-parse --show-toplevel 2>/dev/null || pwd -W 2>/dev/null || pwd)
  if command -v sha256sum >/dev/null; then sum=sha256sum; else sum='/usr/bin/shasum -a 256'; fi
  key=$(printf %s "$root" | $sum | cut -c1-16)
  mkdir -p "$HOME/.local/state/duo"
  echo "$HOME/.local/state/duo/$key.$1"
}

recent_session() {
  file=$(memory_file "$1")
  if [ -n "$(find "$file" -mmin -720 2>/dev/null)" ]; then cat "$file"; fi
}
