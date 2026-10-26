# skein fact sheet

One source of truth for what skein does, extracted from the code at commit 4c2e2ef
(version 0.2.0). Every top-level bullet ends in the file and line it came from. Where the
README or the usage text disagrees with the code, the code is recorded here and the
disagreement is listed under "Drift".

## Install

- Prerequisites checked by the installer: `git`, `node`, `jq` and `gh`; a missing one is a printed note, not a failure (`setup:18`).
- Every command requires `git`, `node` and `jq`; a command that touches a board or a driver also needs `gh` or the Superset CLI (`lib/common.sh:3`, `lib/common.sh:12`).
- `gh` is required by `skein review` and `skein merge` only outside local mode (`commands/review.sh:9`, `commands/merge.sh:11`).
- The Superset CLI is required by the Superset board and the Superset driver (`lib/boards/superset.sh:7`, `lib/drivers/superset.sh:25`).
- `codex` is optional: `skein review` falls back to Claude when `codex` cannot run, and `skein doctor` reports its absence as a note rather than a failure (`commands/review.sh:18-20`, `commands/doctor.sh:29`).
- `claude` is required by the local driver (`lib/drivers/local.sh:9`), which is also what `skein doctor` checks when the driver is `local` (`commands/doctor.sh:27`).
- `./setup` symlinks each directory under `skills/` to `$HOME/.claude/skills/skein-<name>` and `bin/skein` to `$HOME/.local/bin/skein` (`setup:13-16`).
- Both destinations are overridable: `CLAUDE_SKILLS_DIR` for the skills directory and `SKEIN_BIN_DIR` for the bin directory (`setup:7-8`).
- `./setup` warns when the bin directory is not on `PATH`, then prints the installed version (`setup:17`, `setup:19`).
- `./setup --uninstall` removes the `skein-*` skill links and the bin link, and nothing else (`setup:9-11`).
- The README's install section matches this, and names the same prerequisites (`README.md:32-39`).

## Commands

`skein <command> [args]`. An empty command, `-h`, `--help` or `help` prints the usage text and
exits 0; `--version` or `version` prints the `VERSION` file; an unknown command prints the
usage text to stderr and exits 2 (`bin/skein:54-60`). Every command runs from anywhere inside
the repository and dies with "not inside a git repository" outside one (`lib/common.sh:15`).
`SKEIN_HOME` is resolved from the script's own path through symlinks, and a vendored copy is
detected by the absence of a sibling `commands/` directory (`bin/skein:8-18`).

### `skein init`

- Scaffolds a repository: `.skein/config.json`, the vendored runtime, `AGENTS.md`, `docs/plan/`, CI, the pre-push hook and the Superset lifecycle scripts (`commands/init.sh:6-7`).
- Flags: `--name <n>`, `--prefix <P>`, `--board github|superset|none`, `--driver superset|local`, `--base <branch>`, `--force-templates` (`commands/init.sh:16-20`); the driver falls back to `superset` only when neither a flag nor a kept config gives one (`commands/init.sh:38`).
- Any other flag is refused with "unknown flag" (`commands/init.sh:20`).
- It refuses to run without the kit's `templates/` directory, so a vendored copy cannot run it (`commands/init.sh:14`); `init.sh` and `upgrade.sh` are deleted from the vendored copy (`commands/init.sh:111`).
- It refuses `--board github` in local mode, because the GitHub board needs an origin remote (`commands/init.sh:41`).
- Defaults it derives, each only when neither a flag nor a kept config gives the value: the name from the repository directory name, the prefix from the name uppercased up to the first hyphen, stripped to `A-Z0-9` and cut to six characters, and the base branch from `origin/HEAD` falling back to `main` (`commands/init.sh:42-44`).
- It detects the toolchain from the lockfile or manifest present (pnpm, bun, yarn, npm, cargo, uv, go) and fills `install`, `standard` and the CI setup step from it (`commands/init.sh:55-86`).
- For a Node package manager the `standard` commands are whichever of `typecheck`, `lint` and `test` exist as scripts in `package.json` (`commands/init.sh:69`).
- Idempotent: a kept `.skein/config.json` and existing rendered files are left alone unless `--force-templates` (`commands/init.sh:92`, `commands/init.sh:126`). The kept config also supplies the name, prefix, base, board and driver that no flag gives, and a flag that contradicts it is refused with `<flag> <value> differs from the kept .skein/config.json (<kept value>)` unless `--force-templates` rewrites the config (`commands/init.sh:22-37`).
- The vendored runtime is always refreshed, including on a repeat run (`commands/init.sh:109-114`).
- The pre-push hook is the one exception to "left alone": it is rendered with `always` (`commands/init.sh:147`).
- In local mode it writes no CI workflow and says so (`commands/init.sh:145-146`).
- It appends `.superset/config.local.json` to `.gitignore`, adds the vendor glob to `knip.json` when that file exists, and sets `core.hooksPath` to `scripts/githooks` (`commands/init.sh:152-157`).
- It prints a four-step "Next" block rather than a JSON line (`commands/init.sh:159-169`).

### `skein upgrade`

- Resyncs the vendored runtime from the installed kit; config, plan, briefs and rendered docs are left alone (`commands/upgrade.sh:2-4`).
- Takes no flags or positional arguments (`commands/upgrade.sh:1-17`).
- Requires a config file and the kit's `templates/` directory (`commands/upgrade.sh:5-6`).
- It runs `git pull -q --ff-only` in the kit checkout unless `SKEIN_KIT_GIT` is set, and only warns when the pull fails (`commands/upgrade.sh:9`).
- It re-renders `scripts/githooks/pre-push` from the template with the config's base branch and coordinator environment variable (`commands/upgrade.sh:16`).
- It prints the old and new versions as a log line, not JSON (`commands/upgrade.sh:17`).

