# Fonctions partagées par codex-safe et claude-safe.

stop() { echo "ARRÊT : $1" >&2; exit 1; }

# chemins.sh est créé par install.sh avec les emplacements de claude et de codex.
[ -r "$(dirname "$0")/chemins.sh" ] || stop "lance d'abord ./install.sh."
. "$(dirname "$0")/chemins.sh"

# Les contrôles lisent ~/.codex et ~/.claude : un autre dossier leur échapperait.
[ -z "${CLAUDE_CONFIG_DIR:-}${CODEX_HOME:-}" ] || stop "duo ne gère pas CLAUDE_CONFIG_DIR ni CODEX_HOME."

# Le modèle doit rester un seul mot : il ne peut pas ajouter d'options à la commande.
case ${DUO_MODEL:-} in
  -*|*[!A-Za-z0-9._:-]*) stop "DUO_MODEL invalide : un nom de modèle seul est attendu." ;;
esac

# Aucune clé API ni adresse de fournisseur ne doit atteindre les agents.
# DUO_ACTIF signale aux agents appelés qu'ils travaillent déjà pour un collègue.
# CODEX_THREAD_ID ferait passer Claude pour la session de Codex qui l'a appelé dans conso.
safe_env() {
  env -u OPENAI_API_KEY -u CODEX_API_KEY -u OPENAI_BASE_URL -u OPENAI_ORG_ID \
      -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_BASE_URL -u ANTHROPIC_PROFILE \
      -u CODEX_THREAD_ID DUO_ACTIF=1 "$@"
}

# Sans ce contrôle, deux agents pourraient s'appeler sans fin et vider le quota.
refuse_nested() {
  [ -z "${DUO_ACTIF:-}" ] || stop "un agent appelé par son collègue ne peut pas le rappeler."
}

check_codex() {
  /usr/bin/python3 -I "$(dirname "$0")/controle" codex || exit 1
}

check_claude() {
  safe_env "$CLAUDE" auth status --json 2>/dev/null | /usr/bin/python3 -I -c '
import json, os, sys
auth = json.load(sys.stdin)
ok = (auth.get("loggedIn") and auth.get("authMethod") == "claude.ai" and auth.get("apiProvider") == "firstParty"
      and auth.get("configDirectory") == os.path.expanduser("~/.claude"))
sys.exit(0 if ok else 1)
' || stop "login claude.ai introuvable ou impossible à vérifier, par exemple depuis un sandbox."
  /usr/bin/python3 -I "$(dirname "$0")/controle" claude || exit 1
}

# Un fil de conversation par projet et par agent, oublié après 12 heures.
memory_file() {
  root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  key=$(printf %s "$root" | /usr/bin/shasum -a 256 | cut -c1-16)
  mkdir -p "$HOME/.local/state/duo"
  echo "$HOME/.local/state/duo/$key.$1"
}

recent_session() {
  file=$(memory_file "$1")
  if [ -n "$(find "$file" -mmin -720 2>/dev/null)" ]; then cat "$file"; fi
}
