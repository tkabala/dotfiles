---
name: bye
description: End-of-session wrap-up. Checks that work is committed and pushed, that nothing this session started is left running or lying around, what is finished and what is still open, and what is worth writing down for next time (a "start here tomorrow" note in memory, lasting lessons in CLAUDE.md or the project docs). Proposes everything and acts only on the user's approval.
disable-model-invocation: true
---

# bye: wrap up the session

The user is about to close this session. Your job is to make sure nothing is lost when the
conversation ends: no uncommitted work, nothing left running, no open point forgotten, and
no hard-won knowledge that only lives in this conversation.

Work in three phases: **look** (read-only), **propose** (one report, then wait), **act**
(only what the user approved). Never commit, push, delete, stop or write anything before
the user has answered the report, because they may want to keep things as they are.

## Phase 1: look (read-only)

Go back over the whole conversation first: what the user asked for, what was changed,
which repositories and files were touched, what was started, and what went wrong along
the way. The conversation is the main source; the commands below confirm the current state.

### Git, for every repository touched in this session (not only the current directory)

- `git status --short`: uncommitted or untracked files. Separate changes made in this
  session from ones that were already there; say which is which.
- `git stash list`: leftover stashes.
- `git log --oneline @{u}..` (or note "no upstream" if the branch was never pushed):
  commits not pushed yet.
- `git branch -vv` and `git worktree list`: extra branches or worktrees created in this
  session that are merged, abandoned or no longer needed.
- If the branch has a pull request (`gh pr view` / `glab mr view`), note its state and CI.
- If the repo is a chezmoi source (`chezmoi source-path` points at it), run
  `chezmoi status` to catch files edited directly in `~` instead of in the repo, or repo
  changes not yet applied.

### Leftovers from this session

Only things this session started; never touch the user's own processes or files.

- Background shells, monitors, dev servers, containers started here.
- Scheduled loops or reminders (`CronList`, an active `/loop`).
- Temporary files or directories created outside the scratchpad, debug output, test
  fixtures, commented-out code or debug prints left in the diff.

### Finished or not

- Compare what was asked with what was done. Note anything skipped, half done, failing
  (tests, CI, a build), or verified only partly.
- Scan the session's diff for new `TODO`/`FIXME`/`XXX` lines.
- Collect follow-ups that came up but were out of scope.

### Worth writing down

Look for things a future session would otherwise have to rediscover:

- **Where to pick up next time**: short-lived state (what's next, what's blocked, which
  branch or PR). Goes to Claude's memory as a `project` note with today's absolute date.
  Check memory for an earlier "next steps" note from a previous wrap-up and update or
  replace it instead of adding another.
- **Lessons and tricks about the project**: a gotcha, a command that works, why something
  is done a certain way, a mistake not to repeat. Goes to the project's `CLAUDE.md`. If
  the point is useful to a human reader too (how to use or maintain something), put it in
  the project's docs (README, `docs/`) instead, matching their style. If there is no
  `CLAUDE.md`, propose creating one or fall back to memory.
- **About the user or how they like to work** (not tied to this project): memory, as a
  `user` or `feedback` note.

Read the target file first and skip anything already written there. Keep each entry short
and say why it matters, not just what it is. Leave out what the code or git history
already shows.

## Phase 2: propose

Give one report, in plain language (explain git terms briefly; the user isn't a git
expert), using this shape and leaving out sections that have nothing in them:

```
## Session wrap-up

**Done:** <one or two lines on what was accomplished>

**Git**
- <repo>: <clean / N uncommitted files / N commits not pushed / ...>
  Proposed: <commit "message" and push / push / nothing>

**Cleanup**
- <thing left over>: proposed <stop / delete / keep, because ...>

**Still open**
- <open point or follow-up, with enough context to pick it up cold>

**To write down**
- Memory (next time): <the note>
- CLAUDE.md / <doc file>: <the lesson, as it would be written>

Reply with what to do (e.g. "all", "all but the cleanup", or item by item).
```

For proposed commits, follow the repository's own commit message style (`git log
--oneline -10`) and any commit rules in CLAUDE.md or memory. If everything is clean and
there is nothing to write down, say so in a line or two and stop.

## Phase 3: act on what was approved

Do it in this order, so the final state is clean:

1. Write the approved notes (memory, CLAUDE.md, docs).
2. Clean up what was approved.
3. Commit and push what was approved. Doc and CLAUDE.md edits from step 1 belong in
   these commits too.
4. Check again (`git status`, unpushed commits) and end with one line per repository
   confirming its final state, plus the list of open points if there are any.

If something fails (a push is rejected, a hook fails), report it as it is, don't force it.