### `skein doctor`

- Checks this machine and this repository before coordinating, and is read-only (`commands/doctor.sh:2`).
- Takes no flags (`commands/doctor.sh:1-32`).
- It checks `git`, `node` and `jq` on `PATH`, the config and the version it declares, the plan file and its task count, the vendored `skein` and its version, and `core.hooksPath`; a config version this kit cannot use is reported as a failed check (`commands/doctor.sh:8-13`).
- In local mode it reports local mode; otherwise it checks that origin is reachable (`commands/doctor.sh:14-15`).
- Board checks: `github` needs `gh` authenticated and fails in local mode; `superset` needs the Superset CLI authenticated; `none` always passes (`commands/doctor.sh:16-21`).
- Driver checks: `superset` resolves the project id for this checkout; `local` needs `claude` on `PATH` (`commands/doctor.sh:22-28`).
- It reports both caps and the `standard` commands, and fails when there are none (`commands/doctor.sh:30-31`).
- It exits 1 when any check failed, after printing the count (`commands/doctor.sh:32`).

### `skein plan`

- The task DAG, read-only: each task's readiness and the ownership overlaps that decide what can run together (`lib/plan.mjs:2-3`).
- It passes every argument through to `lib/plan.mjs` (`commands/plan.sh:3`).
- Flags: `--json` for the same data as JSON, `--check <TASK-ID>` to validate a brief, `--dispatchable` for the ids that could be dispatched now, and `--overlapping <ID>` for the unmerged tasks whose owned paths overlap that task's, one id per line (`lib/plan.mjs:5-9`, `lib/plan.mjs:17-21`, `lib/plan.mjs:97-109`).
- It exits 2 when the plan file is missing (`lib/plan.mjs:28`).
- `--check` exits 1 with one line per problem, or 0 with "ok" (`lib/plan.mjs:94-95`).
- The default view prints a count line, one row per task, then the overlaps among ready tasks or a line saying there are none (`lib/plan.mjs:114-122`).

### `skein brief`

- Validates a brief against its task, or scaffolds a new one; the `/skein-brief` skill is what writes a brief (`commands/brief.sh:2-5`).
- Positional arguments: the task id, then the mode, which defaults to `--check` (`commands/brief.sh:8`).
- `skein brief <TASK>` with no mode runs the same validation as `skein plan --check <TASK>` (`commands/brief.sh:12`).
- `skein brief <TASK> --new` renders `templates/brief.md.tmpl` into the briefs directory with the task's id, title, owned globs and accept commands filled in (`commands/brief.sh:13-19`).
- `--new` refuses when the file already exists (`commands/brief.sh:15`).
- Any other mode is refused with "unknown mode" (`commands/brief.sh:20`).
- A missing task id is refused with the usage line (`commands/brief.sh:9`).
- The validator requires a title, the sections `Objective`, `Read first`, `You own`, `Work` and `Acceptance`, every owned glob listed under "You own", at least one accept command, at least one owned glob, the task id somewhere in the text, and a non-null `brief` path in the plan (`lib/plan.mjs:84-91`).

### `skein dispatch`

- Claims the task on the board, creates the workspace, waits for setup and launches the worker (`commands/dispatch.sh:3`).
- Flags: `--tag <t>` (default `running`), `--model <m>`, `--agent <a>`, `--effort <e>`, `--allow-overlap`; a bare argument is the task id (`commands/dispatch.sh:9-13`).
- Any other flag is refused with "unknown flag", a second task id with "one task per call", and a missing task id with the usage line (`commands/dispatch.sh:13-14`).
- Unset flags fall back to `worker.agent` (default `claude`), `worker.model` and `worker.effort` from the config (`commands/dispatch.sh:18-20`).
- It prints one JSON line on success: `task`, `ok`, `workspace`, `terminal`, `branch`, `head`, `model`, `worktree`, `board` (`commands/dispatch.sh:95-97`).
- On any failure it prints `{task, ok:false, error}` and exits 1, after releasing the claim back to `ready` and deleting a half-built workspace (`commands/dispatch.sh:27-31`).
- It refuses when the brief does not validate, quoting the validator's reasons (`commands/dispatch.sh:35`).
- It refuses when the task is not dispatchable because a dependency is not merged, and when the brief or the plan differs from the base reference, because workspaces fork from there (`commands/dispatch.sh:36`, `commands/dispatch.sh:39-40`).
- It refuses a task whose owned paths overlap a task in flight, claimed on the board or holding a workspace here, unless `--allow-overlap` is passed; the check runs once, before the claim (`commands/dispatch.sh:42-49`).
- A leftover branch with no commits of its own is deleted so the workspace forks from today's base; a branch with commits on it is a refusal (`commands/dispatch.sh:54-64`).
- It refuses when either cap is reached, and refuses again after claiming if the repository is over its cap, releasing the claim (`commands/dispatch.sh:67`, `commands/dispatch.sh:73`).
- It refuses when workspace creation fails, when setup fails, when the worktree cannot be found, when the brief is missing inside the worktree, and when the workspace head is not the base reference (`commands/dispatch.sh:76-83`).
- It refuses when the agent does not start (`commands/dispatch.sh:93`).
- The worker prompt is fixed unless `workerPrompt` overrides it, with a separate default for local mode; the placeholders substituted are `{ID}`, `{NAME}`, `{BRIEF}`, `{GATE}` and `{BASE}` (`commands/dispatch.sh:86-91`).
- It comments on the board naming the workspace, branch, agent, model and head (`commands/dispatch.sh:94`).

