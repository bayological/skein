# AGENTS.md

Rules for every agent working in this repository. Coordinator-owned: do not edit.

This repo is skein. It is built by several agents in parallel, each in its own workspace
and branch, and every claim is verified by a gate before it merges. The rules below exist so
that parallel work merges cleanly and so that no mistake reaches production, a user, or a
credential.

## Read before you write
1. Your brief: `docs/plan/briefs/<task-id>.md`. It names the paths you own and how you will be
   judged.
2. `docs/plan/wps.json`: which task owns which paths, and what is coordinator-owned.
3. The project rules below, and whatever the brief lists under "Read first".

## The rules

**1. Stay inside your paths.** Change only files matching your task's `owned` globs in
`docs/plan/wps.json`. The `alwaysAllowed` entries there (lockfile, `docs/adr/DRAFT-*.md`) are always
fine. Never edit anything under `coordinatorOwned`: `AGENTS.md`, `.skein/**`,
`scripts/skein/**`, `docs/plan/**`, `.github/**`, the hooks, and the project's frozen paths. If
a shared file seems to need a change, that is a blocker to report, not an edit to make.

**2. Frozen paths are frozen.** The plan's `coordinatorOwned` list names the contract this
project builds against. If it lacks something you need, stop and report `BLOCKED` with the
exact change you propose. The coordinator applies it with a short ADR and tells running
workers to rebase.

**3. Never weaken a test to get green.** No `.skip`, `.only` or `.todo`. No `@ts-nocheck`,
no file-wide lint disables, no widened tolerances. Shared regression suites only grow; the
gate counts them. A failing test is information: fix the code or report the problem.

**4. Secrets.** Never commit `.env` or any credential. Never print, log, or put in an error
message a key, a token, a signing secret, or a user's personal data. Test data is invented.
The gate scans for committed keys; do not rely on it.

**5. Dependencies.** Add one only if your brief's work needs it, and name it in your hand-off.
Prefer what is already here. No install scripts from packages you cannot vouch for.

**6. Stay in scope.** Do what the brief says. Note improvements you spot in your hand-off
instead of making them. Do not refactor another task's code.

**7. Skills and workflows.** The coordinator uses whatever skills it likes; workers do not.
Do not invoke `/ship`, `/review`, `/qa`, or any workflow that merges, bumps versions, or opens
PRs on your behalf. Your gate is `scripts/skein/skein gate <task-id>` and nothing else.

**8. Do not poll GitHub.** Every agent shares API limits. No `gh pr checks --watch`, no loop
around `gh`. The local gate is your evidence; the coordinator watches CI.

## Project rules
This repo is the skein kit itself. The gate that judges you is a copy of the code you are
changing, and the commands you are editing act on GitHub, Superset and live agents.

**9. The source is not the gate.** The kit's source is `bin/`, `commands/`, `lib/`,
`skills/`, `templates/` and `setup`. `scripts/skein/` is a copy of it, vendored by `skein
init`, and it is the gate that judges your task: coordinator-owned, never edited by a task,
never used to try a kit change. Try your change with this worktree's `./bin/skein`; the
`skein` on PATH points at the owner's main checkout, not at your worktree. After a kit
change merges, the coordinator refreshes `scripts/skein/` with `skein upgrade`.

**10. Never point skein at anything real.** Do not run `dispatch`, `watch`, `send`,
`review`, `merge`, `init` or `upgrade` against this repo, any GitHub repo, or a Superset
workspace: they open issues, create workspaces, launch agents, push and merge. Run the kit
only in the throwaway sandbox that `.superset/run.sh` builds (a local bare origin, local
mode, `--board none --driver local`, no network); another shell joins it with
`. "$SANDBOX/env.sh"`. Your gate's e2e step runs that smoke test for you. Outside the
sandbox, `skein upgrade` also runs `git pull` in the owner's kit checkout
(`commands/upgrade.sh:9`).

**11. Never run `./setup` from a workspace.** It points `~/.local/bin/skein` and
`~/.claude/skills/skein-*` at your worktree, which is deleted with the workspace
(`.superset/setup.sh:6-8`).

