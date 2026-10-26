# skein fact sheet

One source of truth for what skein does, extracted from the code at commit 98bd151
(version 0.1.3). Every top-level bullet ends in the file and line it came from. Where the
README or the usage text disagrees with the code, the code is recorded here and the
disagreement is listed under "Drift".

## Install

- Prerequisites checked by the installer: `git`, `node`, `jq` and `gh`; a missing one is a printed note, not a failure (`setup:18`).
- Every command requires `git`, `node` and `jq`; a command that touches a board or a driver also needs `gh` or the Superset CLI (`common.sh:3`, `common.sh:12`).
- `gh` is required by `skein review` and `skein merge` only outside local mode (`review.sh:9`, `merge.sh:11`).
- The Superset CLI is required by the Superset board and the Superset driver (`superset.sh:7`, `superset.sh:25`).
- `codex` is optional: `skein review` falls back to Claude when `codex` cannot run, and `skein doctor` reports its absence as a note rather than a failure (`review.sh:18-20`, `doctor.sh:28`).
- `claude` is required by the local driver (`local.sh:9`) and by the Superset driver's `local` check in `skein doctor` (`doctor.sh:26`).
- `./setup` symlinks each directory under `skills/` to `$HOME/.claude/skills/skein-<name>` and `bin/skein` to `$HOME/.local/bin/skein` (`setup:13-16`).
- Both destinations are overridable: `CLAUDE_SKILLS_DIR` for the skills directory and `SKEIN_BIN_DIR` for the bin directory (`setup:7-8`).
- `./setup` warns when the bin directory is not on `PATH`, then prints the installed version (`setup:17`, `setup:19`).
- `./setup --uninstall` removes the `skein-*` skill links and the bin link, and nothing else (`setup:9-11`).
- The README's install section matches this, and names the same prerequisites (`README.md:32-39`).

## Commands

`skein <command> [args]`. An empty command, `-h`, `--help` or `help` prints the usage text and
exits 0; `--version` or `version` prints the `VERSION` file; an unknown command prints the
usage text to stderr and exits 2 (`bin/skein:54-60`). Every command runs from anywhere inside
the repository and dies with "not inside a git repository" outside one (`common.sh:15`).
`SKEIN_HOME` is resolved from the script's own path through symlinks, and a vendored copy is
detected by the absence of a sibling `commands/` directory (`bin/skein:8-18`).

### `skein init`

- Scaffolds a repository: `.skein/config.json`, the vendored runtime, `AGENTS.md`, `docs/plan/`, CI, the pre-push hook and the Superset lifecycle scripts (`init.sh:6-9`).
- Flags: `--name <n>`, `--prefix <P>`, `--board github|superset|none`, `--driver superset|local` (default `superset`), `--base <branch>`, `--force-templates` (`init.sh:14-18`).
- Any other flag is refused with "unknown flag" (`init.sh:18`).
- It refuses to run without the kit's `templates/` directory, so a vendored copy cannot run it (`init.sh:12`); `init.sh` and `upgrade.sh` are deleted from the vendored copy (`init.sh:87`).
- It refuses `--board github` in local mode, because the GitHub board needs an origin remote (`init.sh:22`).
- Defaults it derives: the name from the repository directory name, the prefix from the name uppercased up to the first hyphen, stripped to `A-Z0-9` and cut to six characters, and the base branch from `origin/HEAD` falling back to `main` (`init.sh:23-25`).
- It detects the toolchain from the lockfile or manifest present (pnpm, bun, yarn, npm, cargo, uv, go) and fills `install`, `standard` and the CI setup step from it (`init.sh:31-62`).
- For a Node package manager the `standard` commands are whichever of `typecheck`, `lint` and `test` exist as scripts in `package.json` (`init.sh:45`).
- Idempotent: an existing `.skein/config.json` and existing rendered files are kept unless `--force-templates` is passed (`init.sh:68`, `init.sh:102`).
- The vendored runtime is always refreshed, including on a repeat run (`init.sh:85-90`).
- The pre-push hook is the one exception to "left alone": it is rendered with `always` (`init.sh:123`).
- In local mode it writes no CI workflow and says so (`init.sh:121-122`).
- It appends `.superset/config.local.json` to `.gitignore`, adds the vendor glob to `knip.json` when that file exists, and sets `core.hooksPath` to `scripts/githooks` (`init.sh:128-133`).
- It prints a four-step "Next" block rather than a JSON line (`init.sh:135-145`).

### `skein upgrade`

- Resyncs the vendored runtime from the installed kit; config, plan, briefs and rendered docs are left alone (`upgrade.sh:2-4`).
- Takes no flags or positional arguments (`upgrade.sh:1-17`).
- Requires a config file and the kit's `templates/` directory (`upgrade.sh:5-6`).
- It runs `git pull -q --ff-only` in the kit checkout unless `SKEIN_KIT_GIT` is set, and only warns when the pull fails (`upgrade.sh:9`).
- It re-renders `scripts/githooks/pre-push` from the template with the config's base branch and coordinator environment variable (`upgrade.sh:16`).
- It prints the old and new versions as a log line, not JSON (`upgrade.sh:17`).

### `skein doctor`