### `skein watch`

- Polls one worker until it emits a completion envelope naming this task, vanishes, or times out (`commands/watch.sh:3-6`).
- Positional arguments in order: `<TASK>`, `ws`, `term`, `max-hours`, `poll-seconds`, `marker`, plus the `--resume` flag anywhere (`commands/watch.sh:2`, `commands/watch.sh:9`).
- `ws` and `term` accept `-` or an empty value, which means "ask the driver" (`commands/watch.sh:12-13`).
- Defaults: 8 max-hours, a 120 second poll, and no marker (`commands/watch.sh:14`).
- With `--resume`, envelopes already on screen when the watch starts are recorded as a baseline and ignored, so it must be started before the follow-up prompt is sent (`commands/watch.sh:4-6`, `commands/watch.sh:28`).
- The `marker` argument truncates the screen text to everything after its last occurrence (`commands/watch.sh:27`).
- It prints `SKEIN_WATCH task=<id> outcome=DONE|BLOCKED` and the last screen, then exits 0 (`commands/watch.sh:40-42`).
- Five consecutive empty reads print `outcome=TERMINAL_UNREADABLE` and exit 2 (`commands/watch.sh:24`).
- The deadline prints `outcome=TIMEOUT after <n>h` and exits 1 (`commands/watch.sh:47-48`).
- It refuses when no workspace is found for the task, and when the workspace has no agent terminal (`commands/watch.sh:12-13`).
- Its log, last screen and resume baseline live in `SKEIN_STATE_DIR`, falling back to a directory under `TMPDIR` named after the repository (`commands/watch.sh:15-16`).
- An envelope counts only when the summary or reason line is non-empty and carries no angle brackets, so an unfilled template line is not a result (`commands/watch.sh:33`).

### `skein status`

- Every task running anywhere according to the board, and every worker running here according to the driver, with both caps; of the driver's workspaces only those named for a task in the plan are listed, and the others are counted on a closing line saying they carry no task id (`commands/status.sh:2-3`, `commands/status.sh:14-31`, `commands/status.sh:38-39`, `commands/status.sh:63`).
- Read-only: it never sends anything to a worker (`commands/status.sh:3`).
- Takes no flags (`commands/status.sh:1-64`).
- Per workspace it prints a state read from the terminal text: DONE awaiting gate, BLOCKED, usage limit, API retry, working, idle at prompt, or no agent (`commands/status.sh:42-50`).
- It also prints the commit count against the base branch, the uncommitted file count, the worktree path and the agent's last note (`commands/status.sh:51-60`).
- It closes with a line saying the gate, not this view, decides done (`commands/status.sh:64`).

### `skein send`

- Delivers one line to a running worker, with quoting handled (`commands/send.sh:2`).
- Positional arguments: the task id and the message; both are required (`commands/send.sh:4`).
- Newlines in the message are turned into spaces before sending (`commands/send.sh:8`).
- It refuses when no workspace is found for the task, and when the workspace has no agent terminal (`commands/send.sh:6-7`).
- It prints "sent to <ID>" as a log line (`commands/send.sh:8`).

### `skein gate`

- The merge gate for one task, with three callers: the worker before it claims done, the coordinator before it merges, and CI (`lib/gate.mjs:2-4`).
- It passes every argument through to `lib/gate.mjs` (`commands/gate.sh:3`).
- Flags: `--base <ref>`, `--only <check>[,<check>]`, `--timeout-min <n>` (default 30), `--from-branch` and `--standard-only` (`lib/gate.mjs:7-9`, `lib/gate.mjs:28`, `lib/gate.mjs:32`).
- A value flag with no value, an unknown flag, a second positional argument, an unknown check name, or a non-positive timeout each exit 2 (`lib/gate.mjs:39-51`).
- `--standard-only` runs the config's `standard` commands with no task at all, and is what CI runs on a push to the base branch (`lib/gate.mjs:9`, `lib/gate.mjs:100-112`).
- `--from-branch` resolves the task from `GITHUB_HEAD_REF`, then `SKEIN_BRANCH`, then the checked-out branch, matching the last path segment against task ids (`lib/gate.mjs:117-128`).
- A branch that names no task runs the standard commands instead of failing, which is how a coordinator's own pull request passes (`lib/gate.mjs:125-126`).
- Without a task id and without `--from-branch` it exits 2 (`lib/gate.mjs:130`).
- It exits 2 when the config file is missing, when the plan file is missing, and when the task is not in the plan (`lib/gate.mjs:85`, `lib/gate.mjs:114`, `lib/gate.mjs:132`).
- The default base is `origin/<baseBranch>` when that reference verifies, and `<baseBranch>` otherwise, with `baseBranch` defaulting to `main` (`lib/gate.mjs:134-135`).
- It exits 1 when any check failed, 0 otherwise (`lib/gate.mjs:302`).

### `skein review`

