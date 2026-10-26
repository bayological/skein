// skein status lists a workspace as a worker only when its name is a task's workspace name,
// the two forms task_ws_name makes (lib/common.sh:71-75), and counts the rest in one line.
// Everything runs in a sandbox on a copy of the example repository (AGENTS.md rule 10).

import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";

import { exampleRepo, fakeWorkspace, join, sandbox, skein } from "./helpers.mjs";

// skein status paints its output; a test reads the text under the colour.
const strip = (text) => text.replace(new RegExp(`${join("\\u001b", "\\[")}[0-9;]*m`, "g"), "");

// Every fake workspace carries the same envelope: HS-01's, done. A workspace listed under
// another id must not be read as HS-01's worker.
const ENVELOPE = [
  `HS_WORKER${join("_", "DONE")}`,
  "task: HS-01",
  "summary: the farewell function, with its test",
  "files: src, test",
  "handoff: none",
].join("\n");

const COUNT = /(\d+) other workspace\(s\) here carry no task id/;

/** repo(t): an initialised copy of the example repository, and the sandbox env around it. */
function repo(t) {
  const { dir, env } = sandbox(t);
  const root = exampleRepo(path.join(dir, "hello-swarm"));
  const init = skein(root, env, "init", "--name", "hello-swarm", "--prefix", "HS", "--board", "none", "--driver", "local");
  assert.equal(init.code, 0, init.stderr);
  return { root, env };
}

/** status(root, env): the workers section of `skein status`, without colour. */
function status(root, env) {
  const res = skein(root, env, "status");
  assert.equal(res.code, 0, res.stderr);
  const out = strip(res.stdout);
  const at = out.indexOf("workers on this machine");
  assert.ok(at >= 0, `no workers section in:\n${out}`);
  return out.slice(at);
}

test("a workspace with no task id in its name is not a worker, and the count line says so", (t) => {
  const { root, env } = repo(t);
  fakeWorkspace(env, root, "coord", "coordinator notes", ENVELOPE);
  fakeWorkspace(env, root, "hs01", "feat: farewell function (HS-01)", ENVELOPE);

  const out = status(root, env);
  assert.doesNotMatch(out, /coordinator notes/);
  assert.match(out, /feat: farewell function \(HS-01\)/);
  assert.equal(out.match(COUNT)?.[1], "1");
});

test("a name that only mentions an id is not a task's workspace name", (t) => {
  const { root, env } = repo(t);
  fakeWorkspace(env, root, "chat", "notes about hs-01 (draft)", ENVELOPE);
  fakeWorkspace(env, root, "hs01", "feat: farewell function (HS-01)", ENVELOPE);

  const out = status(root, env);
  assert.doesNotMatch(out, /notes about hs-01/);
  assert.match(out, /feat: farewell function \(HS-01\)/);
  assert.equal(out.match(COUNT)?.[1], "1");
});

test("the workspace name task_ws_name makes is a worker, and its envelope still reads", (t) => {
  const { root, env } = repo(t);
  fakeWorkspace(env, root, "hs01", "feat: farewell function (HS-01)", ENVELOPE);

  const out = status(root, env);
  assert.match(out, /feat: farewell function \(HS-01\)\s+DONE, awaiting gate/);
  assert.doesNotMatch(out, COUNT);
});

test("the fallback name, the lowercased id alone, is that task's workspace", (t) => {
  const { root, env } = repo(t);
  fakeWorkspace(env, root, "hs02", "hs-02", ENVELOPE);

  const out = status(root, env);
  assert.match(out, /^ {2}hs-02\s/m);
  assert.doesNotMatch(out, COUNT);
  // Read as HS-02, not as an empty id that matches any task: line: HS-01's envelope is not
  // this workspace's, so the state falls through to the no-envelope one.
  assert.doesNotMatch(out, /DONE, awaiting gate/);
  assert.match(out, /hs-02\s+idle at prompt/);
});

test("when no workspace is a task's, the section is none and the count line follows", (t) => {
  const { root, env } = repo(t);
  fakeWorkspace(env, root, "coord", "coordinator notes", ENVELOPE);

  const out = status(root, env);
  assert.match(out, /workers on this machine\n {2}none\n/);
  assert.equal(out.match(COUNT)?.[1], "1");
});

test("with no workspaces at all, the section is none and there is nothing to count", (t) => {
  const { root, env } = repo(t);

  const out = status(root, env);
  assert.match(out, /workers on this machine\n {2}none\n/);
  assert.doesNotMatch(out, COUNT);
});