**12. Scripts commit unsigned, as someone.** The owner's git config signs every commit, so
a script or test that commits on its own (sandbox repos, fixtures) passes
`-c commit.gpgsign=false` and an explicit `user.name` and `user.email`, like `sbgit` in
`.superset/run.sh:38`; otherwise it fails. Your own commits on your branch are ordinary
commits.

**13. The kit is dependency-free.** Bash, Node built-ins, git, jq and gh: nothing to
install, because the gate runs before any install, on whatever `node` is on PATH
(`lib/gate.mjs:5`). No root `package.json`; import only `node:` modules or relative files.
The `node-builtins-only` invariant enforces it. A self-contained app with its own
`package.json` lives in its own directory, and only when its brief says so.

**14. Portable shell.** The kit runs on macOS, with BSD tools and bash 3.2. No
`readlink -f` (`bin/skein:8`), `sed -i`, `grep -P`, `date -d`, `mapfile`, `declare -A` or
`${x,,}`. The `portable-shell` invariant enforces it.

**15. Contracts other repos parse.** Every repo that vendored skein reads the completion
envelope, the `SKEIN_GATE_RESULT` line, the one JSON line each running command ends with
(`lib/common.sh:84-85`), the keys of `.skein/config.json` and the task fields of
`docs/plan/wps.json`. Changing any of them is a coordinator decision with an ADR under
`docs/adr/`: report `BLOCKED` with the change you need.

**16. No project names in the kit.** Code, templates, skills and docs name no client,
employer or other repository (commit 30a586b).

**17. Writing about the gate.** The gate scans every added line of every file, prose
included. `test-integrity` fails on the literal tokens it hunts for (`lib/gate.mjs:212-219`)
and `secrets` on anything shaped like a key (`lib/gate.mjs:171-194`). In docs, describe
them in words and cite the source; never type one out.

## Workflow
1. Read the brief and everything it lists under "Read first".
2. Work in small conventional commits (`feat(scope): …`, `fix(scope): …`, `test(scope): …`)
   on your branch only.
3. Before claiming done, run the gate and make it pass:
   ```bash
   scripts/skein/skein gate <task-id>
   ```
   It checks a clean tree, path ownership, committed secrets, test integrity, the project's
   invariants, then the standard commands, the e2e suite if configured, and your task's
   acceptance commands. The coordinator and CI run the same gate, so a claim it does not
   support will be rejected.
4. Push your branch and open a **draft** pull request. Names say what the work is and carry
   the task id:
   - **your branch** is `<type>/<slug>-<task-id>`, made for you at dispatch;
   - **the pull request title** is a conventional-commit subject with the id at the end:
     `fix(api): JSON 404 for unknown paths (SK-01)`. It becomes the squashed commit on
     `main`, and the plan reads it to know the task merged.

   Never push to `main`, never merge, never force-push a branch that is not yours.
5. End your final message with exactly one envelope.

## Completion envelope
```text
SK_WORKER_DONE
task: <task-id>
summary: <one-line outcome>
pr: <draft PR url>
files: <comma-separated top-level paths, or none>
checks: <the SKEIN_GATE_RESULT line, verbatim>
handoff: <what the next task or the reviewer needs to know, or none>
```
```text
SK_WORKER_BLOCKED
task: <task-id>
reason: <specific blocker>
needs: <the decision, access, contract change or dependency required>
```
Report `BLOCKED` early rather than working around a problem. A precise blocker is a good
outcome; a silent workaround is not.

## Ambiguity
If the architecture or the contract is ambiguous or wrong, do not guess silently. Write
`docs/adr/DRAFT-<task-id>-<slug>.md` stating the context, the decision you took and its
consequences, and mention it in your hand-off. The coordinator numbers it at merge.

## Commands
```bash
scripts/skein/skein gate <task-id> --only standard   # syntax pass over the kit (.skein/config.json "standard")
scripts/skein/skein gate <task-id> --only e2e        # the sandbox smoke test, .superset/run.sh
scripts/skein/skein gate <task-id>
scripts/skein/skein gate <task-id> --only boundary,secrets,test-integrity,invariants   # fast static checks
./bin/skein <command>                                 # this worktree's kit, inside the sandbox only (rule 10)
```
