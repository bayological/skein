// The config's baseBranch decides what the two Node programs measure against: the gate's
// default base and the branch whose subjects lib/plan.mjs reads for merges. Judged by the
// SKEIN_GATE_RESULT line and by `plan --json`, never by reading the source.
//
// A repository on `trunk` stands in for one that does not call its base branch main. The
// bash commands already follow the config through base_ref (lib/common.sh:47), so these
// cases mirror it: the branch itself with no origin, origin/<branch> with one.

import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";

import { gate, gateRepo, git, plan, sandbox, write } from "./helpers.mjs";

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

const TASKS = [task("FX-01"), task("FX-02")];

// A repository on `branch`, with FX-01 landed there as a squash-merged subject and FX-02
// still on its own branch, which is what the gate judges.
function fixture(t, { branch = "trunk", config, files } = {}) {
  const { dir, env } = sandbox(t);
  const repo = path.join(dir, "repo");
  gateRepo(repo, { tasks: TASKS, branch, config, files });
  git(repo, "commit", "-q", "--allow-empty", "-m", "feat(fixture): the first task (FX-01) (#1)");
  git(repo, "checkout", "-q", "-b", "feat/fixture-fx-02-fx-02");
  write(repo, { "src/fx-02/a.js": "export const a = 1;\n" });
  git(repo, "add", "-A");
  git(repo, "commit", "-qm", "feat(fixture): the second task's change");
  return { dir, repo, env };
}

// `plan --json`'s verdict on one task.
function status(repo, env, id) {
  const res = plan(repo, env, "--json");
  assert.equal(res.code, 0, res.stderr);
  return JSON.parse(res.stdout).tasks.find((row) => row.id === id).status;
}

test("with no origin the base branch itself is the base and the record", (t) => {
  const { repo, env } = fixture(t);

  assert.equal(status(repo, env, "FX-01"), "merged");

  const res = gate(repo, env, "FX-02", "--only", "boundary");
  assert.equal(res.code, 0, res.stdout + res.stderr);
  assert.equal(res.result.base, "trunk");
  assert.equal(res.result.status, "PASS");
});

test("with an origin the base is origin/<base branch>, and it still carries the record", (t) => {
  const { dir, repo, env } = fixture(t);
  const origin = path.join(dir, "origin.git");
  git(dir, "init", "-q", "--bare", "-b", "trunk", origin);
  git(repo, "remote", "add", "origin", origin);
  git(repo, "push", "-q", "origin", "trunk", "feat/fixture-fx-02-fx-02");

  assert.equal(status(repo, env, "FX-01"), "merged");

  const res = gate(repo, env, "FX-02", "--only", "boundary");
  assert.equal(res.code, 0, res.stdout + res.stderr);
  assert.equal(res.result.base, "origin/trunk");
  assert.equal(res.result.status, "PASS");
});

test("--base overrides the config's base branch", (t) => {
  const { repo, env } = fixture(t, { branch: "main" });
  // A branch at the same commit as main, so the diff is the task's change either way.
  git(repo, "branch", "trunk", "main");

  const dflt = gate(repo, env, "FX-02", "--only", "boundary");
  assert.equal(dflt.result.base, "main");

  const res = gate(repo, env, "FX-02", "--only", "boundary", "--base", "trunk");
  assert.equal(res.code, 0, res.stdout + res.stderr);
  assert.equal(res.result.base, "trunk");
  assert.equal(res.result.status, "PASS");
});

test("a config with no baseBranch key still means main", (t) => {
  const config = {
    version: 1,
    name: "fixture",
    prefix: "FX",
    standard: ["true"],
    board: { type: "none" },
    driver: { type: "local" },
  };
  // `files` is written last, so this config replaces the fixture's, baseBranch and all.
  const { repo, env } = fixture(t, {
    branch: "main",
    files: { ".skein/config.json": `${JSON.stringify(config, null, 2)}\n` },
  });
  assert.equal(JSON.parse(git(repo, "show", "HEAD~1:.skein/config.json")).baseBranch, undefined);

  assert.equal(status(repo, env, "FX-01"), "merged");

  const res = gate(repo, env, "FX-02", "--only", "boundary");
  assert.equal(res.code, 0, res.stdout + res.stderr);
  assert.equal(res.result.base, "main");
  assert.equal(res.result.status, "PASS");
});