- Cross-model review of the task's pull request in a read-only worktree forked from the pull request branch, headless (`commands/review.sh:2-4`).
- Flags: `--agent codex|claude` and `--model <m>`; a bare argument is the task id (`commands/review.sh:2`, `commands/review.sh:11-12`).
- Any other flag is refused with "unknown flag", a second task id with "one task per call", and a missing task id with the usage line (`commands/review.sh:12-13`).
- Unset flags fall back to `review.agent` (default `codex`) and `review.model` (`commands/review.sh:15-16`).
- When the agent is `codex` and `codex --version` does not run, it warns and falls back to `claude` with `review.fallbackModel` (default `claude-fable-5-1`) (`commands/review.sh:18-20`).
- An agent other than `codex` or `claude` is refused with "unknown review agent" (`commands/review.sh:52`).
- The reviewer only reads: `codex` runs in its read-only sandbox, and `claude` is given read tools plus `git diff`, `log`, `show` and `status` and nothing else (`commands/review.sh:39-42`).
- Outside local mode it refuses when there is no open pull request for the branch (`commands/review.sh:27`); in local mode it refuses when the local branch does not exist (`commands/review.sh:23`).
- It refuses when the review produced no output, and warns when the output carries no `REVIEW_DONE` envelope (`commands/review.sh:54-55`).
- It prefixes the findings with an HTML comment marker naming the task, the reviewer and the caller, which is the evidence `skein merge` requires (`commands/review.sh:56-57`).
- Outside local mode it posts the findings as one pull request comment, and warns rather than failing when the post does not go through (`commands/review.sh:62`).
- In local mode it writes the findings to the reviews directory as `<ID>.md` (`commands/review.sh:58-60`).
- It releases the board claim to `gating`, deletes the review workspace, and deletes the review branch, which holds no commits (`commands/review.sh:64-68`).
- It prints one JSON line: `task`, `ok`, `pr`, `file`, `reviewer` (`commands/review.sh:69`).

### `skein merge`

- Reruns the gate in the worker's worktree, squash-merges, closes the claim, deletes the workspace and then the branch, and marks the task done in the plan with a log line (`commands/merge.sh:3-5`).
- Flags: `--no-gate`; a bare argument is the task id (`commands/merge.sh:2`, `commands/merge.sh:13`).
- Any other flag is refused with "unknown flag", a second task id with "one task per call", and a missing task id with the usage line (`commands/merge.sh:13-14`).
- It refuses a task claimed by someone else (`commands/merge.sh:19`).
- It refuses a `money` or `pii` task without the review marker: a comment from a repository owner, member or collaborator outside local mode, or the review file in local mode (`commands/merge.sh:26-27`, `commands/merge.sh:32-36`).
- `--no-gate` is honoured only when a CI check whose name matches "gate" succeeded on the pull request, and is refused outright in local mode (`commands/merge.sh:23`, `commands/merge.sh:40-43`).
- Without `--no-gate` it refuses when there is no local worktree to run the gate in, and refuses to merge when the gate fails (`commands/merge.sh:45-48`).
- Outside local mode it refuses when there is no open pull request, marks the pull request ready, and refuses when the squash merge fails (`commands/merge.sh:30`, `commands/merge.sh:67-71`).
- It does not pass a delete-branch flag to the merge, so the workspace teardown runs before the branch goes (`commands/merge.sh:68-70`, commit a3343f9).
- In local mode it refuses unless the base branch is checked out in the coordinator's checkout and that checkout is clean, refuses a branch with no commits beyond the base, and resets the squash on a conflict (`commands/merge.sh:54-62`).
- The local-mode squash subject follows the pull request title rule, `<type>: <title> (<ID>)`, so `skein plan` sees the task merged (`commands/merge.sh:52-57`).
- After merging it closes the board claim, deletes the workspace, deletes the remote branch outside local mode, and deletes the local branch (`commands/merge.sh:74-80`).
- It then sets `done: true` on the task, appends a line to `LOG.md` next to the plan, commits both, and pushes to the base branch outside local mode, warning rather than failing if any of that does not work (`commands/merge.sh:83-87`).
- It prints one JSON line: `task`, `ok`, `merged` (`commands/merge.sh:88`).

## Gate

Nine checks in this order (`lib/gate.mjs:27`, `lib/gate.mjs:290-299`). Each prints a `[PASS]`,
`[FAIL]` or `[SKIP]` line with up to 40 notes (`lib/gate.mjs:73-78`).

| check | what it checks | what makes it fail | source |
|---|---|---|---|
| `brief` | the task has a brief and the file exists | `brief` is null in the plan, or the path does not exist | `lib/gate.mjs:159-164` |
| `clean-tree` | the working tree has no uncommitted changes | any output from the porcelain status | `lib/gate.mjs:165-169` |
| `boundary` | every changed file is the task's to change | a coordinator-owned path in a non-coordinator task, or a path outside the task's `owned` globs and the plan's `alwaysAllowed` | `lib/gate.mjs:170-183` |
| `secrets` | no credential reached a commit | a forbidden filename, a line matching a key pattern, or a 32-byte hex value on a line naming a key or secret | `lib/gate.mjs:210-224` |
| `test-integrity` | no test was weakened, no shared suite shrank | an added line carrying a weakener token, or a monotonic count that fell | `lib/gate.mjs:234-246` |
| `invariants` | the repository's own "never do this" rules | an added line matching a rule's `pattern`, outside the rule's `except` globs and outside comments | `lib/gate.mjs:248-262` |
| `standard` | the config's `standard` commands | any command exiting non-zero, or no commands configured at all | `lib/gate.mjs:273-277` |
| `e2e` | the config's `e2e` commands | any command exiting non-zero; an empty list passes | `lib/gate.mjs:278-282` |
| `accept` | the task's own `accept` commands | any command exiting non-zero, or no accept commands in the plan | `lib/gate.mjs:283-287` |