- Checks this machine and this repository before coordinating, and is read-only (`doctor.sh:2`).
- Takes no flags (`doctor.sh:1-31`).
- It checks `git`, `node` and `jq` on `PATH`, the config, the plan file and its task count, the vendored `skein` and its version, and `core.hooksPath` (`doctor.sh:8-12`).
- In local mode it reports local mode; otherwise it checks that origin is reachable (`doctor.sh:13-14`).
- Board checks: `github` needs `gh` authenticated and fails in local mode; `superset` needs the Superset CLI authenticated; `none` always passes (`doctor.sh:15-20`).
- Driver checks: `superset` resolves the project id for this checkout; `local` needs `claude` on `PATH` (`doctor.sh:21-27`).
- It reports both caps and the `standard` commands, and fails when there are none (`doctor.sh:29-30`).
- It exits 1 when any check failed, after printing the count (`doctor.sh:31`).

### `skein plan`

- The task DAG, read-only: each task's readiness and the ownership overlaps that decide what can run together (`plan.mjs:2-3`).
- It passes every argument through to `lib/plan.mjs` (`plan.sh:3`).
- Flags: `--json` for the same data as JSON, `--check <TASK-ID>` to validate a brief, and `--dispatchable` for the ids that could be dispatched now, one per line (`plan.mjs:5-8`, `plan.mjs:16-19`).
- It exits 2 when the plan file is missing (`plan.mjs:26`).
- `--check` exits 1 with one line per problem, or 0 with "ok" (`plan.mjs:90-91`).
- The default view prints a count line, one row per task, then the overlaps among ready tasks or a line saying there are none (`plan.mjs:97-105`).

### `skein brief`

- Validates a brief against its task, or scaffolds a new one; the `/skein-brief` skill is what writes a brief (`brief.sh:2-5`).
- Positional arguments: the task id, then the mode, which defaults to `--check` (`brief.sh:8`).
- `skein brief <TASK>` with no mode runs the same validation as `skein plan --check <TASK>` (`brief.sh:12`).
- `skein brief <TASK> --new` renders `templates/brief.md.tmpl` into the briefs directory with the task's id, title, owned globs and accept commands filled in (`brief.sh:13-19`).
- `--new` refuses when the file already exists (`brief.sh:15`).
- Any other mode is refused with "unknown mode" (`brief.sh:20`).
- A missing task id is refused with the usage line (`brief.sh:9`).
- The validator requires a title, the sections `Objective`, `Read first`, `You own`, `Work` and `Acceptance`, every owned glob listed under "You own", at least one accept command, at least one owned glob, the task id somewhere in the text, and a non-null `brief` path in the plan (`plan.mjs:80-87`).

### `skein dispatch`

- Claims the task on the board, creates the workspace, waits for setup and launches the worker (`dispatch.sh:3`).
- Flags: `--tag <t>` (default `running`), `--model <m>`, `--agent <a>`, `--effort <e>`; a bare argument is the task id (`dispatch.sh:9-12`).
- Any other flag is refused with "unknown flag", and a missing task id with the usage line (`dispatch.sh:12-13`).
- Unset flags fall back to `worker.agent` (default `claude`), `worker.model` and `worker.effort` from the config (`dispatch.sh:17-19`).
- It prints one JSON line on success: `task`, `ok`, `workspace`, `terminal`, `branch`, `head`, `model`, `worktree`, `board` (`dispatch.sh:85-87`).
- On any failure it prints `{task, ok:false, error}` and exits 1, after releasing the claim back to `ready` and deleting a half-built workspace (`dispatch.sh:26-30`).
- It refuses when the brief does not validate, quoting the validator's reasons (`dispatch.sh:34`).
- It refuses when the task is not dispatchable because a dependency is not merged (`dispatch.sh:35`).
- It refuses when the brief or the plan differs from the base reference, because workspaces fork from there (`dispatch.sh:38-39`).
- A leftover branch with no commits of its own is deleted so the workspace forks from today's base; a branch with commits on it is a refusal (`dispatch.sh:44-54`).
- It refuses when either cap is reached, and refuses again after claiming if the repository is over its cap, releasing the claim (`dispatch.sh:57`, `dispatch.sh:63`).
- It refuses when workspace creation fails, when setup fails, when the worktree cannot be found, when the brief is missing inside the worktree, and when the workspace head is not the base reference (`dispatch.sh:66-73`).
- It refuses when the agent does not start (`dispatch.sh:83`).
- The worker prompt is fixed unless `workerPrompt` overrides it, with a separate default for local mode; the placeholders substituted are `{ID}`, `{NAME}`, `{BRIEF}`, `{GATE}` and `{BASE}` (`dispatch.sh:76-81`).
- It comments on the board naming the workspace, branch, agent, model and head (`dispatch.sh:84`).

### `skein watch`

