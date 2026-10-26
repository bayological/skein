// What `skein init` reads and what it renders. A repository that already has a
// .skein/config.json is the interesting case: every other command reads its name, prefix,
// base, board, driver, envelope and coordinator variable (lib/common.sh), so init has to
// render the same values rather than re-derive them from the folder, and refuse a flag that
// would silently disagree.
//
// Every case runs on a throwaway copy of examples/hello-swarm (prefix HS, board none, driver
// local) under os.tmpdir(), so nothing reaches this repository, a remote or Superset
// (AGENTS.md rule 10).

import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

import { exampleRepo, git, makeRepo, sandbox, skein } from "./helpers.mjs";

const read = (repo, rel) => readFileSync(path.join(repo, rel), "utf8");
const config = (repo) => JSON.parse(read(repo, ".skein/config.json"));

/** A copy of the example in `dir`, with `patch` merged over its config and committed. */
function keptConfigRepo(t, dir, patch = {}) {
  const { dir: sb, env } = sandbox(t);
  const repo = exampleRepo(path.join(sb, dir));
  if (Object.keys(patch).length) {
    writeFileSync(
      path.join(repo, ".skein/config.json"),
      `${JSON.stringify({ ...config(repo), ...patch }, null, 2)}\n`,
    );
    git(repo, "commit", "-qam", "chore: patch the kept config");
  }
  return { repo, env };
}

/** keptConfigRepo, then a committed `skein init`, the state a second run meets. */
function initialised(t, dir, patch) {
  const { repo, env } = keptConfigRepo(t, dir, patch);
  const init = skein(repo, env, "init");
  assert.equal(init.code, 0, init.stderr);
  git(repo, "add", "-A");
  git(repo, "commit", "-qm", "chore: skein init");
  return { repo, env };
}

test("a kept config supplies the values, not the folder name", (t) => {
  // sandbox-copy would derive the name sandbox-copy and the prefix SANDBO.
  const { repo, env } = keptConfigRepo(t, "sandbox-copy");

  const init = skein(repo, env, "init");
  assert.equal(init.code, 0, init.stderr);

  const agents = read(repo, "AGENTS.md");
  assert.match(agents, /HS_WORKER_DONE/, "AGENTS.md should carry the kept config's envelope");
  assert.doesNotMatch(agents, /SANDBO_/, "AGENTS.md should not carry a prefix derived from the folder");
  assert.match(read(repo, "scripts/githooks/pre-push"), /HS_COORDINATOR/);
  assert.match(
    init.stdout,
    /skein init done for hello-swarm \(HS-xx tasks, board=none, driver=local, base=main/,
  );
});

test("a kept envelope and coordinator variable are rendered as they are", (t) => {
  const { repo, env } = keptConfigRepo(t, "sandbox-copy", {
    envelope: "HELLO_WORKER",
    coordinatorEnv: "HELLO_COORD",
  });

  const init = skein(repo, env, "init");
  assert.equal(init.code, 0, init.stderr);
  assert.match(read(repo, "AGENTS.md"), /HELLO_WORKER_DONE/);
  assert.match(read(repo, "scripts/githooks/pre-push"), /HELLO_COORD/);
});

const CONTRADICTIONS = [
  { flag: "--name", value: "x", kept: "hello-swarm" },
  { flag: "--prefix", value: "XX", kept: "HS" },
  { flag: "--base", value: "trunk", kept: "main" },
  { flag: "--board", value: "github", kept: "none" },
  { flag: "--driver", value: "superset", kept: "local" },
];

for (const { flag, value, kept } of CONTRADICTIONS) {
  test(`${flag} ${value} is refused against the kept ${kept}, and writes nothing`, (t) => {
    const { repo, env } = initialised(t, "sandbox-copy");

    const res = skein(repo, env, "init", flag, value);
    assert.notEqual(res.code, 0, `${flag} ${value} should be refused`);
    assert.match(
      res.stderr,
      new RegExp(`${flag} ${value} differs from the kept \\.skein/config\\.json \\(${kept}\\)`),
    );
    assert.equal(git(repo, "status", "--porcelain").trim(), "", "a refused init should write nothing");
  });
}

test("flags that agree with the kept config are accepted", (t) => {
  const { repo, env } = initialised(t, "sandbox-copy");

  const res = skein(
    repo, env, "init",
    "--name", "hello-swarm", "--prefix", "HS", "--base", "main", "--board", "none", "--driver", "local",
  );
  assert.equal(res.code, 0, res.stderr);
  assert.equal(config(repo).prefix, "HS");
});

test("--force-templates lets a flag win and keeps the rest of the config", (t) => {
  const { repo, env } = initialised(t, "sandbox-copy");

  const res = skein(repo, env, "init", "--force-templates", "--prefix", "XX");
  assert.equal(res.code, 0, res.stderr);

  const after = config(repo);
  assert.equal(after.prefix, "XX");
  assert.equal(after.name, "hello-swarm");
  assert.equal(after.board.type, "none");
  assert.equal(after.driver.type, "local");
  assert.equal(after.baseBranch, "main");
  assert.match(read(repo, "AGENTS.md"), /XX_WORKER_DONE/);
});

test("with no config, init still derives the name, prefix and driver", (t) => {
  const { dir, env } = sandbox(t);
  const repo = makeRepo(path.join(dir, "widget-app"), { "README.md": "widget\n" });

  const init = skein(repo, env, "init");
  assert.equal(init.code, 0, init.stderr);

  const written = config(repo);
  assert.equal(written.prefix, "WIDGET");
  assert.equal(written.name, "widget-app");
  assert.equal(written.driver.type, "superset");
  assert.match(read(repo, "AGENTS.md"), /WIDGET_WORKER_DONE/);
});