- Monotonic counts sit inside `test-integrity`, not in a check of their own: for each `monotonic` entry whose file changed, the count of the pattern in the file may not fall below its count at the base (`lib/gate.mjs:237-243`).
- `secrets` and `test-integrity` and `invariants` read added lines only, so a rule is about what this branch wrote (`lib/gate.mjs:146-155`).
- The secret patterns are described by kind rather than typed out: Stripe or Clerk secret keys, Stripe restricted keys, Stripe live publishable keys, Stripe webhook signing secrets, Resend API keys, Anthropic API keys, OpenAI API keys, GitHub tokens, AWS access key ids, Slack tokens, and a PEM private-key header, plus any pair added in `secretPatterns` (`lib/gate.mjs:185-198`).
- `secrets` also fails a line that names a key, signer, secret or mnemonic and carries a 64-character hex value, unless that value is one of three published development accounts or is listed in `secretAllow` (`lib/gate.mjs:200-208`, `lib/gate.mjs:216-218`).
- Committing an environment file or an SSH private key by name fails the check whatever the contents (`lib/gate.mjs:208`, `lib/gate.mjs:212`).
- The weakener tokens are likewise described rather than typed: a focused or skipped test call in either the dotted or the prefixed form, the TypeScript pragma that switches off checking for a whole file, the pragma that suppresses the next error without failing when it goes away, a file-wide lint disable comment, Rust's ignore attribute, and Python's two skip markers (`lib/gate.mjs:226-233`).
- Because those are literal token searches over every added line of every file, prose that spells one out fails the check as surely as code does (`lib/gate.mjs:226-236`).
- Once an earlier check fails, `standard`, `e2e` and `accept` are recorded as `SKIP` rather than run, unless `--only` was passed (`lib/gate.mjs:296-299`).
- `--only` therefore also turns the skipping off, which is what makes a fast static pass usable on its own (`lib/gate.mjs:297-299`).
- Each `standard`, `e2e` and `accept` command runs through the shell with the gate's timeout, and the first failure stops that check's list (`lib/gate.mjs:264-272`).
- CI runs a subset: on a pull request `--from-branch --only brief,boundary,secrets,test-integrity,invariants,standard,accept`, which leaves out `clean-tree` and `e2e`; on a push to the base branch, `--standard-only` (`templates/ci.yml.tmpl:27-32`).
- The gate's last line is `SKEIN_GATE_RESULT task=<id> base=<ref> status=PASS|FAIL checks=<name>:<status>,...`, one entry per check that ran (`lib/gate.mjs:301`).
- Under `--standard-only` that line carries `task=-` and a single `standard` entry, and no base (`lib/gate.mjs:109`).
- The gate is vendored into each repository and coordinator-owned there, so a worker cannot weaken the gate it is judged by (`lib/gate.mjs:2-5`).
- It is dependency-free on purpose: it runs on whatever `node` is on `PATH`, before any install (`lib/gate.mjs:5`).

## Plan

The plan file is `docs/plan/wps.json` by default (`lib/plan.mjs:26`).

- Task fields the code reads: `id`, `title`, `type`, `slug`, `brief`, `owned`, `deps`, `accept`, `money`, `pii`, `done` and `coordinator` (`lib/plan.mjs:56-66`, `lib/gate.mjs:160-174`, `lib/gate.mjs:284`, `lib/common.sh:80-89`, `commands/merge.sh:21`, `commands/merge.sh:56`).
- `id` is matched case-insensitively everywhere, and the plan's spelling is canonical (`lib/common.sh:72`, `lib/common.sh:77`, `lib/gate.mjs:131-133`).
- `type` and `slug` give the branch name `<type>/<slug>-<id>` with the id lowercased, and the workspace name `<type>: <slug words> (<ID>)`; without both, the branch and the workspace are named after the id alone (`lib/common.sh:79-89`).
- `owned` is a list of globs; `**` crosses directories, `*` stops at a slash and `?` matches one non-slash character (`lib/gate.mjs:59-71`).
- `coordinator: true` exempts a task from the coordinator-owned paths, and nothing else (`lib/gate.mjs:174-177`).
- Plan-level `coordinatorOwned` always wins over a task's `owned` globs, and plan-level `alwaysAllowed` is permitted to every task (`lib/gate.mjs:172-178`).
- The four statuses are `merged`, `no brief`, `waiting on deps` and `ready`, in that order of precedence (`lib/plan.mjs:65`).
- `ready` means not merged, a `brief` path that exists on disk, and every dependency merged (`lib/plan.mjs:62-65`).
- A task counts as merged when the plan says `done: true`, which `skein merge` sets, or when a commit subject in the last 1000 on the base reference ends with `(<ID>)`, optionally followed by a pull request number (`lib/plan.mjs:53-60`).
- The base reference follows the config's `baseBranch`, which defaults to `main`: `origin/<baseBranch>` when an origin remote exists, after a fetch, and the local `<baseBranch>` otherwise (`lib/plan.mjs:49-52`).
- The overlap rule is deliberately conservative: two globs overlap when one's literal prefix up to its first wildcard contains the other's, and two wildcard-free globs overlap only when they are equal (`lib/plan.mjs:40-47`).
- Overlaps are computed among ready tasks only, pairwise, and reported as the shared globs (`lib/plan.mjs:68-73`).
- The reason for the conservatism is stated in the code: a false overlap costs one serialized merge round, a missed one costs a conflict (`lib/plan.mjs:40-41`).

## Config

`.skein/config.json`, committed with the repository. Every key below is read by the code at
the line given; a default of "none" means the code reads it only when it is present.