- Polls one worker until it emits a completion envelope naming this task, vanishes, or times out (`watch.sh:3-6`).
- Positional arguments in order: `<TASK>`, `ws`, `term`, `max-hours`, `poll-seconds`, `marker`, plus the `--resume` flag anywhere (`watch.sh:2`, `watch.sh:9`).
- `ws` and `term` accept `-` or an empty value, which means "ask the driver" (`watch.sh:12-13`).
- Defaults: 8 max-hours, a 120 second poll, and no marker (`watch.sh:14`).
- With `--resume`, envelopes already on screen when the watch starts are recorded as a baseline and ignored, so it must be started before the follow-up prompt is sent (`watch.sh:4-6`, `watch.sh:28`).
- The `marker` argument truncates the screen text to everything after its last occurrence (`watch.sh:27`).
- It prints `SKEIN_WATCH task=<id> outcome=DONE|BLOCKED` and the last screen, then exits 0 (`watch.sh:40-42`).
- Five consecutive empty reads print `outcome=TERMINAL_UNREADABLE` and exit 2 (`watch.sh:24`).
- The deadline prints `outcome=TIMEOUT after <n>h` and exits 1 (`watch.sh:47-48`).
- It refuses when no workspace is found for the task, and when the workspace has no agent terminal (`watch.sh:12-13`).
- Its log, last screen and resume baseline live in `SKEIN_STATE_DIR`, falling back to a directory under `TMPDIR` named after the repository (`watch.sh:15-16`).
- An envelope counts only when the summary or reason line is non-empty and carries no angle brackets, so an unfilled template line is not a result (`watch.sh:33`).

### `skein status`

- Every task running anywhere according to the board, and every worker running here according to the driver, with both caps (`status.sh:2-3`).
- Read-only: it never sends anything to a worker (`status.sh:3`).
- Takes no flags (`status.sh:1-41`).
- Per workspace it prints a state read from the terminal text: DONE awaiting gate, BLOCKED, usage limit, API retry, working, idle at prompt, or no agent (`status.sh:21-29`).
- It also prints the commit count against the base branch, the uncommitted file count, the worktree path and the agent's last note (`status.sh:30-39`).
- It closes with a line saying the gate, not this view, decides done (`status.sh:41`).

### `skein send`

- Delivers one line to a running worker, with quoting handled (`send.sh:2`).
- Positional arguments: the task id and the message; both are required (`send.sh:4`).
- Newlines in the message are turned into spaces before sending (`send.sh:8`).
- It refuses when no workspace is found for the task, and when the workspace has no agent terminal (`send.sh:6-7`).
- It prints "sent to <ID>" as a log line (`send.sh:8`).

### `skein gate`

- The merge gate for one task, with three callers: the worker before it claims done, the coordinator before it merges, and CI (`gate.mjs:2-4`).
- It passes every argument through to `lib/gate.mjs` (`gate.sh:3`).
- Flags: `--base <ref>`, `--only <check>[,<check>]`, `--timeout-min <n>` (default 30), `--from-branch` and `--standard-only` (`gate.mjs:7-9`, `gate.mjs:28`, `gate.mjs:32`).
- A value flag with no value, an unknown flag, a second positional argument, an unknown check name, or a non-positive timeout each exit 2 (`gate.mjs:39-51`).
- `--standard-only` runs the config's `standard` commands with no task at all, and is what CI runs on a push to the base branch (`gate.mjs:9`, `gate.mjs:87-99`).
- `--from-branch` resolves the task from `GITHUB_HEAD_REF`, then `SKEIN_BRANCH`, then the checked-out branch, matching the last path segment against task ids (`gate.mjs:104-115`).
- A branch that names no task runs the standard commands instead of failing, which is how a coordinator's own pull request passes (`gate.mjs:112-113`).
- Without a task id and without `--from-branch` it exits 2 (`gate.mjs:117`).
- It exits 2 when the config file is missing, when the plan file is missing, and when the task is not in the plan (`gate.mjs:85`, `gate.mjs:101`, `gate.mjs:119`).
- The default base is `origin/main` when that reference verifies, otherwise `main` (`gate.mjs:121`).
- It exits 1 when any check failed, 0 otherwise (`gate.mjs:288`).

### `skein review`

- Cross-model review of the task's pull request in a read-only worktree forked from the pull request branch, headless (`review.sh:2-4`).
- Flags: `--agent codex|claude` and `--model <m>`; a bare argument is the task id (`review.sh:2`, `review.sh:11-12`).
- Any other flag is refused with "unknown flag", and a missing task id with the usage line (`review.sh:12-13`).
- Unset flags fall back to `review.agent` (default `codex`) and `review.model` (`review.sh:15-16`).
- When the agent is `codex` and `codex --version` does not run, it warns and falls back to `claude` with `review.fallbackModel` (default `claude-fable-5-1`) (`review.sh:18-20`).
- An agent other than `codex` or `claude` is refused with "unknown review agent" (`review.sh:52`).
- The reviewer only reads: `codex` runs in its read-only sandbox, and `claude` is given read tools plus `git diff`, `log`, `show` and `status` and nothing else (`review.sh:39-42`).
- Outside local mode it refuses when there is no open pull request for the branch (`review.sh:27`); in local mode it refuses when the local branch does not exist (`review.sh:23`).
- It refuses when the review produced no output, and warns when the output carries no `REVIEW_DONE` envelope (`review.sh:54-55`).
- It prefixes the findings with an HTML comment marker naming the task, the reviewer and the caller, which is the evidence `skein merge` requires (`review.sh:56-57`).
- Outside local mode it posts the findings as one pull request comment, and warns rather than failing when the post does not go through (`review.sh:62`).
- In local mode it writes the findings to the reviews directory as `<ID>.md` (`review.sh:58-60`).
- It releases the board claim to `gating`, deletes the review workspace, and deletes the review branch, which holds no commits (`review.sh:64-68`).
- It prints one JSON line: `task`, `ok`, `pr`, `file`, `reviewer` (`review.sh:69`).

