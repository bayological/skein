# Cross-model fact-check of the docs

Reviewed: `README.md` at the head of SK-04's branch `docs/readme-upgrade-sk-04` (f70f30f);
`docs/limitations.md`, `examples/hello-swarm/README.md` and `docs/demo/README.md` at `main`
(e88b156); `docs/site/` does not exist on `main`. Reviewer: claude-fable-5-1, a different
model from the writers. Sources: `docs/facts/FACTS.md` and the code at e88b156, and the owner
facts in `docs/plan/docs-run.md`. Where a row says "replayed", the claim was checked by copying
`examples/hello-swarm` into a scratch directory, committing it, and running `lib/plan.mjs` and
`lib/gate.mjs` there with no network and no `skein init`.

| claim | source | verdict | fix |
|---|---|---|---|
| README.md:3-6: skein runs many coding agents in parallel, each in its own worktree, under any number of coordinators, with one merge gate deciding what is done. | README.md:3-6 on main, verbatim; lib/drivers/local.sh:2; lib/gate.mjs:2-4 | ok | |
| README.md:8-10: it packages the swarm setup that grew across several repos (a Superset workspace per task, a coordinator that briefs and gates, workers that never merge) into a kit installed once and vendored into each repo, the way gstack does. | README.md:8-10 on main, verbatim; owner facts in docs/plan/docs-run.md ("grew out of swarm setups used across several repos"); commands/init.sh:84-90 | ok | |
| README.md:12: the architecture diagram shows coordinators, the board, the plan, workers in worktrees, the gate, review and merge. | docs/assets/architecture.svg text labels: coordinator, board, plan, workers in parallel each with a worktree of its own, gate, cross-model review, skein merge | ok | |
| README.md:16-17: in March 2026 an AI QA agent with its own GitHub account ran for 15 days against four repositories of a production codebase. | owner facts, docs/plan/docs-run.md "Why it exists"; "a production codebase" is the wording the owner asked for | ok | |
| README.md:17: it opened 21 fix pull requests and 6 were merged. | owner facts, docs/plan/docs-run.md | ok | |
| README.md:17-18: one merged pull request took test coverage on a core service from 42% to 90% and added CI coverage gates. | owner facts, docs/plan/docs-run.md | ok | |
| README.md:18-19: the other 15 were closed. | owner facts, docs/plan/docs-run.md | ok | |
| README.md:19-20: the closed ones are the reason for the rule "A worker's claim is not evidence". | owner facts, docs/plan/docs-run.md | ok | |
| README.md:24: `skein gate <ID>` runs nine checks in order. | lib/gate.mjs:27, 276-285; FACTS.md:185-186 | ok | |
| README.md:24-27: the checks are a brief, a clean tree, path ownership, no committed credential, no weakened test and no shrunk shared suite, the repo's invariants, the standard commands, an optional e2e suite, the task's acceptance commands. | lib/gate.mjs:27, 145-273; FACTS.md:190-198 | ok | |
| README.md:27-29: the worker runs the gate before claiming done, the coordinator before merging, and CI runs a subset of it on every PR. | lib/gate.mjs:2-4; templates/ci.yml.tmpl:27-29; FACTS.md:140, 215 | ok | |
| README.md:29-30: the gate is vendored and coordinator-owned, so a worker cannot weaken the gate it is judged by. | lib/gate.mjs:2-4; FACTS.md:218 | ok | |
| README.md:31-32: `docs/plan/wps.json` is the task DAG, with each task's `owned` globs, `deps`, `accept` commands and money/pii flags. | lib/plan.mjs:2-3, 165-170; lib/gate.mjs:157, 270; commands/merge.sh:21; FACTS.md:222 | ok | |
| README.md:32-33: `skein plan` prints what is ready and which ready tasks overlap. | lib/plan.mjs:172-177, 204-213; FACTS.md:71-72 | ok | |
| README.md:33: parallelism stays safe because no two tasks own the same file. | README.md:21 on main; templates/wps.json.tmpl:8; a convention the plan reports (lib/plan.mjs:173-177) and the boundary check enforces per task (lib/gate.mjs:156-169), not a refusal at dispatch (docs/limitations.md:30) | ok | |
| README.md:34-35: claims live on GitHub issues (the default outside local mode), Superset tasks, or nowhere for a solo run. | lib/common.sh:49; lib/boards/github.sh:2-4; lib/boards/superset.sh:2-4; lib/boards/none.sh:2-3; FACTS.md:293, 301, 305 | ok | |
| README.md:35: assigning yourself is the claim. | lib/boards/github.sh:2-3, 67; FACTS.md:294 | ok | |
| README.md:35-36: any number of coordinators, no fixed owner. | lib/boards/github.sh:45-55, 70-77 settle a claim between coordinators; README.md:23-24 on main | ok | |
| README.md:37-38: the machine cap lives in `~/.skein/config.json`, default 3. | lib/caps.sh:7; FACTS.md:331 | ok | |
| README.md:37-38: the repo cap lives in `.skein/config.json`, default 6. | lib/caps.sh:8; FACTS.md:332 | ok | |
| README.md:38-39: the repo cap is counted across all coordinators through the board. | lib/caps.sh:10-11, 101; lib/boards/github.sh:100-102; with board none the count comes from the driver (lib/boards/none.sh:8) | ok | |
| README.md:39: a dispatch has to fit under both caps. | lib/caps.sh:5, 102-107; commands/dispatch.sh:57 | ok | |
| README.md:40-41: the drivers are Superset (workspaces, agents, terminals through its CLI) or local (git worktrees plus Claude Code headless), behind one interface. | lib/drivers/superset.sh:2-18; lib/drivers/local.sh:2-5; FACTS.md:312, 322 | ok | |
| README.md:42-43: the commands are init, upgrade, doctor, plan, brief, dispatch, watch, status, send, gate, review and merge. | commands/ holds exactly those twelve scripts; FACTS.md "Commands" | ok | |
| README.md:43-44: the skills are /skein-init, /skein-brief, /skein-coordinate, /skein-gate and /skein-status. | skills/init, brief, coordinate, gate, status; setup:13-15; FACTS.md:364-371 | ok | |
| README.md:49: the kit is cloned from github.com/bayological/skein into `~/.claude/skills/skein`. | README.md:31 on main; docs/plan/docs-run.md "Goal" names the repository | ok | |
| README.md:50: `setup` registers the skills and links `~/.local/bin/skein`. | setup:13-16; FACTS.md:16 | ok | |
| README.md:52: every command needs `git`, `node` and `jq`. | lib/common.sh:3; FACTS.md:11 (the code's own comment; the bare `skein --version` needs none of them, bin/skein:54-60) | ok | |
| README.md:52: `gh` is for the GitHub board and for pushing work. | lib/boards/github.sh:15; commands/merge.sh:11, 29, 71; commands/review.sh:9; FACTS.md:12, 391 ("pushing work" means the pull-request side; the kit itself pushes with git, commands/merge.sh:77, 87) | ok | |
| README.md:53: Superset's CLI is for the Superset driver. | lib/drivers/superset.sh:25; also the Superset board, lib/boards/superset.sh:7; FACTS.md:13 | ok | |
| README.md:53-54: `codex` is for cross-model reviews and falls back to Claude. | commands/review.sh:17-20; FACTS.md:14 | ok | |
| README.md:54: the installer prints a note for a missing one of those rather than stopping. | setup:18 checks `git`, `node`, `jq` and `gh` only; it never looks for Superset's CLI or `codex` (FACTS.md:10) | wrong | Name the four: "The installer checks for `git`, `node`, `jq` and `gh`, and prints a note for a missing one rather than stopping; it does not look for Superset's CLI or `codex`" (setup:18). |
| README.md:56-57: a copy with no origin remote is in local mode: no board, no pull requests, nothing pushed. | lib/common.sh:42-49; FACTS.md:350-353 | ok | |
| README.md:60-64: the sandbox is a `mktemp -d` copy of `examples/hello-swarm/.`, initialised with `git init -q -b main` and one commit. | examples/hello-swarm/README.md:37-41; replayed | ok | |
| README.md:65: `skein init --name hello-swarm --prefix HS` scaffolds the copy. | commands/init.sh:14-16; the example ships its config and plan, which init keeps (commands/init.sh:68, 102, 118) | ok | |
| README.md:70-71: `skein plan` prints three tasks, two ready and dispatchable together, a third waiting on both. | examples/hello-swarm/docs/plan/wps.json:76-130; lib/plan.mjs:204-213; replayed: "3 tasks, 2 ready, 0 merged" and HS-03 "waiting on deps" | ok | |
| README.md:71: one of the ready pair carries a trap, and the gate catches it. | examples/hello-swarm/.skein/config.json:26-31; lib/gate.mjs:223-229; replayed: test-integrity fails on the trimmed suite | ok | |
| README.md:72: the walk-through and the clean-up are in examples/hello-swarm. | examples/hello-swarm/README.md:31-133 | ok | |
| README.md:78: `skein init` can also be run through the /skein-init skill, which interviews you. | skills/init/SKILL.md:3; FACTS.md:367 | ok | |
| README.md:80-82: init writes `.skein/config.json`, vendors the runtime into `scripts/skein/`, and adds `AGENTS.md`, `docs/plan/` (runbook, coordinator prompt, onboarding, the plan), a CI workflow, a pre-push hook and Superset lifecycle scripts. | commands/init.sh:67-90, 114-127; FACTS.md:27 | ok | |
| README.md:82: the pre-push hook refuses the base branch. | templates/pre-push.tmpl:14-19, unless the coordinator variable is set (FACTS.md:288) | ok | |
| README.md:83: existing files are left alone, apart from the pre-push hook, which is rendered every run. | commands/init.sh:85-90 rewrites the vendored runtime every run (FACTS.md:38); commands/init.sh:128 appends to `.gitignore` and 130-131 edits `knip.json` when it exists (FACTS.md:41) | wrong | "Existing rendered files are left alone. The vendored runtime and the pre-push hook are rewritten every run, and init appends one line to `.gitignore` (and the vendor glob to `knip.json` when that file exists)" (commands/init.sh:85-90, 123, 128-131). |
| README.md:83-84: in local mode init writes no CI workflow. | commands/init.sh:121-122; FACTS.md:40 | ok | |
| README.md:86-87: day to day you paste `docs/plan/COORDINATOR-PROMPT.md` into a session and the coordinator runs the commands. | commands/init.sh:116 renders the prompt; skills/coordinate/SKILL.md:3 names a session started from it; templates/AGENTS.md.tmpl:43 keeps the skills with the coordinator | ok | |
| README.md:89: the GIF shows the plan, two dispatches, both workers reporting done, the gate failing on deleted tests, the fix, and two merges. | docs/demo/demo.tape:31-70; docs/demo/work/HS-02.sh:57-78 | ok | |
| README.md:91: the GIF is about 70 seconds of terminal. | docs/assets/demo.gif measures 74.5 seconds (1863 frames, by ffprobe and identify) | ok | |
| README.md:91-93: it shows `skein plan`, two dispatches, both workers reporting done, the gate failing HS-02 because it deleted the two tests its change broke, `skein send` with the failure, then two merges. | docs/demo/demo.tape:34-65; docs/demo/work/HS-02.sh; docs/demo/README.md:8-21 | ok | |
| README.md:93-95: the worker commits are scripted, which docs/demo/README.md explains along with the two stand-ins that keep the run off the network. | docs/demo/README.md:26-46; docs/demo/claude; docs/demo/gh | ok | |
| README.md:100: /skein-brief writes `docs/plan/briefs/<ID>.md` and the plan entry, with you. | skills/brief/SKILL.md:3; FACTS.md:368 | ok | |
| README.md:101: `skein dispatch` claims on the board, creates the workspace, waits for setup and launches the worker. | commands/dispatch.sh:3; FACTS.md:89 | ok | |
| README.md:102: `skein watch` waits for the worker's completion envelope. | commands/watch.sh:3-6; FACTS.md:104 | ok | |
| README.md:103: `skein gate` runs static checks, standard, e2e and accept, for the worker and then the coordinator. | lib/gate.mjs:2-4, 27; FACTS.md:140 | ok | |
| README.md:104: `skein review` is a cross-model review in a read-only worktree, for money/pii tasks. | commands/review.sh:2-5; commands/merge.sh:21-36; FACTS.md:154, 339 | ok | |
| README.md:105: `skein merge` gates again, squash-merges, closes the claim and deletes the workspace. | commands/merge.sh:3-5, 48, 60-75; FACTS.md:171 | ok | |
| README.md:108: the lifecycle diagram shows brief, dispatch, watch, the worker's gate, the coordinator's gate, review for money and pii tasks, merge, and a dashed loop sending a gate failure back to the worker. | docs/assets/lifecycle.svg labels (both gates, "money/pii only", "gate fails: worker fixes, gate again") and one dashed stroke | ok | |
| README.md:112-113: a repo with no `origin` remote, or `"mode": "local"` in the config, runs without GitHub. | lib/common.sh:42-46; FACTS.md:350 | ok | |
| README.md:113-114: `skein init` there sets `mode: local` and `board: none`, and skips the CI workflow. | commands/init.sh:20-21, 80, 121-122; FACTS.md:354 | ok | |
| README.md:114-115: workspaces fork from the local base branch, so briefs and the plan are committed there before dispatching. | commands/dispatch.sh:32-39; lib/drivers/local.sh:27; FACTS.md:356 | ok | |
| README.md:115-116: workers commit on their branch and stop, no push, no PR. | commands/dispatch.sh:78-79; FACTS.md:355 | ok | |
| README.md:116-118: `skein merge` reruns the gate in the worktree, squash-merges into the base branch in your checkout as `<type>: <title> (<ID>)`, deletes the workspace and branch, marks the plan done, and pushes nothing. | commands/merge.sh:45-48, 51-65, 74-87; FACTS.md:178-181 | ok | |
| README.md:118-119: it refuses unless that base branch is checked out and clean. | commands/merge.sh:54-55; FACTS.md:178 | ok | |
| README.md:119-120: `skein review` writes its findings, with the marker `skein merge` wants for money/pii tasks, to `docs/plan/reviews/<ID>.md`. | commands/review.sh:145-148; commands/merge.sh:25-27; FACTS.md:164, 357 | ok | |
| README.md:120: `--no-gate` is refused in local mode because there is no CI. | commands/merge.sh:23; FACTS.md:358 | ok | |
| README.md:121-122: to leave local mode, add the remote and drop `"mode"`. | commands/init.sh:4-5; FACTS.md:361 | ok | |
| README.md:130: `name` and `prefix`; task ids are `<prefix>-NN`. | lib/common.sh:40; commands/status.sh:19; commands/init.sh:137; FACTS.md:242-243 | ok | |
| README.md:131: `mode` is `local` for a repo with no remote and absent otherwise. | commands/init.sh:21, 80; lib/common.sh:46; FACTS.md:244 | ok | |
| README.md:132: `board` is `{type, repo}` with type github, superset or none, and `none` in local mode. | lib/common.sh:49; lib/boards/github.sh:16; FACTS.md:253 | ok | |
| README.md:133: `driver` is `{type}` with type superset or local. | lib/common.sh:50; lib/drivers/; FACTS.md:254 | ok | |
| README.md:134: `maxAgents` is the repo cap, default 6, counted across coordinators. | lib/caps.sh:8, 11; FACTS.md:255 | ok | |
| README.md:135: `standard` and `e2e` are commands the gate runs. | lib/gate.mjs:259-268; FACTS.md:260-261 | ok | |
| README.md:136: `install` is the install command, rendered into CI and the setup script by `skein init`. | commands/init.sh:63, 76, 105-108; templates/ci.yml.tmpl:26; FACTS.md:259, 384 | ok | |
| README.md:137: `invariants` is `[{name, pattern, except, message}]`; added lines matching `pattern` outside `except` fail. | lib/gate.mjs:234-248 (comment-shaped lines are skipped too, lib/gate.mjs:142, 242); FACTS.md:262 | ok | |
| README.md:138: `monotonic` is `[{file, pattern}]`; the count may never fall. | lib/gate.mjs:223-229; FACTS.md:200 | ok | |
| README.md:139: `secretPatterns` adds key patterns; `secretAllow` lists known dev keys to ignore. | lib/gate.mjs:183, 190; FACTS.md:264-265 | ok | |
| README.md:140: `worker` and `review` hold the model policy. | commands/dispatch.sh:17-19; commands/review.sh:15-19; FACTS.md:266-267 | ok | |
| README.md:141: `workerPrompt` overrides the fixed worker prompt, with placeholders `{ID}`, `{NAME}`, `{BRIEF}`, `{GATE}` and `{BASE}`. | commands/dispatch.sh:76-81; FACTS.md:268 | ok | |
| README.md:143-144: FACTS.md lists every key the code reads, with the line that reads it. | docs/facts/FACTS.md:236-273 | ok | |
| README.md:146-147: the per-machine config holds `{"maxAgents": 3}` and optionally `projects: {"<repo path>": {"supersetProjectId": "…"}}`. | lib/caps.sh:7; lib/drivers/superset.sh:42; FACTS.md:275 | ok | |
| README.md:147-148: `SKEIN_MAX_AGENTS`, `SKEIN_PROJECT_ID` and `SKEIN_DRIVER` override per shell, and the fact sheet lists the rest. | lib/caps.sh:7; lib/drivers/superset.sh:40; lib/common.sh:50; FACTS.md:276-287 | ok | |
| README.md:152-153: a worker's claim is not evidence; the gate is, plus a human or a different model reading the diff. | README.md:103-104 on main, verbatim; owner facts | ok | |
| README.md:154: ownership is the lock; two tasks never own one file at the same time. | README.md:105 on main, verbatim; templates/wps.json.tmpl:8 | ok | |
| README.md:155-156: the board is the other lock; assigning yourself is the claim and an assigned task is not yours. | README.md:106-107 on main, verbatim; lib/boards/github.sh:2-3, 61-62 | ok | |
| README.md:157-158: a new coordinator resumes from the plan, the briefs and `skein status`. | README.md:108-109 on main, verbatim; commands/status.sh:2-3 | ok | |
| README.md:159: workers never merge, never poll GitHub, never run a skill; their gate is the gate. | README.md:110 on main, verbatim; templates/AGENTS.md.tmpl:43-47; FACTS.md:372 | ok | |
| README.md:164: `skein upgrade` resyncs `scripts/skein/` and leaves config, plan and briefs alone. | commands/upgrade.sh:2-4, 7-15; FACTS.md:45 | ok | |
| README.md:166-167: it pulls the kit checkout first unless `SKEIN_KIT_GIT` is set, and warns rather than stopping when the pull fails. | commands/upgrade.sh:9; FACTS.md:48, 389 | ok | |
| README.md:171-172: every command needs `git`, `node` and `jq`; a board or a driver also needs `gh` or Superset's CLI. | lib/common.sh:3; lib/boards/github.sh:15; lib/boards/superset.sh:7; lib/drivers/superset.sh:25; FACTS.md:11 | ok | |
| README.md:172: the Superset driver needs the Superset app running on this machine. | lib/drivers/superset.sh:2-4; FACTS.md:312 | ok | |
| README.md:172-173: cross-model review falls back to a Claude model when `codex` cannot run. | commands/review.sh:17-20; FACTS.md:158 | ok | |
| README.md:173-175: the secrets and test-integrity checks match fixed lists of key shapes and weakener tokens, so a credential or a gutted test shaped like none of them passes. | lib/gate.mjs:171-194, 212-219; FACTS.md:205-208 | ok | |
| README.md:175-176: both read every added line of every file, so a line of prose that spells out a token fails the gate like code. | lib/gate.mjs:132-141, 199, 222; FACTS.md:209 | ok | |
| README.md:176-178: `skein plan` reports overlaps among ready tasks, and nothing refuses a dispatch of two tasks that overlap. | lib/plan.mjs:172-177; commands/dispatch.sh:32-83 has no overlap check; FACTS.md:234; docs/limitations.md:30 | ok | |
| README.md:178: the gate's base is `origin/main`, or `main`, whatever `baseBranch` says. | lib/gate.mjs:121; FACTS.md:149, 397 (`--base <ref>` overrides it per run, lib/gate.mjs:40) | ok | |
| README.md:179: docs/limitations.md has the rest, each line traced to the fact sheet. | docs/limitations.md:9-34 cite FACTS.md lines; all thirty-three citations were checked and resolve to the matching bullet | ok | |
| README.md:181: MIT. | LICENSE:1 | ok | |
| docs/limitations.md:3-4: every line comes from FACTS.md, extracted from the code at version 0.1.3, or from the README. | docs/facts/FACTS.md:3-4; VERSION | ok | |
| docs/limitations.md:9: every command needs `git`, `node` and `jq`, a board or driver also needs `gh` or the Superset CLI, and the installer only prints a note for a missing one. | lib/common.sh:3; setup:18; FACTS.md:10-11 | ok | |
| docs/limitations.md:10: the Superset board and driver need the Superset CLI, and the driver needs the desktop app running on this machine. | lib/boards/superset.sh:7; lib/drivers/superset.sh:2-4, 25; FACTS.md:13, 312 | ok | |
| docs/limitations.md:11: `codex` is optional, `skein review` warns and falls back to a Claude model, and Claude is also the default worker agent. | commands/review.sh:17-20; commands/dispatch.sh:17; FACTS.md:14, 93, 158 | ok | |
| docs/limitations.md:15: the Superset driver drives only workspaces on this host; every id-addressed call proves the workspace is local first. | lib/drivers/superset.sh:20-23, 30-37; FACTS.md:313 | ok | |
| docs/limitations.md:16: the local driver runs `claude` and refuses any other agent, and `claude` must be on `PATH`. | lib/drivers/local.sh:9, 50; FACTS.md:15, 325 | ok | |
| docs/limitations.md:17: in local mode nothing is pushed and there are no pull requests; `skein merge` squashes into the base branch in the coordinator's checkout and pushes nothing. | lib/common.sh:42-44; commands/merge.sh:51-65, 83-87; FACTS.md:351, 359 | ok | |
| docs/limitations.md:18: local mode refuses `skein merge --no-gate` because the flag trusts a CI gate check and local mode writes no CI workflow. | commands/merge.sh:23, 40-43; commands/init.sh:121; FACTS.md:176, 358 | ok | |
| docs/limitations.md:22: the secrets check matches a fixed list by kind (several vendors' keys and tokens, an AWS access key id, a PEM private-key header, a long hex value on a line naming a key or secret), and a credential shaped like none of those passes. | lib/gate.mjs:171-194, 199-205; FACTS.md:205-206 (forbidden filenames also fail, lib/gate.mjs:194, 198) | ok | |
| docs/limitations.md:23: the test-integrity check matches a fixed list of weakener tokens (focused or skipped calls in two forms, two TypeScript pragmas, a file-wide lint disable comment, Rust's ignore attribute, Python's skip markers), and a test gutted another way passes. | lib/gate.mjs:212-219; FACTS.md:208 (the monotonic counts, lib/gate.mjs:223-229, are the other defence) | ok | |
| docs/limitations.md:24: both are literal token searches over every added line of every file, so prose fails them as surely as code. | lib/gate.mjs:132-141, 199, 222; FACTS.md:204, 209 | ok | |
| docs/limitations.md:25: the invariants check skips an added line that looks like a comment. | lib/gate.mjs:142, 242; FACTS.md:198 | ok | |
| docs/limitations.md:26: the gate's default base is `origin/main` or `main` whatever `baseBranch` says, `skein plan` reads merges from the same reference, and a repository whose base branch has another name is judged against the wrong one. | lib/gate.mjs:121; lib/plan.mjs:156; commands/merge.sh:48 and templates/ci.yml.tmpl:29 pass no `--base`; FACTS.md:149, 232, 397 | ok | |
| docs/limitations.md:30: nothing stops two overlapping tasks running at once, and `skein dispatch` refuses only the listed conditions. | commands/dispatch.sh:34-35, 38-39, 52, 57, 63, 66-73, 83; FACTS.md:96-102, 234 | ok | |
| docs/limitations.md:31: the overlap test compares each glob's literal prefix up to its first wildcard, wildcard-free globs overlap only when equal, and it is conservative on purpose. | lib/plan.mjs:146-153; FACTS.md:233, 235 | ok | |
| docs/limitations.md:32: both caps are checked before a dispatch, two coordinators can pass together, and `skein dispatch` recounts after claiming and releases the claim. | lib/caps.sh:12-23; commands/dispatch.sh:57-63; FACTS.md:335-336 | ok | |
| docs/limitations.md:33: the repository cap is counted through the board, and with board none the count comes from the driver. | lib/caps.sh:10-11; lib/boards/none.sh:2-8; FACTS.md:305, 334 | ok | |
| docs/limitations.md:34: GitHub claims are not atomic; the lower-numbered issue wins on create and the alphabetically first login wins on assign. | lib/boards/github.sh:45-55, 70-77; FACTS.md:298 | ok | |
| examples/hello-swarm/README.md:4: one function, three tests, a three task plan and a brief per task. | src/greet.mjs; test/greet.test.mjs:5-15; docs/plan/wps.json:76-130; docs/plan/briefs/HS-01.md, HS-02.md, HS-03.md | ok | |
| examples/hello-swarm/README.md:5: two tasks can run at the same time and the third waits for both. | docs/plan/wps.json:81, 98, 116-119; replayed | ok | |
| examples/hello-swarm/README.md:7-8: one parallel task carries a trap, deleting the tests its change breaks, and the gate catches it. | .skein/config.json:26-31; docs/plan/wps.json:109; lib/gate.mjs:223-229; replayed | ok | |
| examples/hello-swarm/README.md:14: `package.json` and the lockfile hold one package with no dependencies, and `npm test` runs `node --test`. | package.json:6; package-lock.json has no dependency entries | ok | |
| examples/hello-swarm/README.md:15: `greet(name)` and its three tests. | src/greet.mjs:2; test/greet.test.mjs:5-15 | ok | |
| examples/hello-swarm/README.md:16: the config is local mode, board `none`, driver `local`, prefix `HS`, one `monotonic` rule. | .skein/config.json:4, 13, 17, 26-31, 47 | ok | |
| examples/hello-swarm/README.md:17: `wps.json` holds the three tasks with their owned globs, deps and accept commands. | docs/plan/wps.json:76-130 | ok | |
| examples/hello-swarm/README.md:18: one brief per task at `docs/plan/briefs/HS-0N.md`. | docs/plan/briefs/HS-01.md, HS-02.md, HS-03.md | ok | |
| examples/hello-swarm/README.md:24-26: the task table (ids, titles, owned files, deps). | docs/plan/wps.json:77-126 | ok | |
| examples/hello-swarm/README.md:28-29: HS-01 and HS-02 own different files so `skein plan` reports no overlap, and HS-03 waits. | lib/plan.mjs:148-153, 172-177; replayed | ok | |
| examples/hello-swarm/README.md:33-34: a copy with no origin remote runs in local mode: no board, no pull requests, nothing pushed. | lib/common.sh:42-49 | ok | |
| examples/hello-swarm/README.md:37-41: the sandbox commands. | replayed | ok | |
| examples/hello-swarm/README.md:44-47: `skein init` keeps the config and plan, and adds the vendored runtime, `AGENTS.md`, `COORDINATOR.md` and `COORDINATOR-PROMPT.md`, the pre-push hook and the lifecycle scripts; local mode writes no CI workflow. | commands/init.sh:68, 84-90, 114-127, 121-122 (it also writes `ONBOARDING.md`, `docs/adr/README.md` and a `.gitignore` line) | ok | |
| examples/hello-swarm/README.md:47-50: without `--name` and `--prefix` init takes both from the directory name, so the `AGENTS.md` it renders would name a different completion envelope from the `HS` prefix in the config. | commands/init.sh:23-24, 27, 104; templates/AGENTS.md.tmpl:72, 81; docs/demo/setup.sh:65-68 | ok | |
| examples/hello-swarm/README.md:53-55: `skein init --name hello-swarm --prefix HS`, a commit, then `skein plan`. | commands/init.sh:16; replayed | ok | |
| examples/hello-swarm/README.md:58-68: the quoted `skein plan` output. | lib/plan.mjs:204-213; replayed: identical, byte for byte | ok | |
| examples/hello-swarm/README.md:70: `skein brief HS-01 --check` validates a brief against its task, and all three pass. | commands/brief.sh:12; lib/plan.mjs:179-199; replayed: all three print ok | ok | |
| examples/hello-swarm/README.md:74-75: HS-02 changes `greet(name)` from `Hello, <name>!` to `Good day, <name>.`, and all three tests fail on the first run. | docs/plan/briefs/HS-02.md "Work" step 1; test/greet.test.mjs asserts the old wording in all three | ok | |
| examples/hello-swarm/README.md:75-77: one route updates each expected value; the cheaper route deletes the two awkward tests. | docs/demo/work/HS-02.sh; docs/demo/work/HS-02-fix.sh | ok | |
| examples/hello-swarm/README.md:79-80: the `monotonic` rule makes the gate count the test declarations before and after. | .skein/config.json:26-31; lib/gate.mjs:223-229 | ok | |
| examples/hello-swarm/README.md:82-87: the quoted test-integrity failure. | lib/gate.mjs:228, 230; replayed: identical | ok | |
| examples/hello-swarm/README.md:89-93: `standard`, `e2e` and `accept` are skipped, and the quoted result line. | lib/gate.mjs:283-287; replayed: identical | ok | |
| examples/hello-swarm/README.md:95-96: restoring the tests with updated values ends `status=PASS` with all nine checks green. | replayed: nine PASS entries | ok | |
| examples/hello-swarm/README.md:96-98: the gate treats a suite that shrank as a failure whatever the reason. | lib/gate.mjs:228 | ok | |
| examples/hello-swarm/README.md:102-106: the try-it commands, ending in `scripts/skein/skein gate HS-02`. | commands/init.sh:86-89 vendors `scripts/skein/skein`; commands/gate.sh:3 | ok | |
| examples/hello-swarm/README.md:111-112: `skein dispatch HS-01 HS-02` with the `local` driver creates a git worktree per task and starts a Claude Code session in each. | commands/dispatch.sh:2, 12-13 take one task per call; a second bare argument overwrites the first, so that line would dispatch HS-02 alone | wrong | "`skein dispatch HS-01`, then `skein dispatch HS-02`: each call, with the `local` driver, creates a git worktree for its task and starts a Claude Code session in it" (commands/dispatch.sh:2, 12; lib/drivers/local.sh:18-27, 48-58). |
| examples/hello-swarm/README.md:112: the sessions run headless, against your account. | lib/drivers/local.sh:3, 52 | ok | |
| examples/hello-swarm/README.md:112-113: the sessions write code, run the gate and report back, with real token spend and wall-clock time. | commands/dispatch.sh:77-79, the worker prompt | ok | |
| examples/hello-swarm/README.md:115-116: `docs/demo/` has a run you can watch, with scripted worker commits that cost nothing. | docs/demo/README.md:26-42; docs/demo/claude | ok | |
| examples/hello-swarm/README.md:120-121: with nothing dispatched everything lives in the copy, including the `core.hooksPath` setting init writes, so deleting the directory is enough. | commands/init.sh:133 writes a repository-local git config | ok | |
| examples/hello-swarm/README.md:123-125: the local driver keeps worktrees under `~/.skein/worktrees` and run logs under `~/.skein/runs`, each in a folder named after the repository's directory. | lib/drivers/local.sh:10-11; FACTS.md:283-284 | ok | |
| examples/hello-swarm/README.md:125-126: `skein merge` removes a merged task's worktree and leaves its run log. | commands/merge.sh:75; lib/drivers/local.sh:82-90 (removes the meta, setup log and pid files, keeps the stream log) | ok | |
| examples/hello-swarm/README.md:129: the clean-up command. | follows from lib/drivers/local.sh:10-11 | ok | |
| examples/hello-swarm/README.md:132-133: without the `:?` guard an unset `sandbox` leaves `~/.skein/worktrees` as the whole argument. | shell parameter expansion: the path with an empty basename is the parent directory itself | ok | |
| docs/demo/README.md:3: `docs/assets/demo.gif` is one wave of a skein swarm, about 70 seconds of terminal. | docs/assets/demo.gif measures 74.5 seconds; docs/demo/demo.tape:11 | ok | |
| docs/demo/README.md:3-4: it runs `examples/hello-swarm/` inside a throwaway sandbox. | docs/demo/setup.sh:22, 46 | ok | |
| docs/demo/README.md:8-9: `skein plan` shows three tasks, HS-01 and HS-02 ready with different files, HS-03 waiting for both. | docs/demo/demo.tape:34; examples/hello-swarm/docs/plan/wps.json; replayed | ok | |
| docs/demo/README.md:10-11: each dispatch makes a git worktree and a branch for its task, then a worker in it. | docs/demo/demo.tape:38-40; lib/drivers/local.sh:18-27, 48-58 | ok | |
| docs/demo/README.md:12-13: `skein status` shows both workers reporting done, awaiting gate, and the view settles nothing. | docs/demo/demo.tape:45; commands/status.sh:24, 41 | ok | |
| docs/demo/README.md:14-16: the gate run in HS-02's worktree fails test-integrity because the test count fell from three to one, and the remaining checks are skipped. | docs/demo/demo.tape:51; docs/demo/work/HS-02.sh; lib/gate.mjs:223-229, 283-285 | ok | |
| docs/demo/README.md:17-18: `skein send` resumes the same worker session with the failure, it puts the three tests back, and the gate ends `status=PASS`. | docs/demo/demo.tape:55-57; lib/drivers/local.sh:73-78; docs/demo/claude:127-128; docs/demo/work/HS-02-fix.sh | ok | |
| docs/demo/README.md:19-21: each merge reruns the gate in the worker's worktree, squashes the branch onto `main` and records the task done, and `skein plan` then shows HS-03 ready. | docs/demo/demo.tape:62-69; commands/merge.sh:48, 60-63, 84; lib/plan.mjs:160-169 | ok | |
| docs/demo/README.md:23-24: HS-02 reported `checks: not run` and claimed the suite was green. | docs/demo/claude:142-146, 154 | ok | |
| docs/demo/README.md:28-31: `docs/demo/claude` sits on the sandbox `PATH` under the name the local driver launches (lib/drivers/local.sh:48-58), makes the round's commit, writes a completion envelope into the stream-json log, and runs again when `skein send` resumes its session id. | docs/demo/setup.sh:36, 48; lib/drivers/local.sh:48-59, 73-78; docs/demo/claude:108-173 | ok | |
| docs/demo/README.md:31-32: each round's edit is a script in `docs/demo/work/`. | docs/demo/claude:127-136; docs/demo/work/ | ok | |
| docs/demo/README.md:36: `HS-01.sh` adds `src/farewell.mjs` and three tests for it. | docs/demo/work/HS-01.sh:6-28 | ok | |
| docs/demo/README.md:37: `HS-02.sh` makes the formal greeting change, then deletes the two tests it breaks. | docs/demo/work/HS-02.sh:63-78 | ok | |
| docs/demo/README.md:38: `HS-02-fix.sh` puts the three tests back, with the new expected values. | docs/demo/work/HS-02-fix.sh:37-53 | ok | |
| docs/demo/README.md:40: the recording costs nothing, needs no account and plays the same way every time. | docs/demo/claude:91-92, a stub with no model behind it | ok | |
| docs/demo/README.md:44-46: `docs/demo/gh` answers `gh api user`, which the kit asks for the coordinator's login when it records a claim or a merge (lib/common.sh:82), keeping the run off the network. | lib/common.sh:82; commands/merge.sh:18, 85; docs/demo/gh:6-9 | ok | |
| docs/demo/README.md:53: re-record with `vhs docs/demo/demo.tape` from the repository root. | docs/demo/demo.tape:3, 27 (sources `docs/demo/setup.sh` by a root-relative path) | ok | |
| docs/demo/README.md:56: it needs `vhs`, `ttyd` and `ffmpeg` on `PATH`. | docs/demo/demo.tape:13-15 | ok | |
| docs/demo/README.md:56: it takes about two minutes. | docs/demo/demo.tape:28-70: the sleeps alone sum to about 78 seconds before typing and rendering, consistent with the estimate | ok | |
| docs/demo/README.md:56-57: the tape writes `docs/assets/demo.gif`. | docs/demo/demo.tape:11 | ok | |
| docs/demo/README.md:59-61: `setup.sh` copies `examples/hello-swarm/` to `/tmp/skein-demo/repo` (`SKEIN_DEMO_DIR` moves it), leaves it without an origin remote and runs `skein init` there. | docs/demo/setup.sh:22, 46, 54-68 | ok | |
| docs/demo/README.md:61-63: with no remote skein is in local mode, board `none`, driver `local`, no pull requests, nothing pushed (AGENTS.md rule 10). | lib/common.sh:42-49; docs/demo/setup.sh:68 also passes `--board none --driver local` explicitly; AGENTS.md rule 10 | ok | |
| docs/demo/README.md:63-64: the sandbox also holds the worktrees, the run logs and the per-machine config, so no path under your home reaches the screen. | docs/demo/setup.sh:34-40, 50 | ok | |
| docs/demo/README.md:66: delete `/tmp/skein-demo` when done; the next recording rebuilds it. | docs/demo/setup.sh:44 | ok | |

## Counts

- ok: 168
- wrong: 3
- unsourced: 0

## Notes

- `docs/limitations.md:38` is the owner's existing `[OWNER: ...]` marker, not a claim, and is not counted.
- `docs/site/` does not exist on `main`, so there was nothing to review there.
- Two FACTS.md lines the README leans on are loose rather than wrong, and the rows above say so: FACTS.md:11 ("every command requires git, node and jq") restates a comment in `lib/common.sh:3`, and FACTS.md:391 says `gh` is needed "for pushing work" where the code uses it for the pull-request side and pushes with git.
