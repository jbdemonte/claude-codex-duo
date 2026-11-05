# Fonctions partagées par codex-safe et claude-safe.

stop() { echo "ARRÊT : $1" >&2; exit 1; }

# chemins.sh est créé par install.sh avec les emplacements de claude et de codex.
[ -r "$(dirname "$0")/chemins.sh" ] || stop "lance d'abord ./install.sh."
. "$(dirname "$0")/chemins.sh"

# Aucune clé API ni adresse de fournisseur ne doit atteindre les agents.
# DUO_ACTIF signale aux agents appelés qu'ils travaillent déjà pour un collègue.
safe_env() {
  env -u OPENAI_API_KEY -u CODEX_API_KEY -u OPENAI_BASE_URL -u OPENAI_ORG_ID \
      -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_BASE_URL \
      DUO_ACTIF=1 "$@"
}

# Sans ce contrôle, deux agents pourraient s'appeler sans fin et vider le quota.
refuse_nested() {
  [ -z "${DUO_ACTIF:-}" ] || stop "un agent appelé par son collègue ne peut pas le rappeler."
}

check_codex() {
  /usr/bin/python3 - 2>/dev/null <<'EOF' || stop "Codex doit utiliser le login ChatGPT, sans clé API."
import json, os, sys
auth = json.load(open(os.path.expanduser('~/.codex/auth.json')))
sys.exit(0 if auth.get('auth_mode') == 'chatgpt' and not auth.get('OPENAI_API_KEY') else 1)
EOF
}

check_claude() {
  safe_env "$CLAUDE" auth status --json 2>/dev/null | /usr/bin/python3 -c '
import json, sys
auth = json.load(sys.stdin)
sys.exit(0 if auth.get("loggedIn") and auth.get("authMethod") == "claude.ai" else 1)
' || stop "login claude.ai introuvable ou impossible à vérifier, par exemple depuis un sandbox."
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