### `skein merge`

- Reruns the gate in the worker's worktree, squash-merges, closes the claim, deletes the workspace and then the branch, and marks the task done in the plan with a log line (`merge.sh:3-5`).
- Flags: `--no-gate`; a bare argument is the task id (`merge.sh:2`, `merge.sh:13`).
- Any other flag is refused with "unknown flag", and a missing task id with the usage line (`merge.sh:13-14`).
- It refuses a task claimed by someone else (`merge.sh:19`).
- It refuses a `money` or `pii` task without the review marker: a comment from a repository owner, member or collaborator outside local mode, or the review file in local mode (`merge.sh:26-27`, `merge.sh:32-36`).
- `--no-gate` is honoured only when a CI check whose name matches "gate" succeeded on the pull request, and is refused outright in local mode (`merge.sh:23`, `merge.sh:40-43`).
- Without `--no-gate` it refuses when there is no local worktree to run the gate in, and refuses to merge when the gate fails (`merge.sh:45-48`).
- Outside local mode it refuses when there is no open pull request, marks the pull request ready, and refuses when the squash merge fails (`merge.sh:30`, `merge.sh:67-71`).
- It does not pass a delete-branch flag to the merge, so the workspace teardown runs before the branch goes (`merge.sh:68-70`, commit a3343f9).
- In local mode it refuses unless the base branch is checked out in the coordinator's checkout and that checkout is clean, refuses a branch with no commits beyond the base, and resets the squash on a conflict (`merge.sh:54-62`).
- The local-mode squash subject follows the pull request title rule, `<type>: <title> (<ID>)`, so `skein plan` sees the task merged (`merge.sh:52-57`).
- After merging it closes the board claim, deletes the workspace, deletes the remote branch outside local mode, and deletes the local branch (`merge.sh:74-80`).
- It then sets `done: true` on the task, appends a line to `LOG.md` next to the plan, commits both, and pushes to the base branch outside local mode, warning rather than failing if any of that does not work (`merge.sh:83-87`).
- It prints one JSON line: `task`, `ok`, `merged` (`merge.sh:88`).

## Gate

Nine checks in this order (`gate.mjs:27`, `gate.mjs:276-285`). Each prints a `[PASS]`,
`[FAIL]` or `[SKIP]` line with up to 40 notes (`gate.mjs:73-78`).

| check | what it checks | what makes it fail | source |
|---|---|---|---|
| `brief` | the task has a brief and the file exists | `brief` is null in the plan, or the path does not exist | `gate.mjs:145-150` |
| `clean-tree` | the working tree has no uncommitted changes | any output from the porcelain status | `gate.mjs:151-155` |
| `boundary` | every changed file is the task's to change | a coordinator-owned path in a non-coordinator task, or a path outside the task's `owned` globs and the plan's `alwaysAllowed` | `gate.mjs:156-169` |
| `secrets` | no credential reached a commit | a forbidden filename, a line matching a key pattern, or a 32-byte hex value on a line naming a key or secret | `gate.mjs:196-210` |
| `test-integrity` | no test was weakened, no shared suite shrank | an added line carrying a weakener token, or a monotonic count that fell | `gate.mjs:220-232` |
| `invariants` | the repository's own "never do this" rules | an added line matching a rule's `pattern`, outside the rule's `except` globs and outside comments | `gate.mjs:234-248` |
| `standard` | the config's `standard` commands | any command exiting non-zero, or no commands configured at all | `gate.mjs:259-263` |
| `e2e` | the config's `e2e` commands | any command exiting non-zero; an empty list passes | `gate.mjs:264-268` |
| `accept` | the task's own `accept` commands | any command exiting non-zero, or no accept commands in the plan | `gate.mjs:269-273` |

