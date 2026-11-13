# duo

Claude Code and Codex CLI work together on your projects, using your subscriptions without API keys. Each can ask the other to review or give an opinion, without copying and pasting. When the other agent needs to code, you start it in its own session so you can watch the work.

## Requirements

- macOS, with `git` and `/usr/bin/python3`.
- Or Windows, with [Git for Windows](https://git-scm.com/download/win) and Python 3.14 or later: `winget install Python.Python.3.14`. Microsoft Store `python` aliases are not enough.
- Claude Code, logged in with a claude.ai account: `claude auth login`.
- Codex CLI, logged in with a ChatGPT account: `codex login`. Credentials must be in `~/.codex/auth.json`.
- `CLAUDE_CONFIG_DIR` and `CODEX_HOME` unset: otherwise `install.sh` stops.

## Before starting: disable paid usage

Beyond the quota, paid usage can take over instead of stopping everything. The scripts have a guard against this, but it is partial and does not protect a `claude` or `codex` you run manually:

- **Claude:** with usage credits, Claude Code switches to usage-based pricing. Disable them in [Settings > Usage](https://claude.ai/settings/usage), then run `claude auth login` to update the local account. `claude-safe` refuses to run while they are enabled.
- **Codex:** once plan limits are reached, usage draws on the credit balance. Check that balance and automatic top-ups in Codex Settings > Usage Dashboard. `codex-safe` stops at 95% of the quota, based on the current quota from Codex, or local logs if unavailable.

On a new machine, if Codex does not provide the current quota, there are no logs yet: the quota is unknown and `codex-safe` refuses to run. Run `codex` manually once.

## Installation

```sh
git clone <repository-url> duo
cd duo
./install.sh
```

Then open a new `claude` or `codex` session to load the instructions.

On Windows, run these commands in Git Bash. Claude calls Codex with its Bash tool. Codex, which works in PowerShell, calls Claude through Git's `bash.exe` and passes the message in `DUO_MESSAGE`: PowerShell 5.1 splits arguments that contain quotes. The installed instructions explain this to Codex.

Keep this folder: the installed instructions point to it. If you move it, run `./install.sh` again.

`install.sh` is safe to run again. It does four things:

- Adds instructions to `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`, between two `duo` markers, without touching the rest of those files.
- Prevents Claude from calling `codex` directly, in `~/.claude/settings.json`. On Windows, the rule also covers its PowerShell tool.
- Saves the locations of `claude`, `codex`, and Python in `paths.sh`, which is not tracked.
- Runs `codex-safe check`, which checks logins, settings, and the spending guard. If the check fails, installation stays in place, but duo refuses calls until the reported issue is resolved.

Before changing any of these three settings files, it copies it to `~/.local/state/duo/backups`. `paths.sh` is simply recreated.

## Usage

Run `claude` or `codex` in your project and talk normally. There are no commands to remember:

- "What does Codex think?"
- "Have Codex do it": the agent gives you a sentence to say in your own session
- "Run Codex in the background": it codes without you seeing its work
- "Have Claude review your code"

The agents talk to you in your language; scripts and instructions are in English.

For a new feature, the agent writes a spec, has its colleague review it, and waits for your approval. If the other agent is to code, it gives you a short sentence to say in that agent's session. Whoever coded then requests a review, up to twenty-five rounds. Simple requests are handled directly, without a spec or review.

When a task changes code or a spec, the agent finishes with a summary: who reviewed, how many rounds, which tests ran, what is still open, and tokens used.

With `approvals_reviewer = "auto_review"` in the Codex configuration, an automatic reviewer decides whether Codex may run `claude-safe`. Ask explicitly for the review: a call Codex decides to make on its own may be denied. After a denial, `/approve` allows that action once.

## What is guaranteed

The scripts enforce these protections:

- API keys and provider addresses are removed from the environment.
- Calls are refused if the login is not a subscription login.
- Calls are refused if settings point elsewhere: `openai_base_url`, `chatgpt_base_url`, `profile`, or another `model_provider` in `~/.codex/config.toml`, `~/.codex/managed_config.toml`, or their system equivalents (`/etc/codex` on Mac, `%ProgramData%\OpenAI\Codex` on Windows), even in an inactive profile; `ANTHROPIC_BASE_URL`, a key, `apiKeyHelper`, or a cloud provider in Claude settings. Only the setting's name is shown, never its value.
- Calls are refused if `CLAUDE_CONFIG_DIR` or `CODEX_HOME` are set, or if `DUO_MODEL` is not a simple model name.
- A called agent cannot call its colleague back, so they cannot call each other in a loop.
- `codex-safe read` runs read-only in the Codex sandbox.

These protections reduce risk without eliminating it:

- `claude-safe` refuses to run if extra usage is enabled or unknown in `~/.claude.json`. This internal field reflects the account at its last local update.
- `codex-safe` refuses to run at or above 95% of the quota. It asks the Codex server (`codex app-server`) for that quota, which it reads from your account without calling a model. If the server does not answer, it uses the latest reading in local logs. That reading cannot see usage on another machine or a reset since then, and just after a login change it may belong to the previous account. Calls already running are not interrupted.
- Settings deployed by a company through Mac management tools or Windows registry policies are not read.
- `claude-safe read` blocks Claude's editing tools. A command already allowed in its settings could still write.
- `claude-safe code` blocks common forms of commit, push, merge, rebase, and reset. Claude has shell access, so other ways remain possible.
- `settings.json` blocks usual calls to `codex`, but not, for example, `npx @openai/codex`.
- Codex now compresses its logs. To read them, `check` needs Python 3.14 or later. Otherwise it refuses calls. macOS's `/usr/bin/python3` is older: if you see this refusal on Mac, install a recent Python, for example with `brew install python`, then run `./install.sh` again.

These rules are only instructions, which an agent may forget:

- Wait for your approval before coding.
- Limit reviews to twenty-five rounds.
- Do not start the colleague's coding work in the background unless you ask.
- Use `DUO_IGNORE_QUOTA=1` only if you ask.
- Write the end-of-task summary.
- Never push or merge, and do not create a branch unless asked.
- Never call `claude` directly from Codex.

Four limitations to know:

- The spending guard reads internal formats. If they change, it may first use an old reading, then refuse calls until `check` is updated.
- A `claude` or `codex` you run yourself does not go through these scripts. It uses the active login: check it with `codex login status` and `claude auth status`.
- `codex-safe review` is not read-only. Codex may execute code and change the project.
- On Windows, the Codex sandbox runs under another account that cannot see Python or the logs: Codex therefore runs `usage` outside the sandbox, with your approval.

## Scripts

The agents use these themselves. You do not need to run them.

| Command | Role |
|---|---|
| `codex-safe read "message"` | Codex reads and answers without changing anything |
| `codex-safe code "message"` | Codex edits the project without committing |
| `codex-safe review <sha>` | Codex reviews a commit |
| `codex-safe check` | Checks logins, settings, and the spending guard |
| `claude-safe read "message"` | Claude reads and answers without changing anything |
| `claude-safe code "message"` | Claude edits the project without committing |
| `codex-safe forget`, `claude-safe forget` | Starts fresh on the next request |
| `usage` | Reports tokens for the session and the colleague's conversation, from local logs |

`DUO_MODEL=<model>` chooses another model for one call.

`DUO_IGNORE_QUOTA=1` disables the Codex quota guard for one call: beyond the quota, that call draws on paid credits. Login and destinations are still checked. Claude uses it only if you explicitly ask.

Run `tests/run.sh` to test the scripts. Tests cost nothing: they use a temporary home folder and fake agents, with no model or network calls. The test runner supports macOS only and stops before writing anything on other systems.

## Updating

```sh
git pull && ./install.sh
```

Then open a new session.

The installer migrates instruction blocks from older markers to the current markers, and replaces the old generated paths file with `paths.sh`. It leaves old backup folders and quota caches untouched. Do not update while a duo call is running; reopen existing agent sessions afterward so they use the new commands.

These scripts depend on internal `claude` and `codex` formats, which may change without notice. After either is updated, try them on a disposable repository: ask Codex for a small change, then ask Claude for a review. `codex-safe check` does not prove a full call works.

## Uninstalling

1. Remove the block between the `duo` markers in `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`.
2. Remove the two `codex` deny rules from `~/.claude/settings.json`, unless you had them before duo.
3. Delete this folder and `~/.local/state/duo`.
