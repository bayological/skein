#!/usr/bin/env bash
# Acceptance for SK-00: the kit's test suite exists, passes, and fails when any one of the
# gate's or the plan's checks is switched off. Each mutation edits one line in a copy of the
# committed kit; a suite that still passes does not test that check. Run from the repository
# root.
set -u
KIT="$PWD"
fail() { echo "FAIL: $*" >&2; exit 1; }
ls tests/*.test.mjs >/dev/null 2>&1 || fail "no tests/*.test.mjs"
out="$(node --test --test-reporter=tap tests/*.test.mjs 2>&1)" || fail "node --test tests/*.test.mjs does not pass: $(printf '%s\n' "$out" | grep -E '^ *not ok|^# fail' | head -8)"

T="$(mktemp -d)"; trap 'rm -rf "${T:?}"' EXIT
mutate() {  # mutate <label> <file> <exact text> <replacement>
  rm -rf "$T/kit"; mkdir -p "$T/kit"
  git -C "$KIT" archive HEAD | tar -x -C "$T/kit" || fail "cannot copy the committed kit"
  node -e '
    const fs = require("node:fs");
    const [file, from, to] = process.argv.slice(1);
    const src = fs.readFileSync(file, "utf8");
    if (!src.includes(from)) process.exit(3);
    fs.writeFileSync(file, src.replace(from, to));
  ' "$T/kit/$2" "$3" "$4" || fail "$1: the mutation text is gone from $2; update docs/plan/accept/SK-00.sh"
  ( cd "$T/kit" && node --test tests/*.test.mjs >/dev/null 2>&1 ) && fail "$1: the suite still passes with that check switched off"
  echo "ok: $1 is tested"
}
G=lib/gate.mjs; P=lib/plan.mjs
mutate "clean-tree"            $G 'if (status) return record("clean-tree", "FAIL"' 'if (false) return record("clean-tree", "FAIL"'
mutate "boundary"              $G 'if (bad.length) return record("boundary", "FAIL"' 'if (false) return record("boundary", "FAIL"'
mutate "coordinator-owned"     $G 'if (!isCoordinatorTask && coordinator.some((re) => re.test(file)))' 'if (false)'
mutate "secrets"               $G 'if (bad.length) return record("secrets", "FAIL"' 'if (false) return record("secrets", "FAIL"'
mutate "weakener tokens"       $G 'for (const [re, what] of WEAKENERS) if (re.test(text))' 'for (const [re, what] of WEAKENERS) if (false)'
mutate "monotonic counts"      $G 'if (after < before) bad.push(' 'if (false) bad.push('
mutate "invariant patterns"    $G 'if (re.test(text)) bad.push(`${rule.name}' 'if (false) bad.push(`${rule.name}'
mutate "invariant except"      $G 'if (except.some((x) => x.test(file)) || isComment(text)) continue;' 'if (isComment(text)) continue;'
mutate "comment lines skipped" $G 'if (except.some((x) => x.test(file)) || isComment(text)) continue;' 'if (except.some((x) => x.test(file))) continue;'
mutate "accept commands run"   $G 'run("accept", cmds);' 'record("accept", "PASS");'
mutate "skip after a failure"  $G 'if (anyFailed() && !only) record("standard", "SKIP"' 'if (false) record("standard", "SKIP"'
mutate "plan: done flag"       $P 'if (t.done === true) return true;' 'if (false) return true;'
mutate "plan: merge subject"   $P 'return mainSubjects.some((s) => re.test(s));' 'return false;'
mutate "plan: deps"            $P 'const depsMet = (t.deps || []).every(' 'const depsMet = [].every('
mutate "plan: overlaps"        $P 'return pa.startsWith(pb) || pb.startsWith(pa);' 'return false;'
mutate "plan: brief sections"  $P 'for (const h of ["Objective", "Read first", "You own", "Work", "Acceptance"])' 'for (const h of [])'
echo "ok: SK-00"
