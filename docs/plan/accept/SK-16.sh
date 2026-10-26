#!/usr/bin/env bash
# Acceptance for SK-16: skein dispatch refuses a task whose owned globs overlap a task still in
# flight (claimed on the board or with a workspace here), names it, and lets --allow-overlap
# through. A machine cap of 0 stops every dispatch that gets past the check at the cap
# check, before any claim or workspace. Run from the repository root.
. docs/plan/accept/lib.sh

R="$SB/repo"; init_repo "$R"; cd "$R" || fail "no repo"
# HS-02 also owns src/farewell.mjs, which HS-01 owns: the two overlap. The brief lists it too,
# so the brief check passes.
jq '(.tasks[] | select(.id == "HS-02") | .owned) += ["src/farewell.mjs"]' docs/plan/wps.json > "$SB/p.json" \
  && mv "$SB/p.json" docs/plan/wps.json || fail "could not edit the plan"
awk '{ print } /^## You own/ { print "- `src/farewell.mjs`" }' docs/plan/briefs/HS-02.md > "$SB/b.md" \
  && mv "$SB/b.md" docs/plan/briefs/HS-02.md || fail "could not edit the brief"
sbgit commit -qam "plan: HS-02 overlaps HS-01" || fail "could not commit the plan"

node "$KIT/lib/plan.mjs" --overlapping HS-02 | grep -qx 'HS-01' || fail "plan.mjs --overlapping HS-02 does not list HS-01"
node "$KIT/lib/plan.mjs" --overlapping HS-03 | grep -q . && fail "plan.mjs --overlapping HS-03 lists a task, but HS-03 overlaps none"

# HS-01 is in flight: the local driver has a workspace for it.
fake_workspace "$R" hs01 "feat: farewell function (HS-01)"
out="$(SKEIN_MAX_AGENTS=0 skein dispatch HS-02 2>&1)" && fail "dispatch HS-02 succeeded while HS-01 is in flight"
printf '%s\n' "$out" | grep -q 'HS-02 overlaps HS-01, which is in flight' \
  || fail "dispatch HS-02 did not refuse the overlap with HS-01: $(printf '%s\n' "$out" | tail -2)"
out="$(SKEIN_MAX_AGENTS=0 skein dispatch HS-02 --allow-overlap 2>&1)"
printf '%s\n' "$out" | grep -q 'machine cap reached' || fail "--allow-overlap did not get past the overlap check: $(printf '%s\n' "$out" | tail -2)"

# Once HS-01 has no workspace, nothing is in flight and HS-02 gets past the check.
rm -f "$SKEIN_RUNS/$(basename "$R")/wt-hs01.meta.json"
out="$(SKEIN_MAX_AGENTS=0 skein dispatch HS-02 2>&1)"
printf '%s\n' "$out" | grep -q 'machine cap reached' || fail "with HS-01 not in flight, dispatch HS-02 did not reach the cap check: $(printf '%s\n' "$out" | tail -2)"
[ -z "$(ls -A "$SKEIN_WORKTREES" 2>/dev/null)" ] || fail "a workspace was created"

echo "ok: SK-16"
