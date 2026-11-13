#!/bin/sh
# Test duo in a fake home folder, with fake claude and codex.
set -u
# Python uses USERPROFILE on Windows, so a fake HOME would not protect real settings.
[ "$(uname)" = Darwin ] || { echo "STOP: tests require macOS." >&2; exit 1; }
base=$(cd "$(dirname "$0")/.." && pwd -P) || exit 1
T=$(mktemp -d "${TMPDIR:-/tmp}/duo-tests.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
real_path=$PATH
pass=0 fail=0
cleanup() {
  result=$?
  if [ "$result" -eq 0 ] && [ "$fail" -eq 0 ]; then
    rm -rf "$T"
  else
    echo "Test files kept at: $T"
  fi
}
trap cleanup 0
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$T/home/.claude" "$T/home/.codex" "$T/bin" "$T/project" "$T/tmp"
cp -R "$base" "$T/duo" || exit 1
rm -f "$T/duo/paths.sh" "$T/duo/chemins.sh"
duo=$T/duo

cat >"$T/bin/codex" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >>"$HOME/codex-args"
env >>"$HOME/codex-env"
# Fake server: return the quota from fake-live.json, or refuse if missing.
if [ "$5" = app-server ]; then
  case ${FAKE_SERVER:-} in
    silent) echo "$$" >"$HOME/silent-pid"; exec sleep 60 ;;
    launcher) sleep 61 & echo "$!" >"$HOME/child-pid"; wait; exit 0 ;;
  esac
  while IFS= read -r line; do
    case $line in
      *'"initialize"'*)
        echo '{"method":"note","params":{}}'
        echo 'not json'
        echo '{"id":1,"method":"server/request","params":{}}'
        echo '{"id":0,"result":{}}' ;;
      *'account/rateLimits/read'*)
        if [ -r "$HOME/fake-live.json" ]; then printf '{"id":1,"result":%s}\n' "$(cat "$HOME/fake-live.json")"
        else echo '{"id":1,"error":{"code":-32600,"message":"refused"}}'; fi ;;
    esac
  done
  exit 0
fi
out=
prev=
for arg in "$@"; do
  [ "$prev" = -o ] && out=$arg
  prev=$arg
done
if [ -n "${FAKE_FAIL:-}" ]; then
  echo '{"type":"thread.started","thread_id":"failed-thread"}'
  exit 3
fi
echo '{"type":"thread.started","thread_id":"good-thread"}'
echo 'session id: review-1'
[ -n "$out" ] && echo codex-answer >"$out"
exit 0
EOF
cat >"$T/bin/claude" <<'EOF'
#!/bin/sh
if [ "$1 $2" = "auth status" ]; then
  cat "$HOME/fake-auth.json"
  exit 0
fi
printf '%s\n' "$@" >>"$HOME/claude-args"
env >>"$HOME/claude-env"
case "${FAKE_FAIL:-}" in
  code) echo '{"session_id":"claude-failed-code","is_error":true,"result":"quota"}'; exit 1 ;;
  error) echo '{"session_id":"claude-failed-error","is_error":true,"result":"quota"}'; exit 0 ;;
  empty) echo 'crash without JSON'; exit 2 ;;
esac
echo '{"session_id":"claude-ok","is_error":false,"result":"claude-answer"}'
EOF
chmod +x "$T/bin/codex" "$T/bin/claude"

run() { HOME="$T/home" TMPDIR="$T/tmp" PATH="$T/bin:$real_path" "$@"; }

