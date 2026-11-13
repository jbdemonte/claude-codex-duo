# Working with Claude

Claude is your colleague on this machine. Call it yourself to read and review: the user should not have to copy and paste between you.

**Language.** Talk to the user in the language they write in. This includes the end-of-task summary, its labels, and the sentence you give them to hand the work to your colleague. Write to your colleague in that language too: the user may read your messages.

## When to call

- When the user asks in their own words: "ask Claude", "what does Claude think".
- Without being asked, to review a spec or nontrivial code you just wrote.
- Not for a question, a small fix, or exploration.

## New feature or major change

1. Write the spec in `tasks/` with the next number if the project uses that folder. It must be enough for whoever implements it, without the context of this conversation.
2. Have Claude review it and fix what needs fixing.
3. Summarize it and wait for the user's explicit approval. Write no code before that. If the spec changes later, ask for approval again.
4. By default, you code and Claude reviews. If the user wants Claude to code, hand over as described in "Having Claude code".
5. Run the project's tests. Whoever did not code reviews. Fix and review, up to twenty-five rounds, then ask the user how to proceed.

If the user asks you to implement an approved spec, do so without repeating steps 1 to 3, then go to step 5. If it needs to change, ask for approval again.

Handle simple requests directly, without a spec or review.

## Having Claude code

The user wants to see Claude work. When Claude is to code, including when the user says "have Claude do it", do not launch it unless they explicitly ask you to run it in the background. Give them this sentence to type in their Claude session:

> The spec <path> is approved. Implement it in this session, run the tests, then have your code reviewed by Codex.

Before stopping, commit the spec if it changed and finish with the summary, with implementation under "Still open".

For a simple request without a spec, give only a sentence describing the work, without asking for a review.

## How to call

Always use `__CLAUDE_SAFE__`, never `claude` directly:

- `claude-safe read "message"`: Claude reads and answers without changing anything. For a review, name the commit or ask it to review the uncommitted changes: it knows how to run `git show` and `git diff`.
- `claude-safe code "message"`: Claude edits the project without committing. The user cannot see its work: launch it only if they explicitly ask you to run it in the background.
- `claude-safe forget`: run at the start of a new task. Otherwise, Claude keeps the conversation in this project.

<!-- windows -->
On Windows, do not pass the message as an argument: PowerShell 5.1 splits arguments that contain quotes. Put it in `DUO_MESSAGE`, between `@'` and `'@`, without escaping anything. `'@` must be alone at the start of a line:

```powershell
$env:DUO_MESSAGE = @'
Review the uncommitted changes in this repository.
'@
__CLAUDE_SAFE__ read
```

<!-- /windows -->
To use another model, prefix the call with `DUO_MODEL=<model>`.

Always run `claude-safe` outside the sandbox (`require_escalated`), from the first attempt and even for `forget`: it needs the network, keychain, and its state folder. Justification: "Review by Claude on the user's subscription, API keys removed." A review may take several minutes: wait for the command to finish.

If `claude-safe` says an agent called by its colleague cannot call it back, continue alone. If permission is denied, do not try another way, even `claude -p`: tell the user and remind them they can type `/approve`. If it fails for another reason, stop and explain why in one sentence. Do not bypass the failure: these checks keep calls on subscriptions.

## End-of-task summary

Whenever a task changes code or a spec, even for a simple request, finish your answer with this summary:

- **Reviewed by:** Claude, or "no one" with the reason.
- **Review rounds:** the number, up to twenty-five.
- **Tests:** the commands run and their results, or "none".
- **Still open:** anything neither fixed nor checked, or "nothing".
- **Tokens:** the output of `__USAGE_CODEX__`, copied exactly. __USAGE_SANDBOX__

## Shared rules

- Describe what Claude does in one or two plain sentences.
- Commit yourself after checking the diff, on the current branch, following the project's rules. Stage only files for this task.
- If a file you need to edit already has uncommitted changes, report that before starting.
- Do not create a branch unless asked. Never push or merge.
