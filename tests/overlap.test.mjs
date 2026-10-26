// Owned paths are the lock between tasks, and dispatch now applies it: a task whose owned
// globs overlap a task still in flight is refused, by name, before anything is claimed or
// created. `--allow-overlap` skips the check for a coordinator who knows better.
//
// Everything runs in a sandbox on a throwaway copy of the example repository (AGENTS.md
// rule 10). "In flight" here is the local driver's side of it: a workspace record for the
// other task, written by fakeWorkspace, with no agent behind it. A machine cap of 0 stops
// every dispatch that gets past the overlap check at the cap check, before a claim or a
// workspace, so the cap message is how a test says "the check let it through".

import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

import { exampleRepo, fakeWorkspace, git, plan, sandbox, skein } from "./helpers.mjs";

// The workspace name the local driver records for HS-01, and what driver_find matches on:
// the id in parentheses (lib/drivers/local.sh:99).
const HS01_WS = "feat: farewell function (HS-01)";

// The cap check is where a dispatch that got past the overlap check stops.
const capped = (env) => ({ ...env, SKEIN_MAX_AGENTS: "0" });

function editPlan(repo, edit) {
  const file = path.join(repo, "docs/plan/wps.json");
  const doc = JSON.parse(readFileSync(file, "utf8"));
  edit(doc, (id) => doc.tasks.find((t) => t.id === id));
  writeFileSync(file, `${JSON.stringify(doc, null, 2)}\n`);
}

/**
 * A committed example repository with skein init run over it (local mode, no board, prefix
 * HS), in which HS-02 also owns src/farewell.mjs, which HS-01 owns: the two overlap. The
 * glob goes under "You own" in HS-02's brief too, or `plan.mjs --check` refuses the task.
 * HS-03 keeps its own disjoint paths but loses its deps, so it is ready to dispatch and can
 * show that a task overlapping nothing in flight gets through.
 */
function overlapRepo(t) {
  const { dir, env } = sandbox(t);
  const repo = exampleRepo(path.join(dir, "hello-swarm"));
  const init = skein(repo, env, "init", "--name", "hello-swarm", "--prefix", "HS", "--board", "none", "--driver", "local");
  assert.equal(init.code, 0, init.stderr);

  editPlan(repo, (doc, task) => {
    task("HS-02").owned.push("src/farewell.mjs");
    task("HS-03").deps = [];
  });
  const brief = path.join(repo, "docs/plan/briefs/HS-02.md");
  writeFileSync(
    brief,
    readFileSync(brief, "utf8").replace(/^(## You own\n)/m, "$1- `src/farewell.mjs`\n"),
  );

  git(repo, "add", "-A");
  git(repo, "commit", "-qm", "plan: HS-02 overlaps HS-01");
  const check = plan(repo, env, "--check", "HS-02");
  assert.equal(check.code, 0, `the edited HS-02 should still pass --check: ${check.stderr}`);
  return { dir, env, repo };
}

const lines = (res) => res.stdout.split("\n").filter(Boolean);

test("plan --overlapping lists the unmerged tasks that share a path", (t) => {
  const { env, repo } = overlapRepo(t);

  assert.deepEqual(lines(plan(repo, env, "--overlapping", "HS-02")), ["HS-01"]);
  assert.deepEqual(lines(plan(repo, env, "--overlapping", "HS-01")), ["HS-02"], "overlap is symmetric");
  assert.deepEqual(lines(plan(repo, env, "--overlapping", "HS-03")), [], "HS-03 shares no path");

  // A merged task has let its globs go, whatever else is true of it.
  editPlan(repo, (doc, task) => { task("HS-01").done = true; });
  assert.deepEqual(lines(plan(repo, env, "--overlapping", "HS-02")), [], "a merged task is not an overlap");
});

test("plan --overlapping exits 2 for an id that is not in the plan", (t) => {
  const { env, repo } = overlapRepo(t);
  const res = plan(repo, env, "--overlapping", "HS-99");
  assert.equal(res.code, 2);
  assert.match(res.stderr, /skein plan: task HS-99 not in docs\/plan\/wps\.json/);
  assert.equal(res.stdout, "");
});

test("dispatch refuses a task that overlaps one in flight, and names it", (t) => {
  const { env, repo } = overlapRepo(t);
  fakeWorkspace(env, repo, "hs01", HS01_WS);

  const res = skein(repo, capped(env), "dispatch", "HS-02");
  assert.equal(res.code, 1, `dispatch HS-02 should fail: ${res.stdout}${res.stderr}`);
  // The refusal goes through fail(), so it is the one JSON line every command ends with.
  const out = JSON.parse(res.stdout.trim().split("\n").pop());
  assert.equal(out.task, "HS-02");
  assert.equal(out.ok, false);
  assert.match(out.error, /HS-02 overlaps HS-01, which is in flight/);
  assert.match(out.error, /--allow-overlap/, "the refusal names the way past it");

  // Refused before any side effect: the cap was never even counted.
  assert.doesNotMatch(`${res.stdout}${res.stderr}`, /machine cap reached/);
  const worktrees = existsSync(env.SKEIN_WORKTREES) ? readdirSync(env.SKEIN_WORKTREES) : [];
  assert.deepEqual(worktrees, [], "no workspace should have been created");
});

test("--allow-overlap gets past the check", (t) => {
  const { env, repo } = overlapRepo(t);
  fakeWorkspace(env, repo, "hs01", HS01_WS);

  const res = skein(repo, capped(env), "dispatch", "HS-02", "--allow-overlap");
  const out = `${res.stdout}${res.stderr}`;
  assert.doesNotMatch(out, /overlaps HS-01/, "--allow-overlap should skip the overlap check");
  assert.match(out, /machine cap reached/, "and reach the cap check");
  const worktrees = existsSync(env.SKEIN_WORKTREES) ? readdirSync(env.SKEIN_WORKTREES) : [];
  assert.deepEqual(worktrees, [], "no workspace should have been created");
});

test("a task that overlaps nothing in flight gets past the check", (t) => {
  const { env, repo } = overlapRepo(t);
  fakeWorkspace(env, repo, "hs01", HS01_WS);

  // HS-03 overlaps neither HS-01 nor HS-02, so HS-01 being in flight is none of its business.
  let res = skein(repo, capped(env), "dispatch", "HS-03");
  assert.match(`${res.stdout}${res.stderr}`, /machine cap reached/, `HS-03: ${res.stdout}${res.stderr}`);

  // And once HS-01 has no workspace, nothing is in flight and HS-02 gets through too.
  rmSync(path.join(env.SKEIN_RUNS, path.basename(repo), "wt-hs01.meta.json"));
  res = skein(repo, capped(env), "dispatch", "HS-02");
  assert.match(`${res.stdout}${res.stderr}`, /machine cap reached/, `HS-02: ${res.stdout}${res.stderr}`);
});
