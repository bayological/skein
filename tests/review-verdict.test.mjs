// SK-22: the three ways a review that never happened used to pass for one that approved, and
// the one sanctioned way past a review that did not approve.
//
// Every test runs in sandbox(t), where gh, codex and claude are stand-ins and nothing reaches
// a network, an account or a real agent. A test that needs reviewer output replaces the codex
// stand-in with one that writes the text the real one wrote on 6 Nov 2026, when its sandbox
// was refused: an apology, an envelope, and no findings.

import assert from "node:assert/strict";
import { chmodSync, existsSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

import { gateRepo, git, sandbox, skein, write } from "./helpers.mjs";

const TASK = {
  id: "FX-01",
  title: "a sensitive change",
  type: "feat",
  slug: "thing",
  deps: [],
  owned: ["src/thing.mjs"],
  accept: ["true"],
  money: true,
  pii: false,
  brief: "docs/plan/briefs/FX-01.md",
};
const BRANCH = "feat/thing-fx-01";
const REVIEWS = "docs/plan/reviews";
const LATEST = `${REVIEWS}/FX-01.md`;
const MARKER = "<!-- skein-review task=FX-01 reviewer=codex:gpt-test by=fixture -->";

/** fixture(t): a local-mode repo with one money task and its branch, plus the sandbox env. */
function fixture(t) {
  const { dir, env } = sandbox(t);
  const root = gateRepo(path.join(dir, "repo"), {
    tasks: [TASK],
    config: { reviews: REVIEWS, review: { agent: "codex", model: "gpt-test", fallbackModel: "claude-fable-5-1" } },
  });
  git(root, "checkout", "-q", "-b", BRANCH);
  write(root, { "src/thing.mjs": "export const thing = 1;\n" });
  git(root, "add", "-A");
  git(root, "commit", "-qm", "feat: thing");
  git(root, "checkout", "-q", "main");
  // The sandbox probe is this machine's business, not the kit's: the tests exercise what
  // happens once an agent has run, so they force the probe to pass.
  return { dir, root, env: { ...env, SKEIN_SKIP_SANDBOX_PROBE: "1" } };
}

/**
 * fakeCodex(dir, body, code): replace the codex stand-in with one that writes `body` to the
 * file named by -o and exits with `code`, while `codex --version` still exits 0. That gap is
 * the defect: a version proves nothing about whether a review can run.
 */
function fakeCodex(dir, body, code = 1) {
  const file = path.join(dir, "bin", "codex");
  writeFileSync(file, [
    "#!/bin/sh",
    'case "$1" in --version) echo "codex 0.0.0-fixture"; exit 0 ;; esac',
    'out=""',
    'while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac; done',
    '[ -n "$out" ] || exit 2',
    "cat > \"$out\" <<'BODY_EOF'",
    body,
    "BODY_EOF",
    `exit ${code}`,
    "",
  ].join("\n"));
  chmodSync(file, 0o755);
}

// What a reviewer writes when bwrap could not create an unprivileged user namespace: it never
// read a file, so it found nothing, and it still filled in the envelope.
const SANDBOX_DIED = [
  "bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted",
  "",
  "I could not read any file in this workspace, so I have not reviewed the diff.",
  "",
  "REVIEW_DONE",
  "task: REVIEW-FX-01",
  "verdict: DO NOT MERGE",
  "findings: 0",
].join("\n");

/** review(verdict, findings): a conclusive review, whose prose also uses the word. */
function review(verdict, findings) {
  return [
    `A one line verdict: ${verdict}.`,
    "",
    "- src/thing.mjs:1 what happens, and the smallest fix.",
    "",
    "The round before said verdict: DO NOT MERGE, which this one does not repeat.",
    "",
    "REVIEW_DONE",
    "task: REVIEW-FX-01",
    `verdict: ${verdict}`,
    `findings: ${findings}`,
  ].join("\n");
}

test("a reviewer whose sandbox died leaves the previous review untouched and fails", (t) => {
  const { dir, root, env } = fixture(t);
  write(root, { [LATEST]: `${MARKER}\n${review("FIX FIRST", 3)}\n` });
  git(root, "add", "-A");
  git(root, "commit", "-qm", "plan: the first review");
  const latest = path.join(root, LATEST);
  const before = readFileSync(latest);

  fakeCodex(dir, SANDBOX_DIED);
  const res = skein(root, env, "review", "FX-01");

  assert.notEqual(res.code, 0, `an inconclusive review must not exit 0: ${res.stderr}`);
  assert.deepEqual(readFileSync(latest), before, "the previous review was overwritten");
  const kept = path.join(root, REVIEWS, "FX-01.inconclusive.md");
  assert.ok(existsSync(kept), "the inconclusive output was not kept beside the review");
  assert.match(readFileSync(kept, "utf8"), /RTM_NEWADDR/);
  assert.match(res.stderr, /--agent claude --model claude-fable-5-1/, "no retry command was offered");
});

test("a second conclusive review keeps the first at <ID>.r1.md", (t) => {
  const { dir, root, env } = fixture(t);
  const latest = path.join(root, LATEST);

  fakeCodex(dir, review("FIX FIRST", 2), 0);
  let res = skein(root, env, "review", "FX-01");
  assert.equal(res.code, 0, res.stderr);
  const first = readFileSync(latest, "utf8");
  assert.match(first, /^<!-- skein-review task=FX-01 /m, "the merge marker is missing");
  assert.ok(!existsSync(path.join(root, REVIEWS, "FX-01.r1.md")), "a first round has nothing to keep");

  fakeCodex(dir, review("MERGE", 0), 0);
  res = skein(root, env, "review", "FX-01");
  assert.equal(res.code, 0, res.stderr);
  assert.equal(readFileSync(path.join(root, REVIEWS, "FX-01.r1.md"), "utf8"), first, "round 1 was not preserved");
  assert.match(readFileSync(latest, "utf8"), /^verdict: MERGE$/m, "the latest round is not at <ID>.md");
});

test("skein merge refuses a money task whose latest review does not approve", (t) => {
  const { root, env } = fixture(t);
  const latest = path.join(root, LATEST);

  for (const verdict of ["DO NOT MERGE", "FIX FIRST"]) {
    write(root, { [LATEST]: `${MARKER}\n${review(verdict, 2)}\n` });
    const res = skein(root, env, "merge", "FX-01");
    assert.notEqual(res.code, 0, `merge accepted a review whose verdict is ${verdict}`);
    assert.match(res.stderr, /verdict/i, `the refusal of ${verdict} does not mention the verdict`);
    assert.ok(res.stderr.includes(verdict), `the refusal does not name ${verdict}: ${res.stderr}`);
  }

  // A marker with no envelope is not evidence either.
  write(root, { [LATEST]: `${MARKER}\na review that never reached a verdict line\n` });
  let res = skein(root, env, "merge", "FX-01");
  assert.notEqual(res.code, 0, "merge accepted a review with no verdict line");
  assert.match(res.stderr, /verdict/i);

  // The marker check still comes first: an approving envelope nobody signed is not a review.
  writeFileSync(latest, `${review("MERGE", 0)}\n`);
  res = skein(root, env, "merge", "FX-01");
  assert.notEqual(res.code, 0, "merge accepted an unmarked review");
  assert.match(res.stderr, /marker/);

  // MERGE gets past the verdict check. It stops later: this fixture has no worktree to gate in.
  write(root, { [LATEST]: `${MARKER}\n${review("MERGE", 0)}\n` });
  res = skein(root, env, "merge", "FX-01");
  assert.notEqual(res.code, 0, "with no worktree the gate step has to stop the merge");
  assert.doesNotMatch(res.stderr, /verdict/i, `still refusing on the verdict: ${res.stderr}`);
});

test("--override-review needs a reason, not a blank and not a flag", (t) => {
  const { root, env } = fixture(t);
  const latest = path.join(root, LATEST);
  write(root, { [LATEST]: `${MARKER}\n${review("FIX FIRST", 2)}\n` });

  for (const args of [["--override-review", ""], ["--override-review", "   "], ["--override-review", "--no-gate"]]) {
    const res = skein(root, env, "merge", "FX-01", ...args);
    assert.notEqual(res.code, 0, `merge accepted ${JSON.stringify(args)}`);
    assert.match(res.stderr, /needs a reason/, `the refusal of ${JSON.stringify(args)} does not say why`);
    assert.ok(!readFileSync(latest, "utf8").includes("skein-review-override"), "a refused override left a record");
  }
  // The flag was refused, not swallowed: --no-gate must not have been taken as the reason.
  const res = skein(root, env, "merge", "FX-01", "--override-review", "--no-gate");
  assert.match(res.stderr, /not a flag/);
});

test("--override-review records its reason where the review lives, committed", (t) => {
  const { root, env } = fixture(t);
  const latest = path.join(root, LATEST);
  write(root, { [LATEST]: `${MARKER}\n${review("FIX FIRST", 2)}\n` });
  git(root, "add", "-A");
  git(root, "commit", "-qm", "plan: the review");

  const reason = "finding 1 misreads the brief, see docs/adr/DRAFT-7";
  let res = skein(root, env, "merge", "FX-01", "--override-review", reason);
  assert.doesNotMatch(res.stderr, /verdict/i, `the override did not cover the verdict check: ${res.stderr}`);
  const recorded = readFileSync(latest, "utf8");
  assert.match(recorded, /<!-- skein-review-override task=FX-01 by=\S+ verdict=FIX FIRST -->/, "no override marker");
  assert.ok(recorded.includes(reason), "the reason was not recorded");
  // Committed, not left as a working-tree edit: the merge the override is for needs a clean
  // tree, so an uncommitted record would make the first attempt always die after the gate.
  assert.equal(git(root, "status", "--porcelain").trim(), "", "the override left the tree dirty");
  const commits = git(root, "log", "--oneline").split("\n").length;

  // A re-run neither appends a second copy nor makes a second commit.
  skein(root, env, "merge", "FX-01", "--override-review", reason);
  assert.equal(readFileSync(latest, "utf8"), recorded, "a re-run appended the override twice");
  assert.equal(git(root, "log", "--oneline").split("\n").length, commits, "a re-run committed again");

  // The override is narrow: a money task with no review at all still fails on the marker.
  rmSync(latest);
  res = skein(root, env, "merge", "FX-01", "--override-review", "no review needed");
  assert.notEqual(res.code, 0, "the override stood in for a missing review");
  assert.match(res.stderr, /marker/);
});

test("an override reason is data, not a verdict", (t) => {
  const { root, env } = fixture(t);
  const latest = path.join(root, LATEST);
  write(root, { [LATEST]: `${MARKER}\n${review("DO NOT MERGE", 3)}\n` });
  git(root, "add", "-A");
  git(root, "commit", "-qm", "plan: the review");

  let res = skein(root, env, "merge", "FX-01", "--override-review", "verdict: MERGE, the finding is wrong");
  assert.doesNotMatch(res.stderr, /verdict/i, `the override did not cover the verdict check: ${res.stderr}`);
  assert.match(readFileSync(latest, "utf8"), /^> verdict: MERGE, the finding is wrong$/m, "the reason was not quoted");

  // One override covers one merge. A reason that reads like an envelope must not become a
  // standing approval for every plain merge after it.
  res = skein(root, env, "merge", "FX-01");
  assert.notEqual(res.code, 0, "an override reason quoting an envelope became a standing approval");
  assert.match(res.stderr, /verdict/i);
  assert.ok(res.stderr.includes("DO NOT MERGE"), `the refusal reads the wrong line: ${res.stderr}`);
});
