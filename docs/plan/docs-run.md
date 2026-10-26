# Docs run: shared rules for SK-01 to SK-10

Every task in this run reads this file in full before it starts. It carries the parts of the
owner's swarm brief (25 Oct 2026, written against skein v0.1.3, commit 0b42055) that a worker
needs. Coordinator-owned: do not edit it.

## Goal
Make github.com/bayological/skein understandable in two minutes to someone skimming it, such
as a CTO or a developer deciding whether to try it, without changing how skein works.

Deliverables: a README upgrade (SK-04), two diagrams (SK-02, SK-03), a runnable example
(SK-05), a demo recording (SK-06), a limitations page (SK-07), an optional static docs site
(SK-08), a cross-model fact-check (SK-09), and a run log of this swarm (SK-10), so the docs
can say honestly that a skein swarm built them.

## Ground rules
1. **Three sources and nothing else:** the code in this repo; the existing `README.md` and the
   commit history; the owner facts below. Once SK-01 merges, later tasks cite
   `docs/facts/FACTS.md`, the README and the owner facts only. No invented features, numbers,
   users, benchmarks or quotes. When you need something no source gives, write
   `[OWNER: <what is needed>]` in the copy and list every marker under `handoff:` in your
   envelope.
2. **Do not change behaviour.** No docs task touches `bin/`, `commands/`, `lib/`, `skills/`,
   `templates/` or `setup`; your owned paths enforce it. If you find a bug, describe it under
   `handoff:` with `path:line`. The coordinator records it in the run log (SK-10). Leave the
   code alone.
3. **Writing rules for all new copy:**
   - Plain British English, short sentences.
   - Match the existing README's voice: terse, concrete, no marketing words.
   - No em dashes. The gate's `no-em-dash-in-docs` invariant fails an added line that has
     one, but it skips lines starting with `#` or `*`, so your accept step also greps.
   - No sentence that starts "That's".
   - No "X is what Y" constructions.
   - No punchy contrast pairs ("not X, but Y").
   - Never "simply", "seamless", "powerful", "robust" or "blazing".
4. **No project names.** Commit 30a586b took project names out of the kit, and the convention
   stands (AGENTS.md rule 16): README, site and example copy name no client, employer or other
   project. The owner facts say how to refer to the one story that needs it.
5. **No publishing.** Never push to GitHub Pages, never enable Pages, never post anywhere. The
   owner enables Pages.
6. **Demo and example safety.** Run skein only in a throwaway sandbox, the way
   `.superset/run.sh` does: a local bare origin, local mode, no GitHub, no network
   (AGENTS.md rule 10). Recordings must not show a home path, a token, an email address or a
   real repository.
7. **Owner gate.** The coordinator does not merge SK-04 or SK-08 until the owner has read the
   diff and said yes in the coordinator session.

## Owner facts (allowed in copy)
- skein grew out of swarm setups used across several repos (`README.md:8-10`).
- Why it exists:
  - In March 2026 the owner ran an AI QA agent, with its own GitHub account, on four real
    repositories for 15 days.
  - It opened 21 fix pull requests. 6 were merged, including one that raised test coverage
    on a core service from 42% to 90% and added CI coverage gates. 15 were closed.
  - The closed ones are the reason for the principle "A worker's claim is not evidence".
- In "Why it exists", say "a production codebase". Do not name the employer or any project.
- Superset is a third-party tool that skein drives through its CLI. Describe it only the way
  `README.md` already does.

## Repository facts, checked against the code
The owner's brief listed these from v0.1.3. They were checked against the code on 25 Oct
2026, and where the brief and the code differ, the code wins. SK-01 verifies every line again
and records the result in `docs/facts/FACTS.md`.
- **Commands** (`commands/*.sh`): init, upgrade, doctor, plan, brief, dispatch, watch, status,
  send, gate, review, merge. The usage text in `bin/skein:20-52` leaves out several flags:
  `init --base` and `--force-templates`, `dispatch --effort`, `review --agent` and `--model`,
  `merge --no-gate`, and `gate --timeout-min`, `--from-branch` and `--standard-only`. Read each
  command's header comment and argument parsing, not the usage text.
- **Gate** (`lib/gate.mjs`, `commands/gate.sh`): the checks run in this order
  (`lib/gate.mjs:27`, `276-285`): brief, clean-tree, boundary, secrets, test-integrity,
  invariants, standard, e2e, accept. Monotonic counts are part of test-integrity
  (`lib/gate.mjs:223-229`), not a step of their own, and the brief check comes first. The
  owner's brief listed them differently; use the code's order. The worker and the coordinator
  run every check. CI runs a subset: on a pull request
  `--only brief,boundary,secrets,test-integrity,invariants,standard,accept`, and on a push to
  the base branch the standard commands only (`templates/ci.yml.tmpl:27-32`). The gate is
  vendored into each repo and coordinator-owned there (`lib/gate.mjs:2-5`).
- **Plan:** `docs/plan/wps.json`. Each task has `owned` globs, `deps`, `accept` commands, and
  `money`/`pii` flags. `skein plan` shows what is ready and which ready tasks overlap
  (`lib/plan.mjs`).
- **Board:** GitHub issues by default, Superset tasks, or none (`lib/boards/`, `lib/common.sh:49`).
  Assigning yourself is the claim (`lib/boards/github.sh:1-4`).
