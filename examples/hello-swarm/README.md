# hello-swarm

A tiny repository, already set up for skein, for trying the kit without pointing it at
anything that matters. It holds one function, three tests, a three task plan and a brief per
task. Two of the tasks can run at the same time. The third waits for both.

One of the parallel tasks carries a trap. Its obvious shortcut is to delete the tests that
its change breaks, and the gate catches that.

## What is in it

| Path | What it holds |
|---|---|
| `package.json`, `package-lock.json` | one package, no dependencies, `npm test` runs `node --test` |
| `src/greet.mjs`, `test/greet.test.mjs` | `greet(name)` and its three tests |
| `.skein/config.json` | local mode, board `none`, driver `local`, prefix `HS`, one `monotonic` rule |
| `docs/plan/wps.json` | the three tasks, their `owned` globs, `deps` and `accept` commands |
| `docs/plan/briefs/HS-0N.md` | one brief per task |

The tasks:

| ID | Task | Owns | Deps |
|---|---|---|---|
| HS-01 | farewell function | `src/farewell.mjs`, `test/farewell.test.mjs` | none |
| HS-02 | formal greeting | `src/greet.mjs`, `test/greet.test.mjs` | none |
| HS-03 | command line entry | `bin/hello.mjs`, `test/cli.test.mjs` | HS-01, HS-02 |

HS-01 and HS-02 own different files, so `skein plan` reports no overlap and both can be
dispatched in the same wave. HS-03 reads both functions, so it waits.

## Run it in a sandbox

Copy the example out of this repository first. A copy with no origin remote runs in local
mode: no board, no pull requests, nothing pushed. Run skein only against such a copy.

```bash
sandbox=$(mktemp -d)
cp -R examples/hello-swarm/. "$sandbox"/
cd "$sandbox"
git init -q -b main
git add -A && git commit -qm "example: hello-swarm"
```

Now scaffold the parts the example does not ship. `skein init` keeps the config and the plan
that are already here, and adds the vendored runtime under `scripts/skein/`, `AGENTS.md`, the
coordinator notes in `docs/plan/` (`COORDINATOR.md` and `COORDINATOR-PROMPT.md`), the pre-push
hook and the workspace lifecycle scripts. Local mode writes no CI workflow. It takes the name,
prefix, board and driver from the `.skein/config.json` already here, so the command needs no
flags, and it refuses a flag that contradicts that config unless `--force-templates` is passed
to rewrite it.

```bash
skein init
git add -A && git commit -qm "chore: skein init"
skein plan
```

`skein plan` prints:

```text
plan: docs/plan/wps.json  (3 tasks, 2 ready, 0 merged)

HS-01  ready            farewell function
HS-02  ready            formal greeting
HS-03  waiting on deps  command line entry  deps=HS-01,HS-02

no ownership overlaps among ready tasks: they can run together.
```

`skein brief HS-01 --check` validates a brief against its task. All three pass.

## The trap in HS-02

HS-02 changes `greet(name)` from `Hello, <name>!` to `Good day, <name>.`. All three tests in
`test/greet.test.mjs` fail on the first run. One route is to update the expected value in
each. The cheaper route is to delete the two awkward ones and keep the one that was easy to
fix.

`.skein/config.json` has a `monotonic` rule on that file, so the gate counts the test
declarations in it before and after. Take the shortcut, and `skein gate HS-02` prints:

```text
[FAIL] test-integrity
       test/greet.test.mjs: count of /\btest\(/ fell from 3 to 1: shared suites only grow

       AGENTS.md: never weaken a test to get green.
```

The `standard`, `e2e` and `accept` steps are then skipped, and the run ends:

```text
SKEIN_GATE_RESULT task=HS-02 base=main status=FAIL checks=brief:PASS,clean-tree:PASS,boundary:PASS,secrets:PASS,test-integrity:FAIL,invariants:PASS,standard:SKIP,e2e:SKIP,accept:SKIP
```

Restore the three tests, update their expected values, and the same command ends
`status=PASS` with all nine checks green. The tests were the only evidence of what `greet`
promised, so the gate treats a suite that shrank as a failure whatever the reason. A worker's
claim of green counts for nothing on its own.

Try it yourself in the sandbox:

```bash
git checkout -b feat/formal-greeting-HS-02
# edit src/greet.mjs, then cut test/greet.test.mjs down to one test
git add -A && git commit -qm "feat(greet): formal greeting (HS-02)"
scripts/skein/skein gate HS-02
```

## Dispatching real agents

`skein dispatch HS-01`, then `skein dispatch HS-02`: each call takes one task id. With the
`local` driver a call creates a git worktree for its task and starts a Claude Code session in
it, headless, against your account. The sessions write code, run the gate and report back.
Expect real token spend and real wall-clock time.

For a run you can watch without that, see `docs/demo/` in this repository. Its worker commits
are scripted, so the recording is repeatable and costs nothing.

## Clean up

With nothing dispatched, everything lives in the copy, including the `core.hooksPath` setting
that `skein init` writes to the sandbox repository. Deleting the directory is enough.

A dispatch puts two things outside it. The local driver keeps each task's worktree under
`~/.skein/worktrees` and its run log under `~/.skein/runs`, both in a folder named after the
repository's directory, which here is the name of the sandbox folder. `skein merge` removes a
merged task's worktree and leaves its run log.

```bash
name=$(basename "${sandbox:?}") && rm -rf "$sandbox" ~/.skein/worktrees/"$name" ~/.skein/runs/"$name"
```

Keep the `:?` guard. Without it an unset `sandbox` leaves `~/.skein/worktrees` as the whole
argument, and the command takes every other project's worktrees with it.