quota() {
  mkdir -p "$T/home/.codex/sessions/2026/11/05"
  printf '{"timestamp":"t","payload":{"type":"token_count","rate_limits":%s}}\n' "$1" \
    >"$T/home/.codex/sessions/2026/11/05/rollout-test.jsonl"
}
future=$(($(date +%s) + 3600))
past=$(($(date +%s) - 3600))
fine() {
  quota "{\"primary\":{\"used_percent\":16.0,\"resets_at\":$future},\"secondary\":null}"
  : >"$T/home/.codex/config.toml"
  echo '{"auth_mode":"chatgpt","OPENAI_API_KEY":null}' >"$T/home/.codex/auth.json"
  echo '{"oauthAccount":{"hasExtraUsageEnabled":false}}' >"$T/home/.claude.json"
  echo "{\"loggedIn\":true,\"authMethod\":\"claude.ai\",\"apiProvider\":\"firstParty\",\"configDirectory\":\"$T/home/.claude\"}" >"$T/home/fake-auth.json"
  echo '{}' >"$T/home/.claude/settings.json"
  rm -rf "$T/project/.claude" "$T/home/fake-live.json"
}
live() {
  echo "$1" >"$T/home/fake-live.json"
}
bucket() {
  echo "{\"limitId\":\"$1\",\"primary\":{\"usedPercent\":$2,\"windowDurationMins\":10080,\"resetsAt\":$3},\"secondary\":null,\"rateLimitReachedType\":${4:-null}}"
}

ok() {
  label=$1; shift
  if out=$( (cd "$T/project" && "$@") 2>&1 ); then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL (expected success): $label : $out"; fi
}
ko() {
  label=$1; want=$2; shift 2
  if out=$( (cd "$T/project" && "$@") 2>&1 ); then
    fail=$((fail + 1)); echo "FAIL (expected refusal): $label"
  elif ! printf %s "$out" | grep -q "$want"; then
    fail=$((fail + 1)); echo "FAIL (wrong message): $label : $out"
  elif printf %s "$out" | grep -q 'SECRET'; then
    fail=$((fail + 1)); echo "FAIL (value leaked): $label : $out"
  else
    pass=$((pass + 1))
  fi
}
check() { run "$duo/codex-safe" check; }
yes_if() {
  label=$1; shift
  if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $label"; fi
}

(cd "$T/project" && git init -q . && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m start)

# Missing current paths must refuse even if the old generated file exists.
ko "missing paths" "run ./install.sh again" run "$duo/codex-safe" check
printf 'legacy paths\n' >"$duo/chemins.sh"
ko "legacy paths alone" "run ./install.sh again" run "$duo/claude-safe" read question

# Installation
fine
ok "fresh install" run "$duo/install.sh"
yes_if "current paths created" test -r "$duo/paths.sh"
yes_if "legacy paths removed" test ! -e "$duo/chemins.sh"
yes_if "block installed" grep -q 'duo:start' "$T/home/.claude/CLAUDE.md"
yes_if "deny rule" grep -q 'Bash(codex \*)' "$T/home/.claude/settings.json"
ok "rerun" run "$duo/install.sh"
yes_if "no temporary files" test -z "$(find "$T/home" -name '*.duo-*')"

# Migrate legacy instruction blocks while keeping surrounding text.
for file in "$T/home/.claude/CLAUDE.md" "$T/home/.codex/AGENTS.md"; do
  printf 'Personal header\n<!-- duo:debut -->\nOld instructions\n<!-- duo:fin -->\nPersonal footer\n' >"$file"
done
cp "$T/home/.claude/settings.json" "$T/settings-before"
ok "migrate legacy markers" run "$duo/install.sh"
for file in "$T/home/.claude/CLAUDE.md" "$T/home/.codex/AGENTS.md"; do
  yes_if "one current block" test "$(grep -c '^<!-- duo:start -->$' "$file")" = 1
  yes_if "one closing marker" test "$(grep -c '^<!-- duo:end -->$' "$file")" = 1
  yes_if "legacy markers removed" test -z "$(grep -E 'duo:(debut|fin)' "$file")"
  yes_if "header preserved" test "$(head -n 1 "$file")" = 'Personal header'
  yes_if "footer preserved" test "$(tail -n 1 "$file")" = 'Personal footer'
