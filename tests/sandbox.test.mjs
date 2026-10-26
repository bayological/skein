// The helpers themselves, proved against the kit's own example repository. If these pass,
// a failure in gate.test.mjs or plan.test.mjs is the kit's, not the harness's.

import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";

import { exampleRepo, fakeWorkspace, join, run, sandbox, skein } from "./helpers.mjs";

// skein status paints its output; a test reads the text under the colour.
const strip = (text) => text.replace(new RegExp(`${join("\\u001b", "\\[")}[0-9;]*m`, "g"), "");

test("the example repository takes skein init, and the plan lists its three tasks", (t) => {
  const { dir, env } = sandbox(t);
  const repo = exampleRepo(path.join(dir, "hello-swarm"));

  const init = skein(repo, env, "init", "--name", "hello-swarm", "--prefix", "HS", "--board", "none", "--driver", "local");
  assert.equal(init.code, 0, init.stderr);
  assert.match(init.stdout, /skein init done for hello-swarm/);

  const listed = skein(repo, env, "plan");
  assert.equal(listed.code, 0, listed.stderr);
  assert.match(listed.stdout, /3 tasks/);
  for (const id of ["HS-01", "HS-02", "HS-03"]) assert.match(listed.stdout, new RegExp(`^${id}\\s`, "m"));
});

test("a workspace with a done envelope shows as DONE, awaiting gate", (t) => {
  const { dir, env } = sandbox(t);
  const repo = exampleRepo(path.join(dir, "hello-swarm"));
  const name = "feat: farewell function (HS-01)";
  const envelope = [
    `HS_WORKER${join("_", "DONE")}`,
    "task: HS-01",
    "summary: the farewell function, with its test",
    "files: src, test",
    "handoff: none",
  ].join("\n");
  fakeWorkspace(env, repo, "a", name, envelope);

  const res = skein(repo, env, "status");
  assert.equal(res.code, 0, res.stderr);
  const out = strip(res.stdout);
  assert.match(out, /feat: farewell function \(HS-01\)\s+DONE, awaiting gate/);
});

test("the sandbox hides this machine: no SKEIN_ settings leak in, and gh, codex and claude fail", (t) => {
  const { dir, env } = sandbox(t);
  assert.equal(env.SKEIN_USER_CONFIG, path.join(dir, "machine.json"));
  assert.equal(env.SKEIN_KIT_GIT, "1");
  assert.ok(env.PATH.startsWith(path.join(dir, "bin")));
  assert.equal(env.GITHUB_HEAD_REF, undefined);
  for (const key of Object.keys(env)) {
    if (!key.startsWith("SKEIN_")) continue;
    assert.ok(
      ["SKEIN_WORKTREES", "SKEIN_RUNS", "SKEIN_USER_CONFIG", "SKEIN_KIT_GIT"].includes(key),
      `${key} should not reach a sandbox`,
    );
  }
  for (const tool of ["gh", "codex", "claude"]) {
    const res = run(tool, [], { cwd: dir, env });
    assert.equal(res.code, 1, `${tool} should be a stand-in that fails`);
  }
});