| key | default | read at |
|---|---|---|
| `version` | `1` as written | written at `commands/init.sh:97`; `require_config` and the gate refuse a config whose version is above the one this kit reads, and one that is not a whole number, saying "this kit understands version 1" (`lib/common.sh:22-35`, `lib/gate.mjs:89-99`); `skein doctor` reports the version and flags the same fault (`commands/doctor.sh:9-10`) |
| `name` | the repository directory name | `commands/status.sh:6`, `commands/dispatch.sh:90`, `commands/doctor.sh:9` |
| `prefix` | `TASK` | `lib/common.sh:54` |
| `mode` | none | `lib/common.sh:60` |
| `envelope` | `<prefix>_WORKER` | `lib/common.sh:55` |
| `coordinatorEnv` | `<prefix>_COORDINATOR` | `lib/common.sh:65` |
| `plan` | `docs/plan/wps.json` | `lib/common.sh:52`, `lib/plan.mjs:26`, `lib/gate.mjs:113` |
| `briefs` | `docs/plan/briefs` | `lib/common.sh:53`, `lib/plan.mjs:27`, `lib/gate.mjs:160` |
| `reviews` | `docs/plan/reviews` | `commands/review.sh:59`, `commands/merge.sh:25` |
| `vendor` | `scripts/skein` | `commands/upgrade.sh:7`, `commands/merge.sh:16`, `commands/merge.sh:47`, `commands/doctor.sh:12` |
| `gate` | `scripts/skein/skein gate` | `commands/dispatch.sh:21`, `commands/brief.sh:18` |
| `baseBranch` | `main` | `commands/dispatch.sh:22`, `commands/merge.sh:16`, `commands/upgrade.sh:16`, `commands/status.sh:55`, `lib/gate.mjs:134`, `lib/plan.mjs:51` |
| `board` | `{type, repo}`; type `github`, or `none` in local mode | `lib/common.sh:63`, `lib/boards/github.sh:16` |
| `driver` | `{type}`; type `superset` | `lib/common.sh:64` |
| `maxAgents` | `6` | `lib/caps.sh:8` |
| `install` | `true` as written | written at `commands/init.sh:100`; rendered into CI and the setup script at init time (`commands/init.sh:132`, `templates/ci.yml.tmpl:26`) |
| `standard` | empty, which fails the check | `lib/gate.mjs:101`, `lib/gate.mjs:274`, `commands/doctor.sh:31` |
| `e2e` | empty, which passes | `lib/gate.mjs:279` |
| `invariants` | empty, which passes | `lib/gate.mjs:249` |
| `monotonic` | empty | `lib/gate.mjs:237` |
| `secretPatterns` | empty | `lib/gate.mjs:197` |
| `secretAllow` | empty | `lib/gate.mjs:204` |
| `worker` | `{agent: claude, model, effort}` | `commands/dispatch.sh:18-20` |
| `review` | `{agent: codex, model, fallbackModel}` | `commands/review.sh:15-16`, `commands/review.sh:19`, `commands/doctor.sh:29` |
| `workerPrompt` | none; the built-in prompt is used | `commands/dispatch.sh:86`, `commands/dispatch.sh:89` |
| `readyMarker` | `workspace '.*' ready` | `lib/drivers/superset.sh:26`, `lib/drivers/local.sh:12` |
| `setupScript` | `.superset/setup.sh` | `lib/drivers/local.sh:14` |
| `setupTimeout` | `300` | `commands/dispatch.sh:78`, `commands/review.sh:34` |
| `setupFatal` | a pattern covering package manager and TypeScript errors | `lib/drivers/superset.sh:27`, `lib/drivers/local.sh:13` |

- Values are read one at a time with `jq`, and an empty or missing value falls back to the default passed at the call site (`lib/common.sh:37-43`).
- `~/.skein/config.json` is the per-machine config, and holds `maxAgents` (default 3) and `projects`, a map from a checkout path to `{supersetProjectId}` (`lib/caps.sh:7`, `lib/drivers/superset.sh:42`).
- `SKEIN_MAX_AGENTS` overrides the machine cap (`lib/caps.sh:7`).
- `SKEIN_PROJECT_ID` overrides the resolved Superset project id (`lib/drivers/superset.sh:40`).
- `SKEIN_DRIVER` overrides `driver.type`, for a machine without Superset (`lib/common.sh:64`).
- `SKEIN_BOARD` overrides `board.type` (`lib/common.sh:63`).
- `SKEIN_USER_CONFIG` overrides the path of the per-machine config (`lib/common.sh:18`).
- `SKEIN_WORKTREES` overrides where the local driver keeps worktrees, default `~/.skein/worktrees` (`lib/drivers/local.sh:10`).
- `SKEIN_RUNS` overrides where the local driver keeps run logs, default `~/.skein/runs` (`lib/drivers/local.sh:11`).
- `SKEIN_STATE_DIR` overrides where `skein watch` keeps its log, snapshot and baseline (`commands/watch.sh:15`).
- `SKEIN_KIT_GIT` tells `skein upgrade` not to pull the kit checkout (`commands/upgrade.sh:9`).
- Three more are read and are not in the README: `SKEIN_BRANCH`, a fallback branch name for the gate's `--from-branch` (`lib/gate.mjs:120`), and `SKEIN_BIN_DIR` with `CLAUDE_SKILLS_DIR` for the installer's destinations (`setup:7-8`).
- The coordinator environment variable named by `coordinatorEnv` is what lets a push to the base branch through the pre-push hook; it is a guard, not a permission system, because anyone can set it (`templates/pre-push.tmpl:8-10`, `templates/pre-push.tmpl:14`).

## Boards and drivers

