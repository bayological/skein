#!/usr/bin/env bash
# Acceptance for SK-19: after the kit fixes (SK-13 to SK-18) the docs state what the kit does
# now, and every citation still points at what it cites. Run from the repository root.
#
# DOCS_BASE is the commit the fact sheet was last checked against; the kit code there is the
# code it describes. Above its "## Drift" heading the fact sheet is edited line for line, so
# the docs that cite docs/facts/FACTS.md:N (limitations, both diagram sources) keep pointing at
# the same facts. On a line whose statement is unchanged, a citation into the code must move
# exactly as far as the cited code moved since DOCS_BASE. Lines whose statement changed are
# listed at the end for the coordinator to check by hand.
set -u
fail() { echo "FAIL: $*" >&2; exit 1; }
F=docs/facts/FACTS.md
DOCS_BASE=0802bfea2fdc8351eb6ea3d137ccdbc97b6c6e21
git cat-file -e "$DOCS_BASE^{commit}" 2>/dev/null || fail "commit $DOCS_BASE is not in this clone: fetch main"

# 1. Citations resolve: `path:N` or `path:N-M` names a file with at least that many lines.
bad=""
for ref in $(grep -ohE '`[A-Za-z0-9_./-]+:[0-9]+(-[0-9]+)?`' "$F" docs/limitations.md | tr -d '`' | sort -u); do
  file="${ref%%:*}"; lines="${ref#*:}"; last="${lines#*-}"
  if [ ! -f "$file" ]; then bad="$bad $ref(no-file)"; continue; fi
  [ "$(wc -l < "$file" | tr -d ' ')" -ge "$last" ] || bad="$bad $ref(past-end)"
done
[ -z "$bad" ] || fail "citations that do not resolve:$bad"

# 2. Line for line above "## Drift", and code citations moved with the code.
node -e '
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const [base, F] = process.argv.slice(1);
const git = (...a) => execFileSync("git", a, { encoding: "utf8", maxBuffer: 1 << 26 });
const fail = (m) => { console.error("FAIL: " + m); process.exit(1); };
const HUNK = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/gm;
const hunks = (diff) => [...diff.matchAll(HUNK)].map((m) => ({ a: +m[1], b: m[2] === undefined ? 1 : +m[2], c: +m[3], d: m[4] === undefined ? 1 : +m[4] }));

