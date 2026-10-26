import { strictEqual } from "node:assert/strict";
import test from "node:test";
import { greet } from "../src/greet.mjs";

test("greets a name", () => {
  strictEqual(greet("Ada"), "Hello, Ada!");
});

test("greets the world when the name is empty", () => {
  strictEqual(greet(""), "Hello, world!");
});

test("greets the world when no name is given", () => {
  strictEqual(greet(), "Hello, world!");
});
