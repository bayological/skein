// Every check lib/gate.mjs runs, with a passing and a failing case, judged by behaviour:
// the exit code, the [PASS]/[FAIL]/[SKIP] lines and the SKEIN_GATE_RESULT line. Nothing here
// reads the kit's source.
//
// The task runs on a branch off main, the way a dispatched worker does, so the gate's
// default base is the fixture's own main.

import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";

import { gate, gateRepo, git, join, sandbox, write } from "./helpers.mjs";

const TASK = {
  id: "FX-01",
  title: "a fixture task",
  type: "feat",
  slug: "fixture-task",
  deps: [],
  owned: ["src/**"],
  accept: ["true"],
  money: false,
  pii: false,
  brief: "docs/plan/briefs/FX-01.md",
};

// A fresh sandbox and a committed fixture repository on main. Call it more than once in a
// test when a case needs its own history; every one is cleaned up in t.after.
function fixture(t, { tasks = [TASK], config, plan, files } = {}) {
  const { dir, env } = sandbox(t);
  const repo = path.join(dir, "repo");
  gateRepo(repo, { tasks, config, plan, files });
  return { repo, env };
}

// The task's branch: what the gate diffs against main.
function onBranch(repo, files, name = "feat/fixture-task-fx-01") {
  git(repo, "checkout", "-q", "-b", name);
  write(repo, files);
  git(repo, "add", "-A");
  git(repo, "commit", "-qm", "feat(fixture): the task's change");
}

test("the result line and the exit code: 0 on PASS, 1 on FAIL, 2 on an unknown flag", (t) => {
  const { repo, env } = fixture(t);
  onBranch(repo, { "src/a.js": "export const a = 1;\n" });

  const pass = gate(repo, env, "FX-01");
  assert.equal(pass.code, 0);
  assert.equal(pass.result.task, "FX-01");
  assert.equal(pass.result.base, "main");
  assert.equal(pass.result.status, "PASS");
  for (const name of ["brief", "clean-tree", "boundary", "secrets", "test-integrity", "invariants", "standard", "e2e", "accept"]) {
    assert.equal(pass.result.checks[name], "PASS", `${name} should pass on a clean fixture`);
    assert.match(pass.stdout, new RegExp(`\\[PASS\\] ${name}`));
  }

  const unknown = gate(repo, env, "FX-01", "--no-such-flag");
  assert.equal(unknown.code, 2);
  assert.equal(unknown.result, null);
  assert.match(unknown.stderr, /unknown flag/);
});

test("clean-tree: an uncommitted file fails", (t) => {
  const { repo, env } = fixture(t);
  onBranch(repo, { "src/a.js": "export const a = 1;\n" });
  write(repo, { "src/later.js": "export const later = 1;\n" });

  const res = gate(repo, env, "FX-01");
  assert.equal(res.code, 1);
  assert.equal(res.result.status, "FAIL");
  assert.equal(res.result.checks["clean-tree"], "FAIL");
  assert.match(res.stdout, /\[FAIL\] clean-tree/);
  assert.match(res.stdout, /uncommitted changes/);
});

test("standard, e2e and accept SKIP after a static failure, unless --only names them", (t) => {
  const { repo, env } = fixture(t);
  onBranch(repo, { "src/a.js": "export const a = 1;\n" });
  write(repo, { "src/later.js": "export const later = 1;\n" });

  const skipped = gate(repo, env, "FX-01");
  assert.equal(skipped.result.checks.standard, "SKIP");
  assert.equal(skipped.result.checks.e2e, "SKIP");
  assert.equal(skipped.result.checks.accept, "SKIP");
  assert.match(skipped.stdout, /\[SKIP\] standard/);

  const only = gate(repo, env, "FX-01", "--only", "standard,accept");
  assert.equal(only.code, 0);
  assert.equal(only.result.status, "PASS");
  assert.equal(only.result.checks.standard, "PASS");
  assert.equal(only.result.checks.accept, "PASS");
  assert.equal(only.result.checks["clean-tree"], undefined);
});

