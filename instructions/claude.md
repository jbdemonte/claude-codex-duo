# Working with Codex

Codex is your colleague on this machine. Call it yourself to read and review: the user should not have to copy and paste between you.

**Language.** Talk to the user in the language they write in. This includes the end-of-task summary, its labels, and the sentence you give them to hand the work to your colleague. Write to your colleague in that language too: the user may read your messages.

## When to call

- When the user asks in their own words: "ask Codex", "what does Codex think".
- Without being asked, to review a spec or nontrivial code you just wrote.
- Not for a question, a small fix, or exploration.

## New feature or major change

1. Write the spec in `tasks/` with the next number if the project uses that folder. It must be enough for whoever implements it, without the context of this conversation.
2. Have Codex review it and fix what needs fixing.
3. Summarize it and wait for the user's explicit approval. Write no code before that. If the spec changes later, ask for approval again.
4. By default, Codex codes and you review: hand over as described in "Having Codex code". The user can ask to reverse the roles: you then code and Codex reviews.
5. Run the project's tests. Whoever did not code reviews. Fix and review, up to twenty-five rounds, then ask the user how to proceed.

If the user asks you to implement an approved spec, do so without repeating steps 1 to 3, then go to step 5. If it needs to change, ask for approval again.

Handle simple requests directly, without a spec or review.

## Having Codex code

The user wants to see Codex work. When Codex is to code, including when the user says "have Codex do it", do not launch it unless they explicitly ask you to run it in the background. Give them this sentence to type in their Codex session:

> The spec <path> is approved. Implement it in this session, run the tests, then have your code reviewed by Claude.

Before stopping, commit the spec if it changed and finish with the summary, with implementation under "Still open".

For a simple request without a spec, give only a sentence describing the work, without asking for a review.

## How to call

Always use `__CODEX_SAFE__`, never `codex` directly:

- `codex-safe read "message"`: Codex reads and answers without changing anything.
- `codex-safe code "message"`: Codex edits the project without committing. The user cannot see its work: launch it only if they explicitly ask you to run it in the background.
- `codex-safe review <sha>`: Codex reviews a commit.
- `codex-safe forget`: run at the start of a new task. Otherwise, Codex keeps the conversation in this project.

<!-- windows -->
On Windows, run `codex-safe` and `usage` with the Bash tool, not PowerShell.

<!-- /windows -->
To use another model, prefix the call with `DUO_MODEL=<model>`. Run `code` and `review` in the background, as they may take more than ten minutes.

If `codex-safe` says an agent called by its colleague cannot call it back, continue alone. If it fails for another reason, stop and explain why in one sentence. Do not bypass the failure: these checks keep calls on subscriptions.

`codex-safe` refuses calls at 95% of the Codex quota. If the user explicitly asks you to ignore that quota, prefix the calls they specify with `DUO_IGNORE_QUOTA=1`. Never do this on your own, even after a refusal: beyond the quota, Codex draws on paid credits.

## End-of-task summary

Whenever a task changes code or a spec, even for a simple request, finish your answer with this summary:

- **Reviewed by:** Codex, or "no one" with the reason.
- **Review rounds:** the number, up to twenty-five.
- **Tests:** the commands run and their results, or "none".
- **Still open:** anything neither fixed nor checked, or "nothing".
- **Tokens:** the output of `__USAGE_CLAUDE__`, copied exactly.

## Shared rules

- Describe what Codex does in one or two plain sentences.
- Commit yourself after checking the diff, on the current branch, following the project's rules. Stage only files for this task.
- If a file you need to edit already has uncommitted changes, report that before starting.
- Do not create a branch unless asked. Never push or merge.
