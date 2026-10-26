# Limitations

Where skein stops. Every line comes from `docs/facts/FACTS.md`, which was extracted from the
code at version 0.1.3, or from the README. The last line is the owner's, and it is the one to
read first if you want to know what goes wrong in practice.

## Requirements

- Every command needs `git`, `node` and `jq`, and a command that touches a board or a driver also needs `gh` or the Superset CLI; the installer only prints a note when one of them is missing, so the failure arrives later (`docs/facts/FACTS.md:11`, `docs/facts/FACTS.md:10`).
- The Superset board and the Superset driver both need the Superset CLI, and the driver reads and drives workspaces through it, so the Superset desktop app has to be running on this machine (`docs/facts/FACTS.md:13`, `docs/facts/FACTS.md:312`).
- Cross-model review needs `codex`, which is optional. When `codex` cannot run, `skein review` warns and falls back to a Claude model, and Claude is also the default worker agent, so the second opinion comes from the same family as the work (`docs/facts/FACTS.md:14`, `docs/facts/FACTS.md:158`, `docs/facts/FACTS.md:93`).

## Drivers and boards

- The Superset driver drives only workspaces on this host. Superset routes a call that names a workspace by id to whichever host owns it, so every id-addressed call first proves the workspace is local and refuses otherwise (`docs/facts/FACTS.md:313`).
- The local driver runs `claude` and refuses any other agent, and `claude` has to be on `PATH` for it to work at all (`docs/facts/FACTS.md:325`, `docs/facts/FACTS.md:15`).
- In local mode nothing is pushed and there are no pull requests: workers commit on their branch, and `skein merge` squashes into the base branch in the coordinator's own checkout and pushes nothing (`docs/facts/FACTS.md:351`, `docs/facts/FACTS.md:359`).
- Local mode also refuses `skein merge --no-gate`, because that flag trusts a CI gate check and local mode writes no CI workflow (`docs/facts/FACTS.md:358`, `docs/facts/FACTS.md:176`).

## The gate

- The secrets check matches a fixed list of key shapes, by kind: several vendors' API keys and tokens, an AWS access key id, a PEM private-key header, and a long hex value on a line that names a key or a secret. A credential shaped like none of those passes (`docs/facts/FACTS.md:205`, `docs/facts/FACTS.md:206`).
- The test-integrity check matches a fixed list of weakener tokens: a focused or skipped test call in either the dotted or the prefixed form, the two TypeScript pragmas that switch off or suppress checking, a file-wide lint disable comment, Rust's ignore attribute and Python's skip markers. A test gutted some other way, or a test that never asserted anything, passes (`docs/facts/FACTS.md:208`).
- Both run as literal token searches over every added line of every file, so prose fails them as surely as code does. A line of documentation that spells out one of those tokens, or a worked example of a key, fails the gate (`docs/facts/FACTS.md:209`, `docs/facts/FACTS.md:204`).
- The invariants check skips an added line that looks like a comment, so a rule's pattern slips through inside a comment (`docs/facts/FACTS.md:198`).
- The gate's default base is `origin/main`, or `main` when that reference does not verify, whatever the config's `baseBranch` says, and `skein plan` reads merges from the same reference. A repository whose base branch has another name is judged against the wrong one (`docs/facts/FACTS.md:397`, `docs/facts/FACTS.md:149`, `docs/facts/FACTS.md:232`).

## Coordination

- Ownership is the lock, and the gate enforces it per task, but nothing stops two overlapping tasks running at once. `skein plan` reports the overlaps among ready tasks, and `skein dispatch` is not one of the things that refuse them: it refuses an invalid brief, an unmerged dependency, a brief or plan that differs from the base reference, a leftover branch with commits on it, either cap, a failed workspace or setup, a missing worktree or brief, a workspace head that is not the base reference, and an agent that does not start (`docs/facts/FACTS.md:234`, `docs/facts/FACTS.md:96-102`).
- The overlap test compares the literal prefix of each glob up to its first wildcard instead of resolving globs against files, and two wildcard-free globs overlap only when they are equal. It is conservative on purpose: a false overlap costs one serialised merge round and a missed one costs a conflict (`docs/facts/FACTS.md:233`, `docs/facts/FACTS.md:235`).
- Both caps are checked before a dispatch, and two coordinators can pass the check at the same moment, so `skein dispatch` recounts after claiming and releases the claim when the repository is over its cap (`docs/facts/FACTS.md:335`, `docs/facts/FACTS.md:336`).
- The repository cap is counted through the board. With board `none` every board function is a no-op and the count comes from the driver, so the cap then covers only what this machine runs (`docs/facts/FACTS.md:334`, `docs/facts/FACTS.md:305`).
- Claims on the GitHub board are not atomic: neither creating an issue nor assigning one is. A race is settled after the fact, with the lower-numbered open issue winning on create and the alphabetically first login winning on assign, so a claim can be taken and then given back (`docs/facts/FACTS.md:298`).

## In practice

- [OWNER: anything else that still goes wrong in practice, e.g. agents stalling, shallow fixes that pass the gate, cost]