done
yes_if "settings unchanged" cmp -s "$T/settings-before" "$T/home/.claude/settings.json"
yes_if "backups created" test -n "$(find "$T/home/.local/state/duo/backups" -name CLAUDE.md)"

# All inputs must remain unchanged when any markers are mixed or inconsistent.
cp "$T/home/.codex/AGENTS.md" "$T/agents-before"
for markers in \
  '<!-- duo:debut -->|<!-- duo:fin -->|<!-- duo:start -->|<!-- duo:end -->' \
  '<!-- duo:start -->' '<!-- duo:end -->' \
  '<!-- duo:end -->|<!-- duo:start -->' \
  '<!-- duo:start -->|<!-- duo:end -->|<!-- duo:start -->|<!-- duo:end -->' \
  '<!-- duo:debut -->' '<!-- duo:fin -->' \
  '<!-- duo:fin -->|<!-- duo:debut -->' \
  '<!-- duo:debut -->|<!-- duo:fin -->|<!-- duo:debut -->|<!-- duo:fin -->'; do
  printf '%s\n' "$markers" | tr '|' '\n' >"$T/home/.codex/AGENTS.md"
  printf 'legacy paths\n' >"$duo/chemins.sh"
  before=$(cksum "$T/home/.claude/CLAUDE.md" "$T/home/.codex/AGENTS.md" "$T/home/.claude/settings.json" "$duo/paths.sh" "$duo/chemins.sh")
  ko "inconsistent markers" "Nothing was changed" run "$duo/install.sh"
  after=$(cksum "$T/home/.claude/CLAUDE.md" "$T/home/.codex/AGENTS.md" "$T/home/.claude/settings.json" "$duo/paths.sh" "$duo/chemins.sh")
  yes_if "no changes after marker refusal" test "$before" = "$after"
done
cp "$T/agents-before" "$T/home/.codex/AGENTS.md"
rm "$duo/chemins.sh"

# Preserve linked files and permissions
mkdir "$T/dotfiles"
mv "$T/home/.claude/CLAUDE.md" "$T/dotfiles/CLAUDE.md"
ln -s "$T/dotfiles/CLAUDE.md" "$T/home/.claude/CLAUDE.md"
echo "personal line" >>"$T/dotfiles/CLAUDE.md"
chmod 600 "$T/dotfiles/CLAUDE.md"
sed -i '' 's/Always use/Be sure to use/' "$T/dotfiles/CLAUDE.md"
ok "install through symlink" run "$duo/install.sh"
yes_if "symlink preserved" test -L "$T/home/.claude/CLAUDE.md"
yes_if "permissions preserved" test "$(stat -f %Lp "$T/dotfiles/CLAUDE.md")" = 600
yes_if "personal line preserved" grep -q 'personal line' "$T/dotfiles/CLAUDE.md"
yes_if "block restored" grep -q 'Always use' "$T/dotfiles/CLAUDE.md"

# The guard does not undo installation
echo '{"oauthAccount":{"hasExtraUsageEnabled":true}}' >"$T/home/.claude.json"
ko "install with guard" "duo will refuse" run "$duo/install.sh"
yes_if "paths.sh present" test -r "$duo/paths.sh"

# Basic checks
fine
ok "all checks pass" check
ok "forget" run "$duo/codex-safe" forget

# Old subcommands are not aliases.
ko "legacy codex command" "usage:" run "$duo/codex-safe" lire question
ko "legacy claude command" "usage:" run "$duo/claude-safe" lire question