const oldL = git("show", `${base}:${F}`).split("\n"), newL = fs.readFileSync(F, "utf8").split("\n");
const drift = (L) => L.findIndex((l) => /^## Drift\b/.test(l)) + 1;
const dOld = drift(oldL), dNew = drift(newL);
if (!dNew) fail(`${F} has no "## Drift" heading`);
if (dOld !== dNew) fail(`"## Drift" moved from line ${dOld} to line ${dNew}: above it, edit ${F} line for line (replace a line, never add or remove one), so the docs that cite ${F}:N still point at the same facts`);
for (const h of hunks(git("diff", "-U0", "--no-color", base, "--", F))) {
  if (h.a < dOld && (h.b !== h.d || h.a !== h.c)) fail(`${F} lines ${h.a}-${h.a + h.b - 1} became ${h.d} line(s) at ${h.c}: above "## Drift", replace lines one for one`);
}

// Where an old line of a file is now: null when the line itself changed.
const maps = new Map();
const where = (file) => {
  if (!maps.has(file)) {
    const hs = hunks(git("diff", "-U0", "--no-color", base, "--", file));
    maps.set(file, (n) => {
      let off = 0;
      for (const h of hs) {
        if (h.b > 0 && n >= h.a && n < h.a + h.b) return null;
        if ((h.b > 0 ? h.a + h.b - 1 : h.a) < n) off += h.d - h.b;
      }
      return n + off;
    });
  }
  return maps.get(file);
};
const CITE = /`([A-Za-z0-9_./-]+):(\d+)(?:-(\d+))?`/g;
const cites = (s) => [...s.matchAll(CITE)].map((m) => ({ file: m[1], from: +m[2], to: m[3] ? +m[3] : null, text: m[0] }));
const statement = (s) => s.replace(CITE, "`@`");
const wrong = [], byHand = [], intoChanged = [];
for (let i = 0; i < dOld - 1; i++) {
  if (statement(oldL[i]) !== statement(newL[i])) { if (cites(newL[i]).length) byHand.push(i + 1); continue; }
  const o = cites(oldL[i]), n = cites(newL[i]);
  o.forEach((c, k) => {
    if (c.file.endsWith(".md")) return;  // the README was rewritten after the fact sheet: checked by hand
    const m = where(c.file), from = m(c.from), to = c.to === null ? null : m(c.to);
    if (from === null || (c.to !== null && to === null)) intoChanged.push(`${i + 1} ${n[k].text}`);
    const ok = (want, got) => want === null || want === got;
    if (n[k].file !== c.file || !ok(from, n[k].from) || (c.to !== null && !ok(to, n[k].to)))
      wrong.push(`${F}:${i + 1}: ${c.text} should now be \`${c.file}:${from ?? "?"}${c.to === null ? "" : "-" + (to ?? "?")}\`, found ${n[k].text}`);
  });
}
if (wrong.length) fail(`citations that did not move with the code (${wrong.length}):\n  ` + wrong.join("\n  "));
console.log(`ok: ${F} is line for line above "## Drift"; code citations on unchanged statements moved with the code`);
if (byHand.length) console.log(`check by hand, statements that changed: ${F} lines ${byHand.join(", ")}`);
if (intoChanged.length) console.log(`check by hand, unchanged statements citing code that changed: ${intoChanged.join("; ")}`);
' "$DOCS_BASE" "$F" || exit 1

# 3. Every citation of the fact sheet from another doc points at a fact, not a blank line or a
#    heading.
for d in docs/limitations.md docs/assets/architecture.md docs/assets/lifecycle.md; do
  for n in $(grep -oE 'docs/facts/FACTS\.md:[0-9]+' "$d" | cut -d: -f2 | sort -un); do
    sed -n "${n}p" "$F" | grep -qE '^[^#[:space:]]' || fail "$d cites $F:$n, which is a blank line or a heading"
  done
done

# 4. Statements the kit fixes made false are gone.
stale() {  # stale <file> <fixed text> <why>
  grep -qF -- "$2" "$1" && fail "$1 still says \"$2\" ($3)"
  return 0
}
stale $F "no command reads it" "SK-18 reads the version key"
stale $F "regardless of the config's \`baseBranch\`" "SK-15"
stale docs/limitations.md "whatever the config's \`baseBranch\` says" "SK-15"
stale docs/limitations.md "nothing stops two overlapping tasks running at once" "SK-16"
stale README.md "whatever \`baseBranch\` says" "SK-15"
stale README.md "nothing refuses a dispatch of two tasks" "SK-16"
stale examples/hello-swarm/README.md "init takes both from the directory name" "SK-13"
stale docs/demo/setup.sh "matter even though the example ships its own" "SK-13"

# 5. The new behaviour is recorded in the fact sheet, quoting the kit's own words.
recorded() {  # recorded <text> <what>
  grep -qF -- "$1" $F || fail "$F does not record $2 (expected the words: $1)"
}
recorded 'differs from the kept' "init's refusal of a flag that contradicts a kept config (SK-13)"
recorded 'one task per call' "that dispatch, merge and review take one task per call (SK-14)"
recorded '--allow-overlap' "dispatch's overlap refusal and --allow-overlap (SK-16)"
recorded 'carry no task id' "that status lists only task workspaces (SK-17)"
recorded 'this kit understands version' "the config version check (SK-18)"
grep -n 'default base' $F | grep -q 'baseBranch' || fail "$F does not say the gate's default base follows baseBranch (SK-15)"

echo "ok: SK-19"
