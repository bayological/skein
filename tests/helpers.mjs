// Test helpers for the kit's own suite. SK-13 to SK-18 write their tests against this API,
// so the names and the shapes are fixed; add, never rename.
//
// Three rules shape everything here. The kit under test is found from this file, never from
// PATH or the current directory, because the acceptance step runs the suite in a `git
// archive` copy with no .git (docs/plan/accept/SK-00.sh). Every repository a test makes lives
// under os.tmpdir() and is deleted when the test ends, so nothing reaches this repository, a
// remote, GitHub or Superset (AGENTS.md rule 10). Commits are unattended, so they pass an
// invented identity and no signing (rule 12).

import { spawnSync } from "node:child_process";
import { chmodSync, cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** KIT: the absolute path of the directory above tests/, the kit under test. */
export const KIT = path.resolve(fileURLToPath(new URL("..", import.meta.url)));

/**
 * join(...parts): its arguments as one string. Use it to build the tokens the gate's
 * test-integrity and secrets checks hunt for, which must never appear as a literal in a
 * line this repository commits (AGENTS.md rule 17).
 */
export function join(...parts) {
  return parts.join("");
}

/**
 * run(cmd, args, { cwd, env, input }): spawn a command and wait. Returns
 * { code, stdout, stderr } and never throws: a non-zero exit is a result, not an error.
 */
export function run(cmd, args, { cwd, env, input } = {}) {
  const res = spawnSync(cmd, args, {
    cwd,
    env,
    input,
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
    timeout: 120_000,
  });
  if (res.error) return { code: -1, stdout: res.stdout || "", stderr: String(res.error.message) };
  return { code: res.status === null ? -1 : res.status, stdout: res.stdout || "", stderr: res.stderr || "" };
}

const IDENTITY = ["-c", "commit.gpgsign=false", "-c", "user.name=skein test", "-c", "user.email=test@localhost"];

/**
 * git(cwd, ...args): git in cwd, unsigned and as `skein test <test@localhost>`. Returns
 * stdout; throws with stderr when git fails, because a broken fixture is not a test result.
 */
export function git(cwd, ...args) {
  const res = run("git", [...IDENTITY, ...args], { cwd });
  if (res.code !== 0) {
    throw new Error(`git ${args.join(" ")} failed in ${cwd}: ${(res.stderr || res.stdout).trim()}`);
  }
  return res.stdout;
}

/** write(dir, files): write { "relative/path": "content" } under dir, making parents. */
export function write(dir, files) {
  for (const [rel, content] of Object.entries(files)) {
    const file = path.join(dir, rel);
    mkdirSync(path.dirname(file), { recursive: true });
    writeFileSync(file, content);
  }
}

/** makeRepo(dir, files, { branch }): a git repository on `branch` with files, all committed. */
export function makeRepo(dir, files, { branch = "main" } = {}) {
  mkdirSync(dir, { recursive: true });
  git(dir, "init", "-q", "-b", branch);
  write(dir, files);
  git(dir, "add", "-A");
  git(dir, "commit", "-qm", "fixture: initial");
  return dir;
}

/** exampleRepo(dir): a committed copy of KIT/examples/hello-swarm on main, with no remote. */
export function exampleRepo(dir) {
  mkdirSync(dir, { recursive: true });
  cpSync(path.join(KIT, "examples", "hello-swarm"), dir, { recursive: true });
  git(dir, "init", "-q", "-b", "main");
  git(dir, "add", "-A");
  git(dir, "commit", "-qm", "example: hello-swarm");
  return dir;
}

// A brief in the shape `plan.mjs --check` demands: a title, the five sections, every owned
// glob under "You own", and the task id somewhere in the text.
function briefText(task) {
  const owned = (task.owned || []).map((glob) => `- \`${glob}\``).join("\n");
  return [
    `# ${task.id}: ${task.title || "fixture task"}`,
    "",
    "## Objective",
    "A fixture task, for the kit's own tests.",
    "",
    "## Read first",
    "- nothing.",
    "",
    "## You own",
    owned,
    "",
    "## Work",
    "1. Nothing.",
    "",
    "## Acceptance",
    `- \`${(task.accept || []).join("`, `") || "none"}\``,
    "",
  ].join("\n");
}

/**
 * gateRepo(dir, { tasks, config, plan, files, branch }): a committed repository the gate can
 * judge. `config` is merged over the fixture .skein/config.json and `plan` over the fixture
 * docs/plan/wps.json; every task with a `brief` path gets a brief that passes `--check`, and
 * `files` is written last, so a test can replace any of them.
 */
export function gateRepo(dir, { tasks, config = {}, plan = {}, files = {}, branch = "main" } = {}) {
  const skeinConfig = {
    version: 1,
    name: "fixture",
    prefix: "FX",
    baseBranch: branch,
    standard: ["true"],
    board: { type: "none" },
    driver: { type: "local" },
    ...config,
  };
  const tree = {
    ".skein/config.json": `${JSON.stringify(skeinConfig, null, 2)}\n`,
    "docs/plan/wps.json": `${JSON.stringify({ ...plan, tasks }, null, 2)}\n`,
  };
  for (const task of tasks) if (task.brief) tree[task.brief] = briefText(task);
  Object.assign(tree, files);
  return makeRepo(dir, tree, { branch });
}

/** skein(cwd, env, ...args): the kit's bin/skein. */
export function skein(cwd, env, ...args) {
  return run("bash", [path.join(KIT, "bin", "skein"), ...args], { cwd, env });
}

/** plan(cwd, env, ...args): the kit's lib/plan.mjs. */
export function plan(cwd, env, ...args) {
  return run(process.execPath, [path.join(KIT, "lib", "plan.mjs"), ...args], { cwd, env });
}

// The SKEIN_GATE_RESULT line is a contract other repositories parse (AGENTS.md rule 15), so
// parse it the way they do: space-separated key=value, and checks as name:status pairs.
function parseResult(stdout) {
  const line = stdout.split("\n").find((l) => l.startsWith("SKEIN_GATE_RESULT"));
  if (!line) return null;
  const fields = {};
  for (const part of line.trim().split(/\s+/).slice(1)) {
    const at = part.indexOf("=");
    if (at > 0) fields[part.slice(0, at)] = part.slice(at + 1);
  }
  const checks = {};
  for (const pair of (fields.checks || "").split(",").filter(Boolean)) {
    const at = pair.lastIndexOf(":");
    if (at > 0) checks[pair.slice(0, at)] = pair.slice(at + 1);
  }
  return { task: fields.task ?? null, base: fields.base ?? null, status: fields.status ?? null, checks };
}

/**
 * gate(cwd, env, ...args): the kit's lib/gate.mjs. Returns run()'s fields plus `result`, the
 * SKEIN_GATE_RESULT line as { task, base, status, checks }, or null when there is no line.
 */
export function gate(cwd, env, ...args) {
  const res = run(process.execPath, [path.join(KIT, "lib", "gate.mjs"), ...args], { cwd, env });
  return { ...res, result: parseResult(res.stdout) };
}

/**
 * sandbox(t): { dir, env }. `dir` is a fresh temp directory, deleted in t.after. `env` is
 * this process's environment with every SKEIN_* key and GITHUB_HEAD_REF dropped, stand-ins
 * for gh, codex and claude first on PATH, the driver's worktrees, run logs and per-machine
 * config under `dir`, and SKEIN_KIT_GIT set so upgrade never pulls a real checkout.
 */
export function sandbox(t) {
  const dir = mkdtempSync(path.join(os.tmpdir(), "skein-test-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const bin = path.join(dir, "bin");
  mkdirSync(bin, { recursive: true });
  for (const name of ["gh", "codex", "claude"]) {
    const file = path.join(bin, name);
    writeFileSync(file, "#!/bin/sh\nexit 1\n");
    chmodSync(file, 0o755);
  }
  const machine = path.join(dir, "machine.json");
  writeFileSync(machine, '{ "maxAgents": 3 }\n');
  const env = {};
  for (const [key, value] of Object.entries(process.env)) {
    if (key.startsWith("SKEIN_") || key === "GITHUB_HEAD_REF") continue;
    env[key] = value;
  }
  env.PATH = `${bin}${path.delimiter}${process.env.PATH || ""}`;
  env.SKEIN_WORKTREES = path.join(dir, "worktrees");
  env.SKEIN_RUNS = path.join(dir, "runs");
  env.SKEIN_USER_CONFIG = machine;
  env.SKEIN_KIT_GIT = "1";
  return { dir, env };
}

/**
 * fakeWorkspace(env, repoDir, key, name, envelope): what the local driver records for a
 * workspace called `name` (lib/drivers/local.sh:31-32, :92-98), so status and dispatch see a
 * workspace with no agent running. With `envelope`, also a run log holding that text as one
 * assistant message, the shape driver_read parses (lib/drivers/local.sh:62-71). Returns the
 * workspace path.
 */
export function fakeWorkspace(env, repoDir, key, name, envelope) {
  const runDir = path.join(env.SKEIN_RUNS, path.basename(repoDir));
  const wsPath = path.join(path.dirname(env.SKEIN_WORKTREES), `wt-${key}`);
  mkdirSync(runDir, { recursive: true });
  mkdirSync(wsPath, { recursive: true });
  writeFileSync(
    path.join(runDir, `wt-${key}.meta.json`),
    `${JSON.stringify({ name, tag: "running", path: wsPath, branch: "x" })}\n`,
  );
  if (envelope) {
    const entry = { type: "assistant", message: { content: [{ type: "text", text: envelope }] } };
    writeFileSync(path.join(runDir, `wt-${key}.jsonl`), `${JSON.stringify(entry)}\n`);
  }
  return wsPath;
}