# The fake Codex does not enforce shell policies: verify each command's arguments.
argument_pair() {
  awk -v option="$2" -v wanted="$3" 'previous == option && $0 == wanted { found = 1 } { previous = $0 } END { exit !found }' "$1"
}
policy() { argument_pair "$T/home/codex-args" -c "$1"; }
for command in exec resume review; do
  : >"$T/home/codex-args"
  if [ "$command" = review ]; then
    ok "policy review" run "$duo/codex-safe" review HEAD
  else
    ok "policy $command" run "$duo/codex-safe" read question
  fi
  case $command in
    exec) yes_if "read uses read-only sandbox" argument_pair "$T/home/codex-args" --sandbox read-only ;;
    resume) yes_if "resumed read uses read-only sandbox" policy 'sandbox_mode="read-only"' ;;
  esac
  yes_if "command $command ran" grep -qx "$command" "$T/home/codex-args"
  yes_if "active flag in $command" policy 'shell_environment_policy.set.DUO_ACTIVE="1"'
  yes_if "environment policy in $command" policy 'shell_environment_policy.include_only=[]'
done
ok "forget after policy checks" run "$duo/codex-safe" forget

# Code mode must grant editing permissions on both fresh and resumed calls.
: >"$T/home/codex-args"
ok "codex code" run "$duo/codex-safe" code task
yes_if "code uses workspace-write sandbox" argument_pair "$T/home/codex-args" --sandbox workspace-write
: >"$T/home/codex-args"
ok "codex code resume" run "$duo/codex-safe" code task
yes_if "code resumed" grep -qx resume "$T/home/codex-args"
yes_if "resumed code uses workspace-write sandbox" policy 'sandbox_mode="workspace-write"'
ok "forget after code checks" run "$duo/codex-safe" forget
: >"$T/home/claude-args"
ok "claude read permissions" run "$duo/claude-safe" read question
yes_if "claude read permission mode" argument_pair "$T/home/claude-args" --permission-mode default
yes_if "claude read blocks edits" argument_pair "$T/home/claude-args" --disallowedTools 'Write,Edit,NotebookEdit'
: >"$T/home/claude-args"
ok "claude code" run "$duo/claude-safe" code task
yes_if "claude code accepts edits" argument_pair "$T/home/claude-args" --permission-mode acceptEdits
yes_if "claude code allows Bash" argument_pair "$T/home/claude-args" --allowedTools Bash
yes_if "claude code blocks Git mutations" argument_pair "$T/home/claude-args" --disallowedTools 'Bash(git push *),Bash(git merge *),Bash(git commit *),Bash(git rebase *),Bash(git reset *),Bash(git -C *),Bash(git -c *)'
ok "forget after claude mode checks" run "$duo/claude-safe" forget

# DUO_MODEL
ok "simple model" run env DUO_MODEL=gpt-6-astra "$duo/codex-safe" read question
yes_if "model passed" grep -qx 'gpt-6-astra' "$T/home/codex-args"
: >"$T/home/codex-args"
ko "injection" "invalid DUO_MODEL" run env 'DUO_MODEL=model -c model_provider="paid"' "$duo/codex-safe" read question
ko "injection review" "invalid DUO_MODEL" run env 'DUO_MODEL=x -c a=b' "$duo/codex-safe" review HEAD
ko "option alone" "invalid DUO_MODEL" run env 'DUO_MODEL=-c' "$duo/codex-safe" read question
ko "injection claude" "invalid DUO_MODEL" run env 'DUO_MODEL=a b' "$duo/claude-safe" read question
yes_if "codex not started" test ! -s "$T/home/codex-args"
ok "forget" run "$duo/codex-safe" forget

# Settings folders
ko "CODEX_HOME" "CODEX_HOME" run env CODEX_HOME=/tmp/x "$duo/codex-safe" read question
ko "CLAUDE_CONFIG_DIR" "CLAUDE_CONFIG_DIR" run env CLAUDE_CONFIG_DIR=/tmp/x "$duo/claude-safe" read question

# Codex destinations
for line in 'openai_base_url = "https://SECRET"' 'chatgpt_base_url = "https://SECRET"' 'profile = "SECRET"' \
            'model_provider = "SECRET"' '  model_provider="SECRET" # note' 'profiles.x.model_provider = "SECRET"'; do
  fine
  echo "$line" >"$T/home/.codex/config.toml"
  ko "config : $line" "outside the subscription" check