- Monotonic counts sit inside `test-integrity`, not in a check of their own: for each `monotonic` entry whose file changed, the count of the pattern in the file may not fall below its count at the base (`gate.mjs:223-229`).
- `secrets` and `test-integrity` and `invariants` read added lines only, so a rule is about what this branch wrote (`gate.mjs:132-141`).
- The secret patterns are described by kind rather than typed out: Stripe or Clerk secret keys, Stripe restricted keys, Stripe live publishable keys, Stripe webhook signing secrets, Resend API keys, Anthropic API keys, OpenAI API keys, GitHub tokens, AWS access key ids, Slack tokens, and a PEM private-key header, plus any pair added in `secretPatterns` (`gate.mjs:171-184`).
- `secrets` also fails a line that names a key, signer, secret or mnemonic and carries a 64-character hex value, unless that value is one of three published development accounts or is listed in `secretAllow` (`gate.mjs:186-194`, `gate.mjs:202-204`).
- Committing an environment file or an SSH private key by name fails the check whatever the contents (`gate.mjs:194`, `gate.mjs:198`).
- The weakener tokens are likewise described rather than typed: a focused or skipped test call in either the dotted or the prefixed form, the TypeScript pragma that switches off checking for a whole file, the pragma that suppresses the next error without failing when it goes away, a file-wide lint disable comment, Rust's ignore attribute, and Python's two skip markers (`gate.mjs:212-219`).
- Because those are literal token searches over every added line of every file, prose that spells one out fails the check as surely as code does (`gate.mjs:212-222`).
- Once an earlier check fails, `standard`, `e2e` and `accept` are recorded as `SKIP` rather than run, unless `--only` was passed (`gate.mjs:282-285`).
- `--only` therefore also turns the skipping off, which is what makes a fast static pass usable on its own (`gate.mjs:283-285`).
- Each `standard`, `e2e` and `accept` command runs through the shell with the gate's timeout, and the first failure stops that check's list (`gate.mjs:250-258`).
- CI runs a subset: on a pull request `--from-branch --only brief,boundary,secrets,test-integrity,invariants,standard,accept`, which leaves out `clean-tree` and `e2e`; on a push to the base branch, `--standard-only` (`ci.yml.tmpl:27-32`).
- The gate's last line is `SKEIN_GATE_RESULT task=<id> base=<ref> status=PASS|FAIL checks=<name>:<status>,...`, one entry per check that ran (`gate.mjs:287`).
- Under `--standard-only` that line carries `task=-` and a single `standard` entry, and no base (`gate.mjs:96`).
- The gate is vendored into each repository and coordinator-owned there, so a worker cannot weaken the gate it is judged by (`gate.mjs:2-5`).
- It is dependency-free on purpose: it runs on whatever `node` is on `PATH`, before any install (`gate.mjs:5`).

## Plan

The plan file is `docs/plan/wps.json` by default (`plan.mjs:24`).

- Task fields the code reads: `id`, `title`, `type`, `slug`, `brief`, `owned`, `deps`, `accept`, `money`, `pii`, `done` and `coordinator` (`plan.mjs:52-62`, `gate.mjs:146-160`, `gate.mjs:270`, `common.sh:66-75`, `merge.sh:21`, `merge.sh:56`).
- `id` is matched case-insensitively everywhere, and the plan's spelling is canonical (`common.sh:58`, `common.sh:63`, `gate.mjs:118-120`).
- `type` and `slug` give the branch name `<type>/<slug>-<id>` with the id lowercased, and the workspace name `<type>: <slug words> (<ID>)`; without both, the branch and the workspace are named after the id alone (`common.sh:65-75`).
- `owned` is a list of globs; `**` crosses directories, `*` stops at a slash and `?` matches one non-slash character (`gate.mjs:59-71`).
- `coordinator: true` exempts a task from the coordinator-owned paths, and nothing else (`gate.mjs:160-163`).
- Plan-level `coordinatorOwned` always wins over a task's `owned` globs, and plan-level `alwaysAllowed` is permitted to every task (`gate.mjs:158-164`).
- The four statuses are `merged`, `no brief`, `waiting on deps` and `ready`, in that order of precedence (`plan.mjs:61`).
- `ready` means not merged, a `brief` path that exists on disk, and every dependency merged (`plan.mjs:58-61`).
- A task counts as merged when the plan says `done: true`, which `skein merge` sets, or when a commit subject in the last 1000 on the main reference ends with `(<ID>)`, optionally followed by a pull request number (`plan.mjs:49-56`).
- The main reference is `origin/main` when an origin remote exists, after a fetch, and the local `main` otherwise (`plan.mjs:48`).
- The overlap rule is deliberately conservative: two globs overlap when one's literal prefix up to its first wildcard contains the other's, and two wildcard-free globs overlap only when they are equal (`plan.mjs:38-45`).
- Overlaps are computed among ready tasks only, pairwise, and reported as the shared globs (`plan.mjs:64-69`).
- The reason for the conservatism is stated in the code: a false overlap costs one serialized merge round, a missed one costs a conflict (`plan.mjs:38-39`).

## Config

`.skein/config.json`, committed with the repository. Every key below is read by the code at
the line given; a default of "none" means the code reads it only when it is present.

| key | default | read at |
|---|---|---|
| `version` | `1` as written | written at `init.sh:73`; no command reads it |
| `name` | the repository directory name | `status.sh:6`, `dispatch.sh:80`, `doctor.sh:9` |
| `prefix` | `TASK` | `common.sh:40` |
| `mode` | none | `common.sh:46` |
| `envelope` | `<prefix>_WORKER` | `common.sh:41` |
| `coordinatorEnv` | `<prefix>_COORDINATOR` | `common.sh:51` |
| `plan` | `docs/plan/wps.json` | `common.sh:38`, `plan.mjs:24`, `gate.mjs:100` |
| `briefs` | `docs/plan/briefs` | `common.sh:39`, `plan.mjs:25`, `gate.mjs:146` |
| `reviews` | `docs/plan/reviews` | `review.sh:59`, `merge.sh:25` |
| `vendor` | `scripts/skein` | `upgrade.sh:7`, `merge.sh:16`, `merge.sh:47`, `doctor.sh:11` |
| `gate` | `scripts/skein/skein gate` | `dispatch.sh:20`, `brief.sh:18` |
| `baseBranch` | `main` | `dispatch.sh:21`, `merge.sh:16`, `upgrade.sh:16`, `status.sh:34` |
| `board` | `{type, repo}`; type `github`, or `none` in local mode | `common.sh:49`, `github.sh:16` |
| `driver` | `{type}`; type `superset` | `common.sh:50` |
| `maxAgents` | `6` | `caps.sh:8` |
| `install` | `true` as written | written at `init.sh:76`; rendered into CI and the setup script at init time (`init.sh:108`, `ci.yml.tmpl:26`) |
| `standard` | empty, which fails the check | `gate.mjs:88`, `gate.mjs:260`, `doctor.sh:30` |
| `e2e` | empty, which passes | `gate.mjs:265` |
| `invariants` | empty, which passes | `gate.mjs:235` |
| `monotonic` | empty | `gate.mjs:223` |
| `secretPatterns` | empty | `gate.mjs:183` |
| `secretAllow` | empty | `gate.mjs:190` |
| `worker` | `{agent: claude, model, effort}` | `dispatch.sh:17-19` |
| `review` | `{agent: codex, model, fallbackModel}` | `review.sh:15-16`, `review.sh:19`, `doctor.sh:28` |
| `workerPrompt` | none; the built-in prompt is used | `dispatch.sh:76`, `dispatch.sh:79` |
| `readyMarker` | `workspace '.*' ready` | `superset.sh:26`, `local.sh:12` |
| `setupScript` | `.superset/setup.sh` | `local.sh:14` |
| `setupTimeout` | `300` | `dispatch.sh:68`, `review.sh:34` |
| `setupFatal` | a pattern covering package manager and TypeScript errors | `superset.sh:27`, `local.sh:13` |