Every board implements `board_claim`, `board_release`, `board_close`, `board_owner`,
`board_running_count`, `board_list` and `board_comment`, and the type names the file under
`lib/boards/` that is sourced; an unknown type is a refusal (`lib/boards/github.sh:6-13`,
`lib/common.sh:92`).

- **GitHub** is the default outside local mode: one issue per task titled `<ID>: <title>`, labelled `skein`, with the state in a `state:` label (`lib/boards/github.sh:2-4`).
- Assigning yourself is the claim, and an unassigned issue is free (`lib/boards/github.sh:2-3`).
- An issue assigned to someone else is refused, and an issue already `state:running` under your own claim is refused as well (`lib/boards/github.sh:61-66`).
- Claims are checked twice because neither creating an issue nor assigning one is atomic across coordinators: on create, a lower-numbered open issue for the same id wins and ours is closed; on assign, the alphabetically first login wins and we back out (`lib/boards/github.sh:48-55`, `lib/boards/github.sh:70-77`).
- Issues are listed rather than searched, because GitHub's search index lags a fresh create (`lib/boards/github.sh:29-33`).
- `board_release <ID> ready` clears the assignee; `gating` and `blocked` keep the claim (`lib/boards/github.sh:81-88`).
- **Superset** is the organization task queue: one task per skein task, titled the same way, assigned to the claiming user, with labels carrying the state (`lib/boards/superset.sh:2-4`).
- It is best-effort about field names, because the CLI's task JSON has changed before, and reads the assignee from any of three shapes (`lib/boards/superset.sh:4`, `lib/boards/superset.sh:31`).
- It verifies exclusive ownership after the write, as the GitHub board does (`lib/boards/superset.sh:36-38`).
- Its `board_comment` is a no-op (`lib/boards/superset.sh:55`).
- **none** is a single coordinator with no shared claims: every function is a no-op, and the running count comes from the driver, so the repository cap then counts only what this machine runs (`lib/boards/none.sh:2-8`).

Every driver implements `driver_project_id`, `driver_create`, `driver_wait_setup`,
`driver_path`, `driver_launch`, `driver_read`, `driver_send`, `driver_tag`, `driver_delete`,
`driver_find`, `driver_list`, `driver_running_count` and `driver_agent_terminal`
(`lib/drivers/superset.sh:6-18`).

- **Superset** workspaces are Superset worktrees, agents run in Superset terminals, and the coordinator reads and drives them through the CLI, which needs the desktop app running on this machine (`lib/drivers/superset.sh:2-4`).
- Workspaces are created with a local flag, but terminals, agents and workspace reads address a workspace by id alone and Superset routes that to whichever host owns it, so every id-addressed call first proves the workspace is on this host and refuses otherwise (`lib/drivers/superset.sh:20-23`, `lib/drivers/superset.sh:30-37`, commit 7a57fd6).
- The project id is resolved from `SKEIN_PROJECT_ID`, then the per-machine `projects` map, then the checkout path as Superset knows it; failing all three is a refusal (`lib/drivers/superset.sh:39-48`).
- A workspace that already exists is a refusal, so a dispatch never lands in a used workspace (`lib/drivers/superset.sh:56`).
- Setup is polled every three seconds for the readiness marker, and a line matching the fatal pattern ends the wait early (`lib/drivers/superset.sh:61-72`).
- Before launching interactive Claude Code it records the worktree as trusted in the user's Claude configuration, because the trust dialog cannot be answered through terminal sends (`lib/drivers/superset.sh:76-86`, commit 491502c).
- It answers Codex's trust prompt once, then confirms the agent actually started, retyping the launch once before failing loudly (`lib/drivers/superset.sh:98-120`).
- `driver_running_count` counts workspaces of this project tagged `running` on this host (`lib/drivers/superset.sh:129-135`).
- The agent's terminal is the newest live terminal whose title is not a plain shell prompt (`lib/drivers/superset.sh:137-141`).
- **local** needs no Superset: a workspace is a git worktree, the worker is Claude Code headless writing a stream of JSON to a log, and reading the terminal means rendering that log (`lib/drivers/local.sh:2-5`).
- The workspace id is the worktree path and the terminal id is the run log path (`lib/drivers/local.sh:7`).
- Driver state is kept outside the worktree on purpose: anything inside shows as untracked, and a worker chasing a clean tree for the gate deletes it (`lib/drivers/local.sh:29-30`).
- Setup runs synchronously at create time, so the wait only checks the log (`lib/drivers/local.sh:33-35`, `lib/drivers/local.sh:39-44`).
- It runs `claude` only, and refuses any other agent (`lib/drivers/local.sh:50`).
- Deleting a workspace kills the worker's process group, runs the teardown script if there is one, removes the worktree and prunes (`lib/drivers/local.sh:82-90`).
- `driver_running_count` counts run logs whose recorded process is still alive (`lib/drivers/local.sh:100-107`).

## Caps

- There are two caps, with two reasons: the per-machine cap protects this laptop and this seat's usage, and the per-repository cap protects the repository's merge rounds, review throughput and the number of disjoint tasks (`lib/caps.sh:2-5`).
- The machine cap is `SKEIN_MAX_AGENTS`, else `maxAgents` in the per-machine config, else 3 (`lib/caps.sh:7`).
- The repository cap is `maxAgents` in the repository config, else 6 (`lib/caps.sh:8`).
- The local count comes from the driver and counts what this machine runs for this repository; the board count comes from the board and counts claims running anywhere (`lib/caps.sh:10-11`).
- A dispatch must fit under both, and the check prints its reason on stdout either way (`lib/caps.sh:5`, `lib/caps.sh:12-23`).
- Because two coordinators can pass the check together, `skein dispatch` recounts after claiming and releases the claim if the repository is over its cap (`commands/dispatch.sh:71-73`).

