// `.skein/config.json` carries a `version`, and this kit reads version 1. A config written
// for a later kit must stop every command that requires a config and the gate itself, rather
// than being served with defaults for keys whose meaning changed and judged by only the
// checks this gate knows.
//
// Judged by behaviour: exit codes, the message on stderr, doctor's lines, and whether the
// gate prints a SKEIN_GATE_RESULT line at all. Nothing here reads the kit's source.

import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

import { exampleRepo, gate, gateRepo, git, sandbox, skein } from "./helpers.mjs";

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

// The example repository, `skein init`ed the way the acceptance script does it and committed,
// so brief, status, dispatch and doctor all have a real repo to work on.
function initialised(t) {
  const { dir, env } = sandbox(t);
  const repo = exampleRepo(path.join(dir, "repo"));
  const res = skein(repo, env, "init", "--name", "hello-swarm", "--prefix", "HS", "--board", "none", "--driver", "local");
  assert.equal(res.code, 0, res.stdout + res.stderr);
  git(repo, "add", "-A");
  git(repo, "commit", "-qm", "chore: skein init");
  return { repo, env };
}

// A repository the gate can judge, on main, with a version 1 config.
function judged(t) {
  const { dir, env } = sandbox(t);
  return { repo: gateRepo(path.join(dir, "repo"), { tasks: [TASK] }), env };
}

const CONFIG = ".skein/config.json";
const configOf = (repo) => JSON.parse(readFileSync(path.join(repo, CONFIG), "utf8"));
/** setConfig(repo, edit): rewrite the config, `edit` applied to the parsed object. */
function setConfig(repo, edit) {
  const config = configOf(repo);
  edit(config);
  writeFileSync(path.join(repo, CONFIG), `${JSON.stringify(config, null, 2)}\n`);
}
/** rawConfig(repo, text): put `text` in the config, whatever it is. */
function rawConfig(repo, text) {
  writeFileSync(path.join(repo, CONFIG), text);
}
// Terminal colour codes, which doctor writes and a grep over its output must not trip on.
const strip = (s) => s.replace(/\u001b\[[0-9;]*m/g, "");

test("a version 1 config, and one with no version key, are served", (t) => {
  const { repo, env } = initialised(t);
  assert.equal(configOf(repo).version, 1);

  for (const label of ["version 1", "no version key"]) {
    if (label === "no version key") setConfig(repo, (c) => delete c.version);

    const brief = skein(repo, env, "brief", "HS-01", "--check");
    assert.equal(brief.code, 0, `${label}: ${brief.stdout + brief.stderr}`);
    const status = skein(repo, env, "status");
    assert.equal(status.code, 0, `${label}: ${status.stdout + status.stderr}`);

    // A config with no version key is version 1, so doctor reports it as one either way.
    const doctor = skein(repo, env, "doctor");
    const line = strip(doctor.stdout).split("\n").find((l) => l.includes(CONFIG));
    assert.match(line, /version 1\)/, `${label}: ${line}`);
    assert.doesNotMatch(strip(doctor.stdout), /understands version/, label);
  }
});

test("the gate judges a version 1 config, and one with no version key", (t) => {
  for (const label of ["version 1", "no version key"]) {
    const { repo, env } = judged(t);
    if (label === "no version key") setConfig(repo, (c) => delete c.version);

    const res = gate(repo, env, "FX-01", "--only", "boundary");
    assert.equal(res.code, 0, `${label}: ${res.stdout + res.stderr}`);
    assert.equal(res.result.status, "PASS", label);
  }
});

test("a version 2 config stops every command that requires a config", (t) => {
  const { repo, env } = initialised(t);
  setConfig(repo, (c) => (c.version = 2));
  const expected = `${CONFIG} is version 2; this kit understands version 1: upgrade the kit`;

  for (const args of [["brief", "HS-01", "--check"], ["status"], ["dispatch", "HS-01"]]) {
    const res = skein(repo, { ...env, SKEIN_MAX_AGENTS: "0" }, ...args);
    assert.notEqual(res.code, 0, `skein ${args.join(" ")} accepted it: ${res.stdout}`);
    assert.ok(res.stderr.includes(expected), `skein ${args.join(" ")}: ${res.stderr}`);
  }
});

test("a version 2 config stops the gate, with no result line", (t) => {
  const { repo, env } = judged(t);
  setConfig(repo, (c) => (c.version = 2));

  const res = gate(repo, env, "FX-01");
  assert.equal(res.code, 2, res.stdout + res.stderr);
  assert.match(res.stderr, /is version 2; this kit understands version 1: upgrade the kit/);
  assert.equal(res.result, null, res.stdout);
  assert.ok(!res.stdout.includes("SKEIN_GATE_RESULT"), res.stdout);
});

test("a version 2 config is a doctor problem", (t) => {
  const { repo, env } = initialised(t);
  setConfig(repo, (c) => (c.version = 2));

  const res = skein(repo, env, "doctor");
  assert.equal(res.code, 1, res.stdout + res.stderr);
  assert.match(strip(res.stdout), /✗ .*is version 2; this kit understands version 1: upgrade the kit/);
});

test("a version that is not a whole number is refused by both", (t) => {
  // The version is quoted the way JSON writes it, so a string version is tellable from the
  // number it looks like.
  for (const version of ["1", 1.5]) {
    const expected = `${CONFIG} has version ${JSON.stringify(version)}; this kit understands version 1`;

    const { repo, env } = initialised(t);
    setConfig(repo, (c) => (c.version = version));
    const status = skein(repo, env, "status");
    assert.notEqual(status.code, 0, `${expected}: ${status.stdout}`);
    assert.ok(status.stderr.includes(expected), `skein status: ${status.stderr}`);

    const judge = judged(t);
    setConfig(judge.repo, (c) => (c.version = version));
    const res = gate(judge.repo, judge.env, "FX-01");
    assert.equal(res.code, 2, res.stdout + res.stderr);
    assert.ok(res.stderr.includes(expected), `the gate: ${res.stderr}`);
    assert.equal(res.result, null, res.stdout);
  }
});

test("a config that is not valid JSON is refused by both, not read as defaults", (t) => {
  const { repo, env } = initialised(t);
  rawConfig(repo, "{ not json\n");
  const expected = `${CONFIG} is not valid JSON`;

  const status = skein(repo, env, "status");
  assert.notEqual(status.code, 0, status.stdout);
  assert.ok(status.stderr.includes(expected), `skein status: ${status.stderr}`);

  const judge = judged(t);
  rawConfig(judge.repo, "{ not json\n");
  const res = gate(judge.repo, judge.env, "FX-01");
  assert.equal(res.code, 2, res.stdout + res.stderr);
  assert.ok(res.stderr.includes(expected), `the gate: ${res.stderr}`);
  assert.equal(res.result, null, res.stdout);
});