- Values are read one at a time with `jq`, and an empty or missing value falls back to the default passed at the call site (`common.sh:23-29`).
- `~/.skein/config.json` is the per-machine config, and holds `maxAgents` (default 3) and `projects`, a map from a checkout path to `{supersetProjectId}` (`caps.sh:7`, `superset.sh:42`).
- `SKEIN_MAX_AGENTS` overrides the machine cap (`caps.sh:7`).
- `SKEIN_PROJECT_ID` overrides the resolved Superset project id (`superset.sh:40`).
- `SKEIN_DRIVER` overrides `driver.type`, for a machine without Superset (`common.sh:50`).
- `SKEIN_BOARD` overrides `board.type` (`common.sh:49`).
- `SKEIN_USER_CONFIG` overrides the path of the per-machine config (`common.sh:18`).
- `SKEIN_WORKTREES` overrides where the local driver keeps worktrees, default `~/.skein/worktrees` (`local.sh:10`).
- `SKEIN_RUNS` overrides where the local driver keeps run logs, default `~/.skein/runs` (`local.sh:11`).
- `SKEIN_STATE_DIR` overrides where `skein watch` keeps its log, snapshot and baseline (`watch.sh:15`).
- `SKEIN_KIT_GIT` tells `skein upgrade` not to pull the kit checkout (`upgrade.sh:9`).
- Two more are read and are not in the README: `SKEIN_BRANCH`, a fallback branch name for the gate's `--from-branch` (`gate.mjs:107`), and `SKEIN_BIN_DIR` with `CLAUDE_SKILLS_DIR` for the installer's destinations (`setup:7-8`).
- The coordinator environment variable named by `coordinatorEnv` is what lets a push to the base branch through the pre-push hook; it is a guard, not a permission system, because anyone can set it (`pre-push.tmpl:8-10`, `pre-push.tmpl:14`).

## Boards and drivers

Every board implements `board_claim`, `board_release`, `board_close`, `board_owner`,
`board_running_count`, `board_list` and `board_comment`, and the type names the file under
`lib/boards/` that is sourced; an unknown type is a refusal (`github.sh:6-13`,
`common.sh:78`).

- **GitHub** is the default outside local mode: one issue per task titled `<ID>: <title>`, labelled `skein`, with the state in a `state:` label (`github.sh:2-4`).
- Assigning yourself is the claim, and an unassigned issue is free (`github.sh:2-3`).
- An issue assigned to someone else is refused, and an issue already `state:running` under your own claim is refused as well (`github.sh:61-66`).
- Claims are checked twice because neither creating an issue nor assigning one is atomic across coordinators: on create, a lower-numbered open issue for the same id wins and ours is closed; on assign, the alphabetically first login wins and we back out (`github.sh:48-55`, `github.sh:70-77`).
- Issues are listed rather than searched, because GitHub's search index lags a fresh create (`github.sh:29-33`).
- `board_release <ID> ready` clears the assignee; `gating` and `blocked` keep the claim (`github.sh:81-88`).
- **Superset** is the organization task queue: one task per skein task, titled the same way, assigned to the claiming user, with labels carrying the state (`superset.sh:2-4`).
- It is best-effort about field names, because the CLI's task JSON has changed before, and reads the assignee from any of three shapes (`superset.sh:4`, `superset.sh:31`).
- It verifies exclusive ownership after the write, as the GitHub board does (`superset.sh:36-38`).
- Its `board_comment` is a no-op (`superset.sh:55`).
- **none** is a single coordinator with no shared claims: every function is a no-op, and the running count comes from the driver, so the repository cap then counts only what this machine runs (`none.sh:2-8`).

Every driver implements `driver_project_id`, `driver_create`, `driver_wait_setup`,
`driver_path`, `driver_launch`, `driver_read`, `driver_send`, `driver_tag`, `driver_delete`,
`driver_find`, `driver_list`, `driver_running_count` and `driver_agent_terminal`
(`superset.sh:6-18`).

