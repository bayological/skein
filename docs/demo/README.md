# The demo recording

`docs/assets/demo.gif` is one wave of a skein swarm, about 70 seconds of terminal. It runs
the example repository in `examples/hello-swarm/` inside a throwaway sandbox.

What it shows, in order:

1. `skein plan`: three tasks. HS-01 and HS-02 are ready and own different files, so they can
   run together. HS-03 waits for both.
2. `skein dispatch HS-01` and `skein dispatch HS-02`: a git worktree and a branch for each
   task, then a worker in each one.
3. `skein status`: both workers report done, awaiting gate. The view is what the workers say
   about themselves, and it settles nothing.
4. The gate, run in HS-02's worktree the way the coordinator runs it. `test-integrity` fails:
   HS-02 deleted the two tests its change broke, so the count of test declarations in
   `test/greet.test.mjs` fell from three to one. The remaining checks are skipped.
5. `skein send HS-02 "..."`: the same worker session is resumed with the failure. It puts the
   three tests back with the new expected values, and the gate ends `status=PASS`.
6. `skein merge HS-01` and `skein merge HS-02`: each merge reruns the gate in the worker's
   worktree, squashes the branch onto `main` and records the task as done. `skein plan` then
   shows HS-03 ready.

HS-02 reported `checks: not run` and claimed the suite was green. The gate disagreed. A
worker's claim is not evidence.

## Worker commits scripted for the recording

The workers in the GIF are not models. `docs/demo/claude` sits on the sandbox `PATH` under
the name the local driver launches (`lib/drivers/local.sh:48-58`) and answers the same
interface: it makes the round's commit, writes a completion envelope into the stream-json log
the driver reads, and runs again when `skein send` resumes its session id. Each round's edit
is a script in `docs/demo/work/`:

| Script | What it does |
|---|---|
| `HS-01.sh` | adds `src/farewell.mjs` and three tests for it |
| `HS-02.sh` | makes the formal greeting change, then deletes the two tests it breaks |
| `HS-02-fix.sh` | puts the three tests back, with the new expected values |

The recording therefore costs nothing, needs no account and plays the same way every time.
Everything else in it is skein doing its own work: the plan, the dispatches, the worktrees,
the gate and the merges.

`docs/demo/gh` is the other stand-in. The kit asks `gh api user` for the coordinator's login
when it records a claim or a merge (`lib/common.sh:82`). Answering that inside the sandbox
keeps the run off the network and a real account out of the recording.

## Re-recording it

From the repository root:

```bash
vhs docs/demo/demo.tape
```

It needs `vhs`, `ttyd` and `ffmpeg` on `PATH`, and takes about two minutes. The tape writes
`docs/assets/demo.gif`.

`docs/demo/setup.sh` builds the sandbox first, while the recording is hidden. It copies
`examples/hello-swarm/` to `/tmp/skein-demo/repo` (`SKEIN_DEMO_DIR` moves it elsewhere),
leaves it without an origin remote and runs `skein init` there. With no remote, skein is in
local mode: board `none`, driver `local`, no pull requests, nothing pushed (AGENTS.md rule
10). The sandbox also holds the worktrees, the run logs and the per-machine config, so no
path under your home reaches the screen.

Delete `/tmp/skein-demo` when you are done. The next recording rebuilds it.
