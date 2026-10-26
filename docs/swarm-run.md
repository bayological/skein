# How skein built its own docs

On 26 October 2026 a skein swarm wrote the docs in this repository: the fact sheet, the two
diagrams, the hello-swarm example, the demo GIF, the limitations page and the README. The
coordinator kept a journal as the run happened, and this page is that journal, edited for
reading. Times are UTC. The plan's own record is [docs/plan/LOG.md](plan/LOG.md), and every
task's brief is in [docs/plan/briefs/](plan/briefs/).

## In short
- Ten tasks went to workers, up to four at once. One of them ran on a different model, to
  fact-check the others.
- All ten passed their own gate before reporting done. Six still needed a fix round, each for
  something no gate check judges.
- A second model checked 171 factual claims and found 3 wrong. All three were fixed before the
  owner read the README.
- One incident, reported by the worker that caused it and contained. Six kit bugs found and left
  for follow-up tasks.
- From the first dispatch to the last merge before the owner's review: 1 hour 24 minutes.

## Setup
- skein was set up on itself with `/skein-init`, from 01:00 to 01:52: `skein init`, then an
  interview for the rules the scaffold cannot detect. It produced three invariants (no em
  dashes in the docs, portable shell for a kit that runs on macOS with bash 3.2, and Node
  built-ins only), a standard step that syntax-checks every script in the kit, and an e2e step
  that runs the sandbox smoke test in `.superset/run.sh`.
- The owner's swarm brief became eleven tasks, SK-00 to SK-10, each with a brief, owned paths,
  dependencies and acceptance commands. Every acceptance command was tested against a passing
  and a failing sample before any dispatch.
- Board: GitHub issues on this repository. Driver: Superset, one workspace per task. Caps: four
  workers on this machine and four on the repository.
- Workers ran Claude Code on claude-opus-5 at high effort. The fact-check, SK-09, ran on
  claude-fable-5-1, a different model from the writers. The coordinator was a Claude Code
  session in a worktree of its own.