## Review

- `skein review` asks a different model to review the pull request in a read-only worktree forked from the branch, headless, and is mandatory for tasks marked `money` or `pii` (`commands/review.sh:2-5`).
- The default reviewer is `codex`, which may be a shim with nothing behind it, so the command proves it runs before using it and otherwise falls back to Claude (`commands/review.sh:17-20`).
- Codex is run non-interactively on purpose: out of quota its interactive screen opens on an upgrade menu that a pasted keystroke could confirm (`commands/review.sh:44-47`).
- The prompt is rendered from `templates/review-prompt.md` with the task id, the pull request or branch, the brief path, the base reference and the task's `money` flag (`commands/review.sh:37`).
- The evidence `skein merge` requires is the HTML comment marker the command writes, because a word in a comment is not evidence (`commands/review.sh:56-57`).
- Outside local mode the marker must come from a repository owner, member or collaborator (`commands/merge.sh:33-35`).
- The coordinator triages each finding on its merits; the command itself never changes code (`commands/review.sh:5`, `commands/review.sh:39`).

## Local mode

- Local mode is on when the config says `"mode": "local"` or when the repository has no origin remote (`lib/common.sh:56-60`).
- In local mode nothing is pushed, there are no pull requests, workspaces fork from the local base branch, and `skein merge` squash-merges locally (`lib/common.sh:56-58`).
- Base references drop the `origin/` prefix and fetches become no-ops (`lib/common.sh:61-62`).
- The board defaults to `none` rather than `github` (`lib/common.sh:63`).
- `skein init` sets `"mode": "local"`, defaults the board to `none`, refuses `--board github`, and writes no CI workflow (`commands/init.sh:39-41`, `commands/init.sh:104`, `commands/init.sh:145-146`).
- The worker prompt tells the worker to leave everything committed on its branch and open no pull request (`commands/dispatch.sh:88-89`).
- `skein dispatch` says to commit the brief and the plan on the base branch first, because the workspace forks from it (`commands/dispatch.sh:38`).
- `skein review` reviews the branch's diff against the base branch and writes its findings, with the marker, to the reviews directory (`commands/review.sh:6-7`, `commands/review.sh:58-60`).
- `skein merge` refuses `--no-gate`, because the flag trusts a CI gate check and local mode has no CI (`commands/merge.sh:23`, commit 0b42055).
- `skein merge` requires the base branch checked out and clean in the coordinator's checkout, squashes there, and pushes nothing (`commands/merge.sh:51-65`, `commands/merge.sh:83-87`).
- `skein doctor` reports local mode instead of checking origin, and fails a `github` board (`commands/doctor.sh:14-17`).
- To leave local mode, add a remote and drop the `mode` key (`commands/init.sh:4-5`).

## Skills

Five Claude Code skills, linked by the installer as `skein-<directory>` under the skills
directory (`setup:13-15`).

- `/skein-init` sets a repository up: it runs `skein init`, interviews the user for the project rules the scaffold cannot detect, fills `AGENTS.md` and the config, and commits (`skills/init/SKILL.md:3`).
- `/skein-brief` writes a backlog-ready brief for one task and registers it in the plan, reading the code first and validating with `skein brief --check` and `skein plan` (`skills/brief/SKILL.md:3`).
- `/skein-coordinate` runs a wave: check the machine, dispatch ready tasks under both caps, watch for envelopes, gate, review `money` and `pii` tasks, merge, and keep the plan true (`skills/coordinate/SKILL.md:3`).
- `/skein-gate` runs the gate for a task and explains any failure with the fix (`skills/gate/SKILL.md:3`).
- `/skein-status` reports what is happening across the flock, read-only: claims on the board, workers on this machine, both caps, and what is ready to dispatch (`skills/status/SKILL.md:3`).
- The skills are the coordinator's; workers do not use them, and their gate is the only check they run (`templates/AGENTS.md.tmpl:43-45`).

## Drift

Where the README or the usage text disagrees with the code, the code is what this file
records. Each bullet cites both sides. What the README used to get wrong went with the
rewrite, so every bullet left is about the usage text built into `bin/skein`.

- The usage text for `init` lists four flags and leaves out `--base` and `--force-templates` (`bin/skein:27` against `commands/init.sh:2-3`, `commands/init.sh:18-19`).
- The usage text for `brief` shows only `--check` and leaves out `--new` (`bin/skein:34` against `commands/brief.sh:2-4`).
- The usage text for `dispatch` leaves out `--effort` and `--allow-overlap` (`bin/skein:37` against `commands/dispatch.sh:2`, `commands/dispatch.sh:11-12`).
- The usage text for `watch` lists four positional arguments; the code takes six, plus `--resume` (`bin/skein:39` against `commands/watch.sh:2`, `commands/watch.sh:9`).
- The usage text for `gate` lists `--only` and `--base` and leaves out `--timeout-min`, `--from-branch` and `--standard-only` (`bin/skein:45` against `lib/gate.mjs:7-9`, `lib/gate.mjs:28`).
- The usage text for `review` leaves out `--agent` and `--model` (`bin/skein:47` against `commands/review.sh:2`, `commands/review.sh:11-12`).
- The usage text for `merge` leaves out `--no-gate` (`bin/skein:48` against `commands/merge.sh:2`, `commands/merge.sh:13`).
- The usage text describes the per-machine config as holding `maxAgents`; the code also reads `projects` from it (`bin/skein:50` against `lib/drivers/superset.sh:42`).
