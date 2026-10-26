// lib/plan.mjs on fixture repositories: what counts as merged, what is waiting on a
// dependency, which ownership globs overlap, what `--check` demands of a brief, and what
// `--dispatchable` prints. Judged by --json and by exit codes, never by reading the source.
//
// Every fixture is on main and at version 1, so these tests pin nothing that the kit-bug
// tasks change.

import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";

import { gateRepo, git, plan, sandbox } from "./helpers.mjs";

function task(id, extra = {}) {
  return {
    id,
    title: `fixture ${id}`,
    type: "feat",
    slug: `fixture-${id.toLowerCase()}`,
    deps: [],
    owned: [`src/${id.toLowerCase()}/**`],
    accept: ["true"],
    money: false,
    pii: false,
    brief: `docs/plan/briefs/${id}.md`,
    ...extra,
  };
}

function fixture(t, tasks, files) {
  const { dir, env } = sandbox(t);
  const repo = path.join(dir, "repo");
  gateRepo(repo, { tasks, files });
  return { repo, env };
}

// A commit on main carrying `subject`: how a squash-merged pull request reaches the record.
function land(repo, subject) {
  git(repo, "commit", "-q", "--allow-empty", "-m", subject);
}

function rows(repo, env) {
  const res = plan(repo, env, "--json");
  assert.equal(res.code, 0, res.stderr);
  const parsed = JSON.parse(res.stdout);
  return { byId: new Map(parsed.tasks.map((r) => [r.id, r])), conflicts: parsed.conflicts };
}

test("merged: the plan's done flag", (t) => {
  const { repo, env } = fixture(t, [task("FX-01", { done: true }), task("FX-02")]);
  const { byId } = rows(repo, env);
  assert.equal(byId.get("FX-01").status, "merged");
  assert.equal(byId.get("FX-02").status, "ready");
});

test("merged: a commit subject on main ending with the id, with or without a pull request number", (t) => {
  const { repo, env } = fixture(t, [task("FX-01"), task("FX-02"), task("FX-03")]);
  land(repo, "feat(fixture): the first task (FX-01)");
  land(repo, "feat(fixture): the second task (FX-02) (#12)");
  land(repo, "chore(fixture): a note about FX-03 and what is left");

  const { byId } = rows(repo, env);
  assert.equal(byId.get("FX-01").status, "merged");
  assert.equal(byId.get("FX-02").status, "merged");
  assert.equal(byId.get("FX-03").status, "ready", "a subject that only mentions the id is not a merge");
});

test("a task waits on its dependency until that dependency merges", (t) => {
  const { repo, env } = fixture(t, [task("FX-01"), task("FX-02", { deps: ["FX-01"] })]);

  const before = rows(repo, env).byId;
  assert.equal(before.get("FX-01").status, "ready");
  assert.equal(before.get("FX-02").status, "waiting on deps");

  land(repo, "feat(fixture): the first task (FX-01)");
  const after = rows(repo, env).byId;
  assert.equal(after.get("FX-01").status, "merged");
  assert.equal(after.get("FX-02").status, "ready");
});

test("overlaps: a directory glob and a file inside it conflict, disjoint globs do not", (t) => {
  const overlapping = fixture(t, [
    task("FX-01", { owned: ["src/**"] }),
    task("FX-02", { owned: ["src/a.js"] }),
  ]);
  const clash = rows(overlapping.repo, overlapping.env).conflicts;
  assert.equal(clash.length, 1, JSON.stringify(clash));
  assert.deepEqual([clash[0].a, clash[0].b].sort(), ["FX-01", "FX-02"]);
  assert.deepEqual(clash[0].shared, ["src/**"]);

  const disjoint = fixture(t, [
    task("FX-01", { owned: ["src/**"] }),
    task("FX-02", { owned: ["docs/**"] }),
  ]);
  assert.deepEqual(rows(disjoint.repo, disjoint.env).conflicts, []);
});

// A brief in the shape --check demands, so each failing case has exactly one problem.
function brief(id, { owned, sections = ["Objective", "Read first", "You own", "Work", "Acceptance"] } = {}) {
  const body = { "You own": owned.map((glob) => `- \`${glob}\``).join("\n") };
  const text = [`# ${id}: a fixture task`, ""];
  for (const section of sections) {
    text.push(`## ${section}`, body[section] || "Something, for the test.", "");
  }
  return text.join("\n");
}

test("--check: a complete brief passes", (t) => {
  const owned = ["src/one.js", "src/two.js"];
  const { repo, env } = fixture(t, [task("FX-01", { owned })], {
    "docs/plan/briefs/FX-01.md": brief("FX-01", { owned }),
  });

  const res = plan(repo, env, "--check", "FX-01");
  assert.equal(res.code, 0, res.stderr);
  assert.match(res.stdout, /FX-01: ok/);
});

test("--check: a missing section is named", (t) => {
  const owned = ["src/one.js"];
  const { repo, env } = fixture(t, [task("FX-01", { owned })], {
    "docs/plan/briefs/FX-01.md": brief("FX-01", {
      owned,
      sections: ["Objective", "Read first", "You own", "Acceptance"],
    }),
  });

  const res = plan(repo, env, "--check", "FX-01");
  assert.equal(res.code, 1);
  assert.match(res.stderr, /NOT READY/);
  assert.match(res.stderr, /brief lacks a "## Work" section/);
});

test("--check: an owned glob missing from \"You own\" is named", (t) => {
  const { repo, env } = fixture(t, [task("FX-01", { owned: ["src/one.js", "src/two.js"] })], {
    "docs/plan/briefs/FX-01.md": brief("FX-01", { owned: ["src/one.js"] }),
  });

  const res = plan(repo, env, "--check", "FX-01");
  assert.equal(res.code, 1);
  assert.match(res.stderr, /owned glob not listed under "You own": src\/two\.js/);
});

test("--dispatchable lists the ready tasks only", (t) => {
  const { repo, env } = fixture(t, [
    task("FX-01"),
    task("FX-02", { brief: null }),
    task("FX-03", { deps: ["FX-02"] }),
    task("FX-04", { done: true }),
  ]);

  const res = plan(repo, env, "--dispatchable");
  assert.equal(res.code, 0, res.stderr);
  assert.deepEqual(res.stdout.split("\n").filter(Boolean), ["FX-01"]);

  const { byId } = rows(repo, env);
  assert.equal(byId.get("FX-02").status, "no brief");
  assert.equal(byId.get("FX-03").status, "waiting on deps");
  assert.equal(byId.get("FX-04").status, "merged");
});

test("the plan view names every task and its status", (t) => {
  const { repo, env } = fixture(t, [task("FX-01"), task("FX-02", { deps: ["FX-01"] })]);

  const res = plan(repo, env);
  assert.equal(res.code, 0, res.stderr);
  assert.match(res.stdout, /2 tasks, 1 ready, 0 merged/);
  assert.match(res.stdout, /FX-01\s+ready/);
  assert.match(res.stdout, /FX-02\s+waiting on deps\s+/);
});