- The setup merged as [PR #1](https://github.com/bayological/skein/pull/1) at 01:58.

## Timeline
| Task | What | Dispatched | Worker done | Fix rounds | Merged | Pull request |
|---|---|---|---|---|---|---|
| SK-01 | Fact sheet | 01:59 | 02:07 | 1 | 02:14 | [#3](https://github.com/bayological/skein/pull/3) |
| SK-05 | hello-swarm example | 02:14 | 02:19 | 1 | 02:26 | [#9](https://github.com/bayological/skein/pull/9) |
| SK-07 | Limitations page | 02:14 | 02:22 | 1 | 02:26 | [#8](https://github.com/bayological/skein/pull/8) |
| SK-02 | Architecture diagram | 02:15 | 02:25 | 1 | 02:32 | [#11](https://github.com/bayological/skein/pull/11) |
| SK-03 | Lifecycle diagram | 02:16 | 02:21 | 1 | 02:32 | [#10](https://github.com/bayological/skein/pull/10) |
| SK-06 | Demo GIF | 02:27 | 02:47 | 0 | 02:54 | [#13](https://github.com/bayological/skein/pull/13) |
| SK-04 | README | 02:57 | 03:03 | 1 | 11:34, after the owner's review | [#17](https://github.com/bayological/skein/pull/17) |
| SK-11 | Example: init flags | 02:58 | 03:00 | 0 | 03:01 | [#16](https://github.com/bayological/skein/pull/16) |
| SK-09 | Cross-model fact-check | 03:05 | 03:17 | 0 | 03:20 | [#19](https://github.com/bayological/skein/pull/19) |
| SK-12 | Example: one task per dispatch | 03:21 | 03:22 | 0 | 03:23 | [#21](https://github.com/bayological/skein/pull/21) |

SK-01 ran alone, since everything else cites it. SK-02, SK-03, SK-05 and SK-07 then ran
together, four at once, the cap. SK-06 waited for SK-05, SK-04 for all six, and SK-09 for
SK-04's worker to finish. SK-11 and SK-12 were added during the run, from findings described
below. SK-08, an optional docs site, was not built: the owner kept to the README. SK-00, a test
harness for the kit, stays in the backlog.

The README waited overnight for the owner to read it, and merged at 11:34.

## What the gate judged, and what it could not
Every worker ran the gate before it reported done, and all ten passed. The coordinator ran the
gate again before each merge, in the worker's worktree, and it passed every time.

Six of the ten tasks still needed a fix round, and no gate check could have asked for any of
the fixes:
- **SK-01, the fact sheet:** citations by bare file name, ambiguous where two files share a
  name; a wrong line about another project the README names; and three smaller errors.
- **SK-07, the limitations page:** a citation of a README line number that the README rewrite
  was about to move.
- **SK-05, the example:** a clean-up step that missed where the local driver keeps worktrees
  and run logs, outside the sandbox; and "no network" in a README whose next section runs real
  agents.
- **SK-02 and SK-03, the diagrams:** drawn in parallel, they disagreed on the weight of their
  box titles, which neither brief specified. Two labels carried wording from the coordinator's
  own brief that was wrong or ambiguous.
- **SK-04, the README:** two claims the fact-check found wrong, a sentence that stated as fact a
  rule nothing enforces, a construction the writing rules ban, and three smaller corrections.

The gate settles whether a change stays inside its paths, leaks nothing, keeps its tests and
passes its checks. Whether the change is true, consistent with its neighbours and readable took
a reader: the coordinator, or a different model.

## The cross-model fact-check
SK-09 checked 171 factual claims against the fact sheet and the code: the README on SK-04's
branch, before the owner saw it, plus the limitations page, the example's README and the demo's
README. Of those, 168 were ok, 3 wrong and none unsourced. It measured the GIF and replayed the
example's trap rather than take either on trust. The wrong ones:
1. The README said the installer notes a missing Superset CLI or `codex`. It checks only `git`,
   `node`, `jq` and `gh` (`setup:18`).
2. The README said `skein init` leaves every existing file alone apart from the pre-push hook.
   Each run also copies the vendored runtime afresh, and adds lines to `.gitignore` and
   `knip.json` when they are missing (`commands/init.sh:84-90`, `commands/init.sh:128-131`).
3. The example's README dispatched two tasks in one call. `skein dispatch` takes one, and a
   second task id silently replaces the first (`commands/dispatch.sh:12`).

The first two went back to SK-04's worker, and the third became SK-12. The table is in
[docs/plan/reviews/docs-factcheck.md](plan/reviews/docs-factcheck.md).

## Findings that became tasks
- Building the demo, SK-06's worker found that plain `skein init` in a copy of the example
  renders `AGENTS.md` with a prefix taken from the folder's name, while the config it keeps
  says `HS`. Workers in such a sandbox would end with an envelope `skein watch` never matches.
  The coordinator reproduced it and briefed SK-11, which passes `--name` and `--prefix` in the
  example's README. It merged 2 minutes 47 seconds after dispatch.
- The fact-check's third wrong claim became SK-12, merged 2 minutes 26 seconds after dispatch.

## An incident
While testing the demo's setup script, SK-06's worker sourced it from a zsh session, where
`BASH_SOURCE` is empty. The script resolved the wrong directory, its `cd` into the sandbox
failed, and the rest of it ran inside the worker's own worktree. The script then made two
unsigned commits under the demo's identity, re-rendered the pre-push hook, and wrote three keys
into the repository's git config, which every worktree on the machine shares: commit signing
off, a user name and an email address.

The worker noticed, reset its branch, restored the hook, removed the three keys and reported
all of it in its hand-off. Nothing was pushed. The coordinator checked each claim: the shared
config held none of the keys, the hook matched `main`, the branch's history started at the
dispatch commit, and every commit on `main` carried the owner's identity, with the
coordinator's own commits signed.

The cause was in the coordinator's brief, which asked for a sourced script that runs
`git config` and commits after a `cd`, with nothing to stop it when the `cd` failed. The script
now refuses to run outside bash, checks the kit's path, and builds the sandbox in a subshell
that stops at the first error.

## Kit bugs found, not fixed
The docs run changed no kit code. These are now briefed as follow-up tasks.
- `skein init` without `--name` and `--prefix` derives both from the directory name even when
  it keeps an existing `.skein/config.json`, and renders `AGENTS.md` and the pre-push hook from
  them (`commands/init.sh:23-24`). Run again from a worktree, it rewrites the hook's coordinator
  variable. Its closing summary also reports the derived values and the default driver rather
  than the kept config's (`commands/init.sh:137`).
- `skein dispatch` given two task ids dispatches only the last (`commands/dispatch.sh:12`).
- The gate's default base and the plan's merge detection read `main` whatever `baseBranch`
  says (`lib/gate.mjs:121`, `lib/plan.mjs:48`).
- Nothing refuses a dispatch of two tasks whose owned paths overlap. `skein plan` reports the
  overlap and stops there (`commands/dispatch.sh:34-83`).
- `skein status` lists the coordinator's own Superset workspace among the workers, as done and
  awaiting the gate, because its terminal shows envelopes the coordinator has read.
- The config key `version` is written by `skein init` and read by nothing
  (`commands/init.sh:73`).

## What the coordinator got wrong
- Two labels in the lifecycle diagram's brief were wrong or ambiguous, and the worker drew them
  as written.
- The diagram briefs fixed colour, corner radius and strokes but not font weight, so the pair
  came back mismatched.
- The demo's brief invited the incident above.
- The demo's acceptance step searched the GIF's bytes for personal paths, and that search cannot
  see text drawn into frames. The coordinator checked the frames by eye instead.
- One acceptance command in the fact sheet's task treated a hyphen as a word boundary. Testing
  every command against a failing sample caught it before dispatch.

## Other things seen
- Workers read the owner's user-level instructions as well as the repository's. Those told every
  session to keep a personal task note current, so workers edited a note outside the repository,
  despite a line in the note asking them not to. The coordinator restored it each time.
  Instructions outside the repository reach workers too.
- An idle worker's terminal shows Claude Code's suggested next prompt, and once showed a dialog
  about compacting. Neither swallowed a message in this run, but a dialog can take the next line
  `skein send` delivers.