- **Drivers:** `lib/drivers/superset.sh` refuses to drive a workspace that is not on this host
  (`lib/drivers/superset.sh:20-37`, commit 7a57fd6). `lib/drivers/local.sh` uses git worktrees
  plus Claude Code headless (`lib/drivers/local.sh:1-5`).
- **Review:** `skein review` asks a different model to review the PR in a read-only worktree.
  It uses `codex` and falls back to Claude when `codex` cannot run (`commands/review.sh:17-20`).
  `skein merge` requires the review for money and pii tasks (`commands/merge.sh:21-36`).
- **Local mode:** no origin remote, or `"mode": "local"` (`lib/common.sh:42-47`). `skein init`
  then sets board none and skips CI (`commands/init.sh:20-22`, `121-122`), `skein merge`
  squashes locally (`commands/merge.sh:51-65`) and refuses `--no-gate`
  (`commands/merge.sh:23`, commit 0b42055).
- **Skills:** /skein-init, /skein-brief, /skein-coordinate, /skein-gate, /skein-status
  (`skills/*/SKILL.md`, linked by `setup:13-15`).
- **Config:** the README table (`README.md:79-99`) covers the main keys. The code reads more:
  `version`, `envelope`, `coordinatorEnv`, `plan`, `briefs`, `reviews`, `vendor`, `gate`,
  `baseBranch`, `readyMarker`, `setupScript`, `setupTimeout` and `setupFatal`
  (`commands/init.sh:72-80`, and `cfg` calls across `commands/` and `lib/`).

## What the gate does to docs
The gate reads every added line of every file, prose included (AGENTS.md rule 17):
- **test-integrity** (`lib/gate.mjs:212-222`) fails a line that contains any token it hunts
  for: the TypeScript pragmas that switch off or suppress checking, a file-wide ESLint
  disable comment, a focused or skipped test call, Rust's ignore attribute, or Python's skip
  markers. "Focused or skipped" includes `xit`, `fit`, `xdescribe` and `fdescribe` followed by
  an opening bracket, so the English word "fit" followed by a bracket fails too. Describe the
  tokens in words and cite `lib/gate.mjs:212-219`; never type one out.
- **secrets** (`lib/gate.mjs:171-210`) fails a line shaped like a real key: a PEM private-key
  header, an AWS access key id (AWS's published example key included), a Stripe-style
  secret key with its full tail, and the rest of that list. Describe the patterns in words.
- **no-em-dash-in-docs** (`.skein/config.json`) fails an added line with an em dash in
  `README.md`, `docs/` (except `docs/facts/`, `docs/plan/`, `docs/adr/`) and `examples/`.

## Tasks and order
| ID | Task | Owned | Deps | Notes |
|---|---|---|---|---|
| SK-01 | Fact sheet | `docs/facts/FACTS.md` | none | |
| SK-02 | Architecture diagram | `docs/assets/architecture.*` | SK-01 | |
| SK-03 | Task lifecycle diagram | `docs/assets/lifecycle.*` | SK-01 | |
| SK-05 | Example repo | `examples/hello-swarm/**` | SK-01 | |
| SK-07 | Limitations page | `docs/limitations.md` | SK-01 | |
| SK-06 | Demo recording | `docs/demo/**`, `docs/assets/demo.*` | SK-05 | |
| SK-11 | Example init flags | `examples/hello-swarm/**` | SK-05, 06 | follow-up from SK-06; runs beside SK-04 |
| SK-04 | README upgrade | `README.md` | SK-01, 02, 03, 05, 06, 07 | owner gate |
| SK-09 | Fact-check review | `docs/plan/reviews/docs-factcheck.md` | as SK-04, plus SK-11 | reviews SK-04's branch |
| SK-08 | Docs site (optional) | `docs/site/**`, `.github/workflows/pages.yml` | SK-04 | owner gate; briefed later |
| SK-10 | Swarm run log | `docs/swarm-run.md` | all | the coordinator writes it |

SK-02, SK-03, SK-05 and SK-07 run together once SK-01 merges.

## Owner checkpoints
- **SK-09 before SK-04 merges.** SK-04's worker finishes and its gate passes; then SK-09 (a
  different model from the writers) fact-checks the README on SK-04's branch, plus
  `docs/limitations.md`, `examples/hello-swarm/README.md` and `docs/demo/README.md` on `main`.
  Every "wrong" verdict
  goes back to SK-04's worker as a fix before the owner reads anything.
- **Owner review, before SK-04 (and SK-08) merge:**
  - Read the README diff top to bottom. Could you explain every sentence to a CTO?
  - Watch the demo GIF and confirm it shows the gate catching the bad task.
  - Check `docs/limitations.md`, and add what really goes wrong.
  - Read `docs/plan/reviews/docs-factcheck.md`.
  - Merge, then enable Pages in the repo settings if you want the site live.
- **SK-08** is briefed only if SK-04 merges cleanly and the owner still wants the site.
- **SK-10** is written by the coordinator from the board, `docs/plan/LOG.md` and the gate
  results: the tasks, how many ran in parallel, each gate failure (which check, which task,
  how it was fixed), review findings, merges, total wall-clock time, and anything that needed
  a human. No embellishment. Once it exists, the README's last line points to it.