done
fine
printf '# openai_base_url = "x"\nmodel_provider = "openai" # comment\n[model_providers.openai_like]\nname = "x"\n' >"$T/home/.codex/config.toml"
ok "config without redirect" check

# Claude destinations
fine
echo '{"env":{"ANTHROPIC_BASE_URL":"https://SECRET"}}' >"$T/home/.claude/settings.json"
ko "ANTHROPIC_BASE_URL" "ANTHROPIC_BASE_URL" check
echo '{"env":{"ANTHROPIC_BASE_URL":""}}' >"$T/home/.claude/settings.json"
ok "empty variable" check
echo '{"env":{"ANTHROPIC_MODEL":"opus","MY_API_KEY":"x"}}' >"$T/home/.claude/settings.json"
ok "other variables" check
echo '{"apiKeyHelper":"/SECRET"}' >"$T/home/.claude/settings.json"
ko "apiKeyHelper" "apiKeyHelper" check
echo '{"env":{"CLAUDE_CODE_USE_BEDROCK":"1"}}' >"$T/home/.claude/settings.json"
ko "bedrock setting" "CLAUDE_CODE_USE_BEDROCK" check
fine
mkdir "$T/project/.claude"
echo '{"env":{"ANTHROPIC_AUTH_TOKEN":"SECRET"}}' >"$T/project/.claude/settings.local.json"
ko "project setting" "ANTHROPIC_AUTH_TOKEN" check
echo 'not json' >"$T/project/.claude/settings.json"
rm "$T/project/.claude/settings.local.json"
ko "invalid JSON" "cannot check" check
fine
echo '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"bedrock"}' >"$T/home/fake-auth.json"
ko "bedrock provider" "claude.ai login" check

# Codex guard
fine
quota "{\"primary\":{\"used_percent\":94.9,\"resets_at\":$future}}"
ok "quota 94.9" check
quota "{\"primary\":{\"used_percent\":95.0,\"resets_at\":$future}}"
ko "quota 95" "Codex quota at 95" check
ko "quota 95 read" "Codex quota at 95" run "$duo/codex-safe" read question
ko "quota 95 review" "Codex quota at 95" run "$duo/codex-safe" review HEAD
ko "legacy quota override ignored" "Codex quota at 95" run env DUO_SANS_QUOTA=1 "$duo/codex-safe" check
ko "override documented" "DUO_IGNORE_QUOTA=1" check
: >"$T/home/codex-env" ; : >"$T/home/claude-env"
ok "guard disabled" run env DUO_IGNORE_QUOTA=1 "$duo/codex-safe" read question
yes_if "variable removed from Codex" sh -c "! grep -q DUO_IGNORE_QUOTA '$T/home/codex-env'"
yes_if "Codex started" grep -q '^DUO_ACTIVE=1' "$T/home/codex-env"
ok "claude with variable" run env DUO_IGNORE_QUOTA=1 "$duo/claude-safe" read question
yes_if "variable removed from Claude" sh -c "! grep -q DUO_IGNORE_QUOTA '$T/home/claude-env'"
out=$( (cd "$T/project" && run env DUO_IGNORE_QUOTA=1 "$duo/codex-safe" check) 2>&1 )
yes_if "warning" sh -c "printf %s \"\$1\" | grep -q 'paid credits'" x "$out"
ko "other value" "Codex quota at 95" run env DUO_IGNORE_QUOTA=yes "$duo/codex-safe" check
echo '{"auth_mode":"apikey"}' >"$T/home/.codex/auth.json"
ko "guard disabled, API key" "ChatGPT login" run env DUO_IGNORE_QUOTA=1 "$duo/codex-safe" check
fine
echo 'openai_base_url = "https://SECRET"' >"$T/home/.codex/config.toml"
quota "{\"primary\":{\"used_percent\":95.0,\"resets_at\":$future}}"
ko "guard disabled, destination" "outside the subscription" run env DUO_IGNORE_QUOTA=1 "$duo/codex-safe" check
fine
quota "{\"primary\":{\"used_percent\":99.0,\"resets_at\":$past}}"
ok "quota reset" check
quota "{\"primary\":{\"used_percent\":10,\"resets_at\":$future},\"secondary\":{\"used_percent\":96,\"resets_at\":$future}}"
ko "second window" "Codex quota at 96" check
quota "{\"primary\":{\"used_percent\":99}}"
ko "changed format" "cannot check" check
quota "{\"primary\":{},\"secondary\":{\"used_percent\":10,\"resets_at\":$future}}"
ko "empty window" "cannot check" check
quota 'null'
ko "empty reading" "unknown Codex quota" check
rm "$T/home/.codex/sessions/2026/11/05/rollout-test.jsonl"
ko "no log" "unknown Codex quota" check