test("boundary: a file outside the owned globs fails", (t) => {
  const { repo, env } = fixture(t);
  onBranch(repo, { "elsewhere/x.js": "export const x = 1;\n" });

  const res = gate(repo, env, "FX-01");
  assert.equal(res.code, 1);
  assert.equal(res.result.checks.boundary, "FAIL");
  assert.match(res.stdout, /elsewhere\/x\.js: outside this task's owned globs/);
});

test("boundary: a file under alwaysAllowed passes", (t) => {
  const { repo, env } = fixture(t, { plan: { alwaysAllowed: ["package-lock.json", "docs/adr/DRAFT-*.md"] } });
  onBranch(repo, { "package-lock.json": "{}\n", "docs/adr/DRAFT-fx-01-note.md": "# a draft\n" });

  const res = gate(repo, env, "FX-01");
  assert.equal(res.code, 0);
  assert.equal(res.result.checks.boundary, "PASS");
});

test("boundary: a coordinator-owned file inside owned still fails, unless the task is the coordinator's", (t) => {
  const plan = { coordinatorOwned: ["docs/plan/**"] };
  const owned = ["src/**", "docs/plan/notes.md"];

  const worker = fixture(t, { tasks: [{ ...TASK, owned }], plan });
  onBranch(worker.repo, { "docs/plan/notes.md": "a note\n" });
  const blocked = gate(worker.repo, worker.env, "FX-01");
  assert.equal(blocked.code, 1);
  assert.equal(blocked.result.checks.boundary, "FAIL");
  assert.match(blocked.stdout, /docs\/plan\/notes\.md: coordinator-owned/);

  const coordinator = fixture(t, { tasks: [{ ...TASK, owned, coordinator: true }], plan });
  onBranch(coordinator.repo, { "docs/plan/notes.md": "a note\n" });
  const allowed = gate(coordinator.repo, coordinator.env, "FX-01");
  assert.equal(allowed.code, 0);
  assert.equal(allowed.result.checks.boundary, "PASS");
});

test("secrets: a key-shaped added line fails", (t) => {
  // Built from parts: this file's own added lines are scanned by the same check.
  const keyish = join("sk", "_", "live", "_") + "A1b2C3d4E5f6G7h8I9j0";
  const { repo, env } = fixture(t);
  onBranch(repo, { "src/a.js": `export const client = "${keyish}";\n` });

  const res = gate(repo, env, "FX-01");
  assert.equal(res.code, 1);
  assert.equal(res.result.checks.secrets, "FAIL");
  assert.match(res.stdout, /\[FAIL\] secrets/);
  assert.match(res.stdout, /src\/a\.js: looks like a committed/);
});

test("secrets: a committed environment file fails even when the task owns it", (t) => {
  const dotenv = join(".", "env");
  const { repo, env } = fixture(t, { tasks: [{ ...TASK, owned: ["src/**", dotenv] }] });
  onBranch(repo, { [dotenv]: "GREETING=hello\n" });

  const res = gate(repo, env, "FX-01");
  assert.equal(res.code, 1);
  assert.equal(res.result.checks.boundary, "PASS");
  assert.equal(res.result.checks.secrets, "FAIL");
  assert.match(res.stdout, /never commit this file/);
});

// `test(` lines for a fixture's own test file, and the weakener tokens the gate hunts for,
// both built at runtime (AGENTS.md rule 17).
const cases = (n) => Array.from({ length: n }, (_, i) => `test("case ${i}", () => {});`).join("\n") + "\n";
const FOCUSED = `${join("it", ".", "only")}("a case", () => {});\n`;
const SKIPPED = `${join("test", ".", "skip")}("a case", () => {});\n`;

test("test-integrity: a focused test and a skipped test both fail", (t) => {
  const focused = fixture(t);
  onBranch(focused.repo, { "src/a.test.mjs": FOCUSED });
  const one = gate(focused.repo, focused.env, "FX-01");
  assert.equal(one.code, 1);
  assert.equal(one.result.checks["test-integrity"], "FAIL");
  assert.match(one.stdout, /focused or skipped test/);

  const skipped = fixture(t);
  onBranch(skipped.repo, { "src/a.test.mjs": SKIPPED });
  const two = gate(skipped.repo, skipped.env, "FX-01");
  assert.equal(two.code, 1);
  assert.equal(two.result.checks["test-integrity"], "FAIL");
  assert.match(two.stdout, /focused or skipped test/);
});

test("test-integrity: a monotonic count that falls fails, one that grows passes", (t) => {
  const monotonic = [{ file: "test/suite.test.mjs", pattern: "\\btest\\(" }];
  const setup = {
    tasks: [{ ...TASK, owned: ["test/**"] }],
    config: { monotonic },
    files: { "test/suite.test.mjs": cases(3) },
  };

  const shrunk = fixture(t, setup);
  onBranch(shrunk.repo, { "test/suite.test.mjs": cases(2) });
  const fell = gate(shrunk.repo, shrunk.env, "FX-01");
  assert.equal(fell.code, 1);
  assert.equal(fell.result.checks["test-integrity"], "FAIL");
  assert.match(fell.stdout, /fell from 3 to 2: shared suites only grow/);

  const grown = fixture(t, setup);
  onBranch(grown.repo, { "test/suite.test.mjs": cases(4) });
  const grew = gate(grown.repo, grown.env, "FX-01");
  assert.equal(grew.code, 0);
  assert.equal(grew.result.checks["test-integrity"], "PASS");
});

const INVARIANTS = [
  {
    name: "no-fixture-token",
    pattern: "FORBIDDEN_IN_FIXTURES",
    except: ["src/legacy/**"],
    message: "the fixture's own rule, for the test",
  },
];
const offending = `export const label = "FORBIDDEN_IN_FIXTURES";\n`;

test("invariants: a matching added line fails", (t) => {
  const { repo, env } = fixture(t, { config: { invariants: INVARIANTS } });
  onBranch(repo, { "src/a.js": offending });

  const res = gate(repo, env, "FX-01");
  assert.equal(res.code, 1);
  assert.equal(res.result.checks.invariants, "FAIL");
  assert.match(res.stdout, /no-fixture-token: src\/a\.js/);
  assert.match(res.stdout, /the fixture's own rule, for the test/);
});

test("invariants: the same line in an except file passes", (t) => {
  const { repo, env } = fixture(t, { config: { invariants: INVARIANTS } });
  onBranch(repo, { "src/legacy/a.js": offending });

  const res = gate(repo, env, "FX-01");
  assert.equal(res.code, 0);
  assert.equal(res.result.checks.invariants, "PASS");
});

test("invariants: the same text in a comment line passes", (t) => {
  const { repo, env } = fixture(t, { config: { invariants: INVARIANTS } });
  onBranch(repo, { "src/a.js": `${join("/", "/")} FORBIDDEN_IN_FIXTURES, and why it is named here\n` });

  const res = gate(repo, env, "FX-01");
  assert.equal(res.code, 0);
  assert.equal(res.result.checks.invariants, "PASS");
});

test("accept: the task's own commands decide it", (t) => {
  const failing = fixture(t, { tasks: [{ ...TASK, accept: ["false"] }] });
  onBranch(failing.repo, { "src/a.js": "export const a = 1;\n" });
  const bad = gate(failing.repo, failing.env, "FX-01");
  assert.equal(bad.code, 1);
  assert.equal(bad.result.status, "FAIL");
  assert.equal(bad.result.checks.accept, "FAIL");
  assert.match(bad.stdout, /\[FAIL\] accept/);

  const passing = fixture(t, { tasks: [{ ...TASK, accept: ["true"] }] });
  onBranch(passing.repo, { "src/a.js": "export const a = 1;\n" });
  const good = gate(passing.repo, passing.env, "FX-01");
  assert.equal(good.code, 0);
  assert.equal(good.result.checks.accept, "PASS");
});

test("standard: a failing standard command fails the gate, and an empty list is a failure too", (t) => {
  const failing = fixture(t, { config: { standard: ["false"] } });
  onBranch(failing.repo, { "src/a.js": "export const a = 1;\n" });
  const bad = gate(failing.repo, failing.env, "FX-01");
  assert.equal(bad.code, 1);
  assert.equal(bad.result.checks.standard, "FAIL");

  const empty = fixture(t, { config: { standard: [] } });
  onBranch(empty.repo, { "src/a.js": "export const a = 1;\n" });
  const none = gate(empty.repo, empty.env, "FX-01");
  assert.equal(none.code, 1);
  assert.equal(none.result.checks.standard, "FAIL");
  assert.match(none.stdout, /no `standard` commands/);
});

test("brief: a task with no brief is not dispatchable", (t) => {
  const { repo, env } = fixture(t, { tasks: [{ ...TASK, brief: null }] });
  onBranch(repo, { "src/a.js": "export const a = 1;\n" });

  const res = gate(repo, env, "FX-01");
  assert.equal(res.code, 1);
  assert.equal(res.result.checks.brief, "FAIL");
  assert.match(res.stdout, /not dispatchable/);
});
