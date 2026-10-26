#!/usr/bin/env bash
# HS-01, the honest round: add src/farewell.mjs and its three tests, and nothing else.
# Run by docs/demo/claude in the task's worktree. Prints the commit subject.
set -euo pipefail

cat > src/farewell.mjs <<'MJS'
// The mirror of greet(name). Added by HS-01.
export function farewell(name) {
  return `Goodbye, ${name || "world"}.`;
}
MJS

cat > test/farewell.test.mjs <<'MJS'
import { strictEqual } from "node:assert/strict";
import test from "node:test";
import { farewell } from "../src/farewell.mjs";

test("says goodbye to a name", () => {
  strictEqual(farewell("Ada"), "Goodbye, Ada.");
});

test("says goodbye to the world when the name is empty", () => {
  strictEqual(farewell(""), "Goodbye, world.");
});

test("says goodbye to the world when no name is given", () => {
  strictEqual(farewell(), "Goodbye, world.");
});
MJS

echo "feat(farewell): farewell function (HS-01)"