# Current quota from the Codex server
fine
quota "{\"primary\":{\"used_percent\":100.0,\"resets_at\":$future}}"
live "{\"rateLimits\":$(bucket codex 0 $future)}"
ok "early reset" check
out=$( (cd "$T/project" && check) 2>&1 )
yes_if "no note" test -z "$(printf %s "$out" | grep Note)"
live "{\"rateLimits\":$(bucket codex 0 null)}"
ok "window not started" check
quota "{\"primary\":{\"used_percent\":10.0,\"resets_at\":$future}}"
live "{\"rateLimits\":$(bucket codex 94.9 $future)}"
ok "live 94.9" check
live "{\"rateLimits\":$(bucket codex 95 $future)}"
ko "live 95" "Codex quota at 95%; further" check
ko "reset date format" "Next reset: $(date -r "$future" '+%Y-%m-%d %H:%M')" check
ko "live 95 read" "Codex quota at 95" run "$duo/codex-safe" read question
live "{\"rateLimits\":$(bucket codex 95 null)}"
ko "live without date" "reset: unknown" check
live "{\"rateLimits\":$(bucket codex 95 $past)}"
ko "live, past date" "Codex quota at 95" check
live "{\"rateLimits\":{\"primary\":{},\"secondary\":$(bucket codex 10 $future | sed 's/.*"primary":\({[^}]*}\).*/\1/')}}"
ko "empty live window" "cannot check" check
live "{\"rateLimits\":$(bucket codex 10 $future),\"rateLimitsByLimitId\":{\"other\":{}}}"
ko "incomplete other limit" "cannot check" check
live "{\"rateLimits\":$(bucket codex 10 $future),\"rateLimitsByLimitId\":{\"other\":{\"limitId\":\"other\",\"primary\":null,\"secondary\":null}}}"
ok "other limit without window" check
live "{\"rateLimits\":null,\"rateLimitsByLimitId\":{\"other\":$(bucket other 10 $future)}}"
ko "missing main limit" "empty current Codex quota" check
live '{"rateLimits":{"limitId":"codex","primary":null,"secondary":null}}'
ko "main limit without window" "empty current Codex quota" check
live "{\"rateLimits\":$(bucket codex 10 $future),\"rateLimitsByLimitId\":{\"codex\":$(bucket codex 10 $future),\"other\":$(bucket other 96 $future)}}"
ko "other limit" "Codex quota at 96% (limit other)" check
live "{\"rateLimits\":$(bucket codex 10 $future '"usageLimitReached"')}"
ko "reached limit" "Codex reports a reached limit" check
live "{\"rateLimits\":{\"primary\":{\"usedPercent\":10}}}"
ko "changed live format" "cannot check" check
live "{\"rateLimits\":$(bucket codex '"10"' $future)}"
ko "percentage as text" "unreadable Codex quota" check
live '{"rateLimits":null}'
ko "empty live response" "empty current Codex quota" check
rm "$T/home/fake-live.json"
quota "{\"primary\":{\"used_percent\":100.0,\"resets_at\":$future}}"
ko "server refusal: logs" "Codex quota at 100" check
quota "{\"primary\":{\"used_percent\":16.0,\"resets_at\":$future}}"
out=$( (cd "$T/project" && check) 2>&1 )
yes_if "refusal note" sh -c "printf %s \"\$1\" | grep -q 'Codex refused the request'" x "$out"
: >"$T/home/codex-args" ; : >"$T/home/codex-env"
ok "server without API keys" run env OPENAI_API_KEY=SECRET CODEX_API_KEY=SECRET "$duo/codex-safe" check
yes_if "key removed from server" sh -c "! grep -q SECRET '$T/home/codex-env'"
yes_if "ChatGPT login forced" grep -qx 'forced_login_method="chatgpt"' "$T/home/codex-args"
yes_if "server started" grep -qx app-server "$T/home/codex-args"
start=$(date +%s)
out=$( (cd "$T/project" && run env FAKE_SERVER=silent "$duo/codex-safe" check) 2>&1 )
yes_if "silent server: logs" sh -c "printf %s \"\$1\" | grep -q 'no answer within 15 s'" x "$out"
yes_if "silent server stopped" test "$(($(date +%s) - start))" -lt 25
# Match only the PID started by this test, and treat pgrep errors as failures.
sleep_stopped() {
  pgrep -f "sleep $2" >"$T/sleep-processes"
  result=$?
  [ "$result" -eq 1 ] && return 0
  [ "$result" -eq 0 ] && ! grep -qx "$(cat "$1")" "$T/sleep-processes"
}
yes_if "no remaining server" sleep_stopped "$T/home/silent-pid" 60
ok "stuck launcher" run env FAKE_SERVER=launcher "$duo/codex-safe" check
yes_if "launcher descendant stopped" sleep_stopped "$T/home/child-pid" 61
mv "$T/bin/codex" "$T/bin/codex.real"
python=$(. "$duo/paths.sh"; echo "$PYTHON")
out=$( (cd "$T/project" && run "$python" -I "$duo/check" codex "$T/bin/codex") 2>&1 )
yes_if "missing codex: logs" sh -c "printf %s \"\$1\" | grep -q 'Codex cannot start'" x "$out"
mv "$T/bin/codex.real" "$T/bin/codex"

