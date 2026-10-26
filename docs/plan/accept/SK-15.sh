#!/usr/bin/env bash
# Acceptance for SK-15: the gate's default base and the plan's merge detection follow the
# config's baseBranch, locally and through an origin remote. Run from the repository root.
. docs/plan/accept/lib.sh

R="$SB/trunk-repo"; mkdir -p "$R/.skein" "$R/docs/plan/briefs"; cd "$R" || fail "no repo"
git init -q -b trunk
cat > .skein/config.json <<'EOF'
{ "name": "trunk-repo", "prefix": "TB", "baseBranch": "trunk", "plan": "docs/plan/wps.json",
  "standard": ["true"], "board": {"type": "none"}, "driver": {"type": "local"} }
EOF
cat > docs/plan/wps.json <<'EOF'
{ "tasks": [
  { "id": "TB-01", "title": "one", "type": "feat", "slug": "one", "deps": [], "owned": ["one.txt"], "accept": ["true"], "brief": "docs/plan/briefs/TB-01.md" },
  { "id": "TB-02", "title": "two", "type": "feat", "slug": "two", "deps": [], "owned": ["two.txt"], "accept": ["true"], "brief": "docs/plan/briefs/TB-02.md" } ] }
EOF
printf '# TB-01\n' > docs/plan/briefs/TB-01.md; printf '# TB-02\n' > docs/plan/briefs/TB-02.md
sbgit add -A && sbgit commit -qm "plan" || fail "could not commit the plan"
printf 'one\n' > one.txt && sbgit add -A && sbgit commit -qm "feat: one (TB-01)" || fail "could not commit TB-01"

# No origin: the local trunk is the record and the base.
st="$(node "$KIT/lib/plan.mjs" --json | jq -r '.tasks[] | select(.id == "TB-01") | .status')"
[ "$st" = merged ] || fail "plan.mjs does not see TB-01 merged on trunk (status: $st)"
git checkout -q -b feat/two-tb-02 && printf 'two\n' > two.txt && sbgit add -A && sbgit commit -qm "feat: two" || fail "could not commit TB-02"
out="$(node "$KIT/lib/gate.mjs" TB-02 --only boundary 2>&1)"
printf '%s\n' "$out" | grep -q 'SKEIN_GATE_RESULT task=TB-02 base=trunk status=PASS' \
  || fail "the gate did not default to trunk: $(printf '%s\n' "$out" | tail -1)"

# With an origin: origin/trunk.
git init -q --bare -b trunk "$SB/origin.git" && git remote add origin "$SB/origin.git" \
  && sbgit push -q origin trunk feat/two-tb-02 || fail "could not push to the sandbox origin"
st="$(node "$KIT/lib/plan.mjs" --json | jq -r '.tasks[] | select(.id == "TB-01") | .status')"
[ "$st" = merged ] || fail "plan.mjs does not see TB-01 merged on origin/trunk (status: $st)"
out="$(node "$KIT/lib/gate.mjs" TB-02 --only boundary 2>&1)"
printf '%s\n' "$out" | grep -q 'SKEIN_GATE_RESULT task=TB-02 base=origin/trunk status=PASS' \
  || fail "the gate did not default to origin/trunk: $(printf '%s\n' "$out" | tail -1)"

# A config with no baseBranch still means main.
cd "$SB" && R2="$SB/main-repo" && example_repo "$R2" && cd "$R2" || fail "no main repo"
jq 'del(.baseBranch)' .skein/config.json > "$SB/c.json" && mv "$SB/c.json" .skein/config.json && sbgit commit -qam "no baseBranch" || fail "could not edit the config"
git checkout -q -b feat/farewell-function-hs-01 && printf 'export const farewell = 1;\n' > src/farewell.mjs && sbgit add -A && sbgit commit -qm farewell || fail "could not commit"
out="$(node "$KIT/lib/gate.mjs" HS-01 --only boundary 2>&1)"
printf '%s\n' "$out" | grep -q 'base=main status=PASS' || fail "with no baseBranch the gate did not default to main: $(printf '%s\n' "$out" | tail -1)"

echo "ok: SK-15"
