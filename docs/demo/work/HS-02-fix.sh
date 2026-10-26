#!/usr/bin/env bash
# HS-02, the fix round: put the three tests back with the expected values the new wording
# gives them. src/greet.mjs already holds the change. Run by docs/demo/claude on resume.
set -euo pipefail

cat > test/greet.test.mjs <<'MJS'
import { strictEqual } from "node:assert/strict";
import test from "node:test";
import { greet } from "../src/greet.mjs";

test("greets a name", () => {
  strictEqual(greet("Ada"), "Good day, Ada.");
});

test("greets the world when the name is empty", () => {
  strictEqual(greet(""), "Good day, world.");
});

test("greets the world when no name is given", () => {
  strictEqual(greet(), "Good day, world.");
});
MJS

echo "fix(greet): restore the three greet tests (HS-02)"