- **Superset** workspaces are Superset worktrees, agents run in Superset terminals, and the coordinator reads and drives them through the CLI, which needs the desktop app running on this machine (`superset.sh:2-4`).
- Workspaces are created with a local flag, but terminals, agents and workspace reads address a workspace by id alone and Superset routes that to whichever host owns it, so every id-addressed call first proves the workspace is on this host and refuses otherwise (`superset.sh:20-23`, `superset.sh:30-37`, commit 7a57fd6).
- The project id is resolved from `SKEIN_PROJECT_ID`, then the per-machine `projects` map, then the checkout path as Superset knows it; failing all three is a refusal (`superset.sh:39-48`).
- A workspace that already exists is a refusal, so a dispatch never lands in a used workspace (`superset.sh:56`).
- Setup is polled every three seconds for the readiness marker, and a line matching the fatal pattern ends the wait early (`superset.sh:61-72`).
- Before launching interactive Claude Code it records the worktree as trusted in the user's Claude configuration, because the trust dialog cannot be answered through terminal sends (`superset.sh:76-86`, commit 491502c).
- It answers Codex's trust prompt once, then confirms the agent actually started, retyping the launch once before failing loudly (`superset.sh:98-120`).
- `driver_running_count` counts workspaces of this project tagged `running` on this host (`superset.sh:129-135`).
- The agent's terminal is the newest live terminal whose title is not a plain shell prompt (`superset.sh:137-141`).
- **local** needs no Superset: a workspace is a git worktree, the worker is Claude Code headless writing a stream of JSON to a log, and reading the terminal means rendering that log (`local.sh:2-5`).
- The workspace id is the worktree path and the terminal id is the run log path (`local.sh:7`).
- Driver state is kept outside the worktree on purpose: anything inside shows as untracked, and a worker chasing a clean tree for the gate deletes it (`local.sh:29-30`).
- Setup runs synchronously at create time, so the wait only checks the log (`local.sh:33-35`, `local.sh:39-44`).
- It runs `claude` only, and refuses any other agent (`local.sh:50`).
- Deleting a workspace kills the worker's process group, runs the teardown script if there is one, removes the worktree and prunes (`local.sh:82-90`).
- `driver_running_count` counts run logs whose recorded process is still alive (`local.sh:100-107`).

## Caps

- There are two caps, with two reasons: the per-machine cap protects this laptop and this seat's usage, and the per-repository cap protects the repository's merge rounds, review throughput and the number of disjoint tasks (`caps.sh:2-5`).
- The machine cap is `SKEIN_MAX_AGENTS`, else `maxAgents` in the per-machine config, else 3 (`caps.sh:7`).
- The repository cap is `maxAgents` in the repository config, else 6 (`caps.sh:8`).
- The local count comes from the driver and counts what this machine runs for this repository; the board count comes from the board and counts claims running anywhere (`caps.sh:10-11`).
- A dispatch must fit under both, and the check prints its reason on stdout either way (`caps.sh:5`, `caps.sh:12-23`).
- Because two coordinators can pass the check together, `skein dispatch` recounts after claiming and releases the claim if the repository is over its cap (`dispatch.sh:61-63`).

## Review

- `skein review` asks a different model to review the pull request in a read-only worktree forked from the branch, headless, and is mandatory for tasks marked `money` or `pii` (`review.sh:2-5`).
- The default reviewer is `codex`, which may be a shim with nothing behind it, so the command proves it runs before using it and otherwise falls back to Claude (`review.sh:17-20`).
- Codex is run non-interactively on purpose: out of quota its interactive screen opens on an upgrade menu that a pasted keystroke could confirm (`review.sh:44-47`).
- The prompt is rendered from `templates/review-prompt.md` with the task id, the pull request or branch, the brief path, the base reference and the task's `money` flag (`review.sh:37`).
- The evidence `skein merge` requires is the HTML comment marker the command writes, because a word in a comment is not evidence (`review.sh:56-57`).
- Outside local mode the marker must come from a repository owner, member or collaborator (`merge.sh:33-35`).
- The coordinator triages each finding on its merits; the command itself never changes code (`review.sh:5`, `review.sh:39`).

## Local mode

- Local mode is on when the config says `"mode": "local"` or when the repository has no origin remote (`common.sh:42-46`).
- In local mode nothing is pushed, there are no pull requests, workspaces fork from the local base branch, and `skein merge` squash-merges locally (`common.sh:42-44`).
- Base references drop the `origin/` prefix and fetches become no-ops (`common.sh:47-48`).
- The board defaults to `none` rather than `github` (`common.sh:49`).
- `skein init` sets `"mode": "local"`, defaults the board to `none`, refuses `--board github`, and writes no CI workflow (`init.sh:20-22`, `init.sh:80`, `init.sh:121-122`).
- The worker prompt tells the worker to leave everything committed on its branch and open no pull request (`dispatch.sh:78-79`).
- `skein dispatch` says to commit the brief and the plan on the base branch first, because the workspace forks from it (`dispatch.sh:37`).
- `skein review` reviews the branch's diff against the base branch and writes its findings, with the marker, to the reviews directory (`review.sh:6-7`, `review.sh:58-60`).
- `skein merge` refuses `--no-gate`, because the flag trusts a CI gate check and local mode has no CI (`merge.sh:23`, commit 0b42055).
- `skein merge` requires the base branch checked out and clean in the coordinator's checkout, squashes there, and pushes nothing (`merge.sh:51-65`, `merge.sh:83-87`).
- `skein doctor` reports local mode instead of checking origin, and fails a `github` board (`doctor.sh:13-16`).
- To leave local mode, add a remote and drop the `mode` key (`init.sh:4-5`).