# Claude guard
fine
echo '{"oauthAccount":{"hasExtraUsageEnabled":true}}' >"$T/home/.claude.json"
ko "usage enabled" "extra usage" check
ko "usage enabled claude-safe" "extra usage" run "$duo/claude-safe" read question
ok "codex-safe still allowed" run "$duo/codex-safe" read question
echo '{"oauthAccount":{}}' >"$T/home/.claude.json"
ko "missing field" "extra usage" check
rm "$T/home/.claude.json"
ko "missing file" "cannot check" check
fine
ok "forget" run "$duo/codex-safe" forget
ok "forget" run "$duo/claude-safe" forget

# Login Codex
fine
echo '{"auth_mode":"apikey"}' >"$T/home/.codex/auth.json"
ko "API key login" "ChatGPT login" check
rm "$T/home/.codex/auth.json"
ko "missing login" "ChatGPT login" check
fine

state() { cat "$T/home/.local/state/duo/"*".$1" 2>/dev/null; }

# Keep failed calls
ko "codex failure" "Codex failed" run env FAKE_FAIL=1 "$duo/codex-safe" read question
yes_if "Codex thread kept" test "$(state codex)" = failed-thread
ok "forget" run "$duo/codex-safe" forget
ko "claude code 1" "Claude failed" run env FAKE_FAIL=code "$duo/claude-safe" read question
yes_if "session kept (code)" test "$(state claude)" = claude-failed-code
ok "forget" run "$duo/claude-safe" forget
ko "claude is_error" "Claude failed" run env FAKE_FAIL=error "$duo/claude-safe" read question
yes_if "session kept (is_error)" test "$(state claude)" = claude-failed-error
ok "forget" run "$duo/claude-safe" forget
ko "claude without JSON" "crash without JSON" run env FAKE_FAIL=empty "$duo/claude-safe" read question
ok "claude normal" run "$duo/claude-safe" read question
yes_if "normal session" test "$(state claude)" = claude-ok

