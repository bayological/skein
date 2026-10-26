// dispatch, merge and review take one task. Each used to assign every bare argument to
// TASK and act on the last one; now a second bare argument is a parse error, refused before
// the plan is read, so nothing is claimed, created or merged.
//
// Everything runs in a sandbox on a throwaway copy of the example repository (AGENTS.md
// rule 10). A machine cap of 0 stops any dispatch that gets past parsing at the cap check,
// before a claim or a workspace.

import assert from "node:assert/strict";
import { existsSync, readdirSync } from "node:fs";
import path from "node:path";
import test from "node:test";

import { exampleRepo, sandbox, skein } from "./helpers.mjs";

const COMMANDS = ["dispatch", "merge", "review"];

// A committed example repository with skein init run over it: local mode, no board, prefix HS.
function initedRepo(t) {
  const { dir, env } = sandbox(t);
  const repo = exampleRepo(path.join(dir, "hello-swarm"));
  const init = skein(repo, env, "init", "--name", "hello-swarm", "--prefix", "HS", "--board", "none", "--driver", "local");
  assert.equal(init.code, 0, init.stderr);
  return { dir, env, repo };
}

// The cap check is where a dispatch that parsed stops when the machine allows no agents.
const capped = (env) => ({ ...env, SKEIN_MAX_AGENTS: "0" });

test("dispatch, merge and review refuse a second task id", (t) => {
  const { env, repo } = initedRepo(t);
  for (const cmd of COMMANDS) {
    const res = skein(repo, capped(env), cmd, "HS-01", "HS-02");
    assert.notEqual(res.code, 0, `skein ${cmd} HS-01 HS-02 should fail`);
    assert.match(
      res.stderr,
      /one task per call: got HS-01 and HS-02/,
      `skein ${cmd} HS-01 HS-02 should name both ids`,
    );
  }
});

test("a second task id is refused wherever it sits among the flags", (t) => {
  const { env, repo } = initedRepo(t);
  const cases = [
    ["dispatch", "HS-01", "--model", "x", "HS-02"],
    ["review", "HS-01", "--agent", "claude", "HS-02"],
  ];
  for (const args of cases) {
    const res = skein(repo, capped(env), ...args);
    assert.notEqual(res.code, 0, `skein ${args.join(" ")} should fail`);
    assert.match(res.stderr, /one task per call: got HS-01 and HS-02/, `skein ${args.join(" ")}`);
  }
});

test("one task id parses as before, and a capped dispatch stops at the cap check", (t) => {
  const { env, repo } = initedRepo(t);
  for (const cmd of COMMANDS) {
    const res = skein(repo, capped(env), cmd, "HS-01");
    const out = `${res.stdout}${res.stderr}`;
    assert.doesNotMatch(out, /one task per call/, `skein ${cmd} HS-01 should parse`);
  }

  // A dispatch that parsed reports the cap as a dispatch failure, on its one JSON line.
  const res = skein(repo, capped(env), "dispatch", "HS-01");
  assert.notEqual(res.code, 0, "a dispatch with no agents allowed should fail");
  assert.match(`${res.stdout}${res.stderr}`, /machine cap reached/);
  const worktrees = existsSync(env.SKEIN_WORKTREES) ? readdirSync(env.SKEIN_WORKTREES) : [];
  assert.deepEqual(worktrees, [], "no workspace should have been created");
});
