# Fonctions partagées par codex-safe et claude-safe.

stop() { echo "ARRÊT : $1" >&2; exit 1; }

# chemins.sh est créé par install.sh avec les emplacements de claude, de codex et de Python.
[ -r "$(dirname "$0")/chemins.sh" ] || stop "lance d'abord ./install.sh."
. "$(dirname "$0")/chemins.sh"
[ -n "${PYTHON:-}" ] || stop "relance ./install.sh."

# Sous Windows, Codex lance ces scripts depuis PowerShell : les outils de Git Bash doivent passer
# devant ceux de Windows, qui a son propre find.
case $(uname) in
  MINGW*|MSYS*) windows=1 PATH=/usr/bin:$PATH ;;
  *) windows= ;;
esac

# Windows ne distingue pas la casse des noms de variables, bash si : pour Codex, codex_home
# vaut CODEX_HOME. Donne les variables présentes qui portent l'un de ces noms dans une autre casse.
# awk plutôt que grep -i, qui plante avec plusieurs motifs dans le grep de Git for Windows.
variants() {
  [ -n "$windows" ] || return 0
  env -0 | tr '\n\0' ' \n' | sed 's/=.*//' | awk -v names="$*" '
    BEGIN { split(names, list, " "); for (i in list) wanted[list[i]] = 1 }
    (toupper($0) in wanted) && !($0 in wanted)'
}

# Les contrôles lisent ~/.codex et ~/.claude : un autre dossier leur échapperait.
[ -z "${CLAUDE_CONFIG_DIR:-}${CODEX_HOME:-}$(variants CLAUDE_CONFIG_DIR CODEX_HOME)" ] ||
  stop "duo ne gère pas CLAUDE_CONFIG_DIR ni CODEX_HOME."

# Le modèle doit rester un seul mot : il ne peut pas ajouter d'options à la commande.
case ${DUO_MODEL:-} in
  -*|*[!A-Za-z0-9._:-]*) stop "DUO_MODEL invalide : un nom de modèle seul est attendu." ;;
esac

# Aucune clé API ni adresse de fournisseur ne doit atteindre les agents.
# DUO_ACTIF signale aux agents appelés qu'ils travaillent déjà pour un collègue.
# CODEX_THREAD_ID ferait passer Claude pour la session de Codex qui l'a appelé dans conso.
removed='OPENAI_API_KEY CODEX_API_KEY OPENAI_BASE_URL OPENAI_ORG_ID
  ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_PROFILE CODEX_THREAD_ID DUO_MESSAGE'
safe_env() {
  # shellcheck disable=SC2046,SC2086
  env $(for name in $removed $(variants $removed); do echo "-u $name"; done) DUO_ACTIF=1 "$@"
}

# Sans ce contrôle, deux agents pourraient s'appeler sans fin et vider le quota.
refuse_nested() {
  [ -z "${DUO_ACTIF:-}" ] || stop "un agent appelé par son collègue ne peut pas le rappeler."
}

# -X utf8 : sous Windows, Python lirait et écrirait sinon dans l'encodage local.
run_python() {
  "$PYTHON" -I -X utf8 "$@"
}

check_codex() {
  run_python "$(dirname "$0")/controle" codex || exit 1
}

check_claude() {
  safe_env "$CLAUDE" auth status --json 2>/dev/null | run_python -c '
import json, os, sys
auth = json.loads(sys.stdin.buffer.read())
folder = os.path.normcase(os.path.normpath(auth.get("configDirectory") or ""))
ok = (auth.get("loggedIn") and auth.get("authMethod") == "claude.ai" and auth.get("apiProvider") == "firstParty"
      and folder == os.path.normcase(os.path.join(os.path.expanduser("~"), ".claude")))
sys.exit(0 if ok else 1)
' || stop "login claude.ai introuvable ou impossible à vérifier, par exemple depuis un sandbox."
  run_python "$(dirname "$0")/controle" claude || exit 1
}

# Le message est le deuxième argument. Depuis PowerShell, il passe plutôt par DUO_MESSAGE :
# PowerShell 5.1 coupe les arguments qui contiennent des guillemets.
# Il est ensuite donné à l'agent par un fichier, sur son entrée standard.
message_file() {
  if [ $# -eq 2 ]; then text=$2
  elif [ $# -eq 1 ] && [ -n "${DUO_MESSAGE:-}" ]; then text=$DUO_MESSAGE
  else stop "usage : $(basename "$0") $1 \"message\", ou le message dans DUO_MESSAGE"
  fi
  file=$(temporary duo-message)
  printf '%s\n' "$text" >"$file"
  echo "$file"
}

temporary() {
  mktemp "${TMPDIR:-/tmp}/$1.XXXXXX"
}

# Sous Windows, un chemin lisible aussi depuis PowerShell.
shown() {
  cygpath -w "$1" 2>/dev/null || echo "$1"
}

# Un fil de conversation par projet et par agent, oublié après 12 heures.
memory_file() {
  # pwd -W donne C:/..., comme git et comme conso sous Windows.
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