# Codex's identifier does not reach Claude
: >"$T/home/claude-env"
ok "claude called by codex" run env CODEX_THREAD_ID=parent "$duo/claude-safe" read question
yes_if "CODEX_THREAD_ID removed" sh -c "! grep -q '^CODEX_THREAD_ID=' '$T/home/claude-env'"
yes_if "DUO_ACTIVE set" grep -q '^DUO_ACTIVE=1' "$T/home/claude-env"

# Expiration in usage and reviews
ok "codex normal" run "$duo/codex-safe" read question
memory=$(ls "$T/home/.local/state/duo/"*.codex)
out=$(cd "$T/project" && run env -u CODEX_THREAD_ID CLAUDE_CODE_SESSION_ID=none "$duo/usage")
yes_if "recent conversation counted" sh -c "printf %s '$out' | grep -q 'Codex, current conversation: unknown'"
touch -t "$(date -v-13H +%Y%m%d%H%M)" "$memory"
out=$(cd "$T/project" && run env -u CODEX_THREAD_ID CLAUDE_CODE_SESSION_ID=none "$duo/usage")
yes_if "expired conversation ignored" sh -c "printf %s '$out' | grep -q 'Codex, current conversation: not called'"
ok "review" run "$duo/codex-safe" review HEAD
reviews=$(ls "$T/home/.local/state/duo/"*.codex-reviews)
echo old-review >"$reviews"
touch -t "$(date -v-13H +%Y%m%d%H%M)" "$reviews"
ok "review after expiration" run "$duo/codex-safe" review HEAD
yes_if "old review forgotten" sh -c "! grep -q old-review '$reviews'"
yes_if "new review recorded" grep -q review-1 "$reviews"

# Usage output keeps English punctuation, including comma thousands separators.
mkdir -p "$T/home/.claude/projects/test"
cat >"$T/home/.claude/projects/test/format.jsonl" <<'EOF'
{"type":"assistant","message":{"id":"message-1","usage":{"input_tokens":1865321,"cache_read_input_tokens":46049828,"output_tokens":544899}}}
EOF
out=$(cd "$T/project" && run env -u CODEX_THREAD_ID CLAUDE_CODE_SESSION_ID=format "$duo/usage")
yes_if "English usage numbers" test "$(printf '%s\n' "$out" | head -n 1)" = 'Claude, current session: 47,915,149 read, including 46,049,828 cached, and 544,899 generated'
out=$(cd "$T/project" && run env -u CODEX_THREAD_ID -u CLAUDE_CODE_SESSION_ID "$duo/usage")
yes_if "unknown current session" test "$out" = 'Current session unknown.'

# Scripts do not load a json.py from the project
echo "open('$T/trap', 'w').write('x')" >"$T/project/json.py"
ok "trapped project" check
ok "trapped project claude" run "$duo/claude-safe" read question
yes_if "project module ignored" test ! -e "$T/trap"
rm "$T/project/json.py"

# Prevent nested calls
ko "nested codex" "cannot call it back" run env DUO_ACTIVE=1 "$duo/codex-safe" read question
ko "nested claude" "cannot call it back" run env DUO_ACTIVE=1 "$duo/claude-safe" read question

ok "legacy active flag ignored by codex" run env DUO_ACTIF=1 "$duo/codex-safe" read question
ok "legacy active flag ignored by claude" run env DUO_ACTIF=1 "$duo/claude-safe" read question

echo "Passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