## Skills

Five Claude Code skills, linked by the installer as `skein-<directory>` under the skills
directory (`setup:13-15`).

- `/skein-init` sets a repository up: it runs `skein init`, interviews the user for the project rules the scaffold cannot detect, fills `AGENTS.md` and the config, and commits (`init/SKILL.md:3`).
- `/skein-brief` writes a backlog-ready brief for one task and registers it in the plan, reading the code first and validating with `skein brief --check` and `skein plan` (`brief/SKILL.md:3`).
- `/skein-coordinate` runs a wave: check the machine, dispatch ready tasks under both caps, watch for envelopes, gate, review `money` and `pii` tasks, merge, and keep the plan true (`coordinate/SKILL.md:3`).
- `/skein-gate` runs the gate for a task and explains any failure with the fix (`gate/SKILL.md:3`).
- `/skein-status` reports what is happening across the flock, read-only: claims on the board, workers on this machine, both caps, and what is ready to dispatch (`status/SKILL.md:3`).
- The skills are the coordinator's; workers do not use them, and their gate is the only check they run (`AGENTS.md:43-45`).

## Drift

Where the README or the usage text disagrees with the code, the code is what this file
records. Each bullet cites both sides.

- The usage text for `init` lists four flags and leaves out `--base` and `--force-templates` (`bin/skein:27` against `init.sh:3`, `init.sh:17`).
- The usage text for `brief` shows only `--check` and leaves out `--new` (`bin/skein:34` against `brief.sh:2-4`).
- The usage text for `dispatch` leaves out `--effort` (`bin/skein:37` against `dispatch.sh:2`, `dispatch.sh:11`).
- The usage text for `watch` lists four positional arguments; the code takes six, plus `--resume` (`bin/skein:39` against `watch.sh:2`, `watch.sh:9`).
- The usage text for `gate` lists `--only` and `--base` and leaves out `--timeout-min`, `--from-branch` and `--standard-only` (`bin/skein:45` against `gate.mjs:7-9`, `gate.mjs:28`).
- The usage text for `review` leaves out `--agent` and `--model` (`bin/skein:47` against `review.sh:2`, `review.sh:11-12`).
- The usage text for `merge` leaves out `--no-gate` (`bin/skein:48` against `merge.sh:2`, `merge.sh:13`).
- The usage text describes the per-machine config as holding `maxAgents`; the code also reads `projects` from it (`bin/skein:50` against `superset.sh:42`).
- The README's gate description lists the checks from `clean-tree` onwards and leaves out the `brief` check, which runs first (`README.md:14-18` against `gate.mjs:27`).
- The README says CI runs the gate on every pull request without saying it runs a subset, leaving out `clean-tree` and `e2e` (`README.md:17` against `ci.yml.tmpl:27-32`).
- The README's config table lists eleven rows and leaves out `version`, `envelope`, `coordinatorEnv`, `plan`, `briefs`, `reviews`, `vendor`, `gate`, `baseBranch`, `readyMarker`, `setupScript`, `setupTimeout` and `setupFatal` (`README.md:83-95` against `common.sh:38-51` and the table above).
- The README groups `install` with `standard` and `e2e` as "commands the gate runs"; the gate runs `standard` and `e2e` only, and `install` is consumed by `skein init` when it renders CI and the setup script (`README.md:90` against `gate.mjs:260`, `gate.mjs:265`, `init.sh:108`).
- The README lists four placeholders for `workerPrompt`; the code also substitutes `{BASE}` (`README.md:95` against `dispatch.sh:81`).
- The README names three environment overrides; the code reads nine, plus `SKEIN_BRANCH`, `SKEIN_BIN_DIR` and `CLAUDE_SKILLS_DIR` (`README.md:98-99` against `common.sh:18`, `local.sh:10-11`, `watch.sh:15`, `upgrade.sh:9`, `gate.mjs:107`, `setup:7-8`).
- The README says `skein upgrade` pulls the kit; the pull is skipped when `SKEIN_KIT_GIT` is set, and a failed pull is a warning rather than a stop (`README.md:115` against `upgrade.sh:9`).
- The README says the board default is GitHub issues without the local-mode exception, where it is `none` (`README.md:22` against `common.sh:49`).
- The README's install line requires `gh` flatly; the installer only notes a missing binary, and `gh` is needed for the GitHub board and for pushing work, not in local mode (`README.md:38` against `setup:18`, `review.sh:9`, `merge.sh:11`).
- The README names another project of the owner's in its second paragraph, which the no-project-names convention rules out (`README.md:10` against commit 30a586b).
- The gate's default base is `origin/main`, or `main`, regardless of the config's `baseBranch`, and so is the reference `skein plan` reads merges from; neither the README nor the usage text says so (`gate.mjs:121`, `plan.mjs:48` against `README.md:86-89`).
