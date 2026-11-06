#!/usr/bin/env bash
# Acceptance for SK-22: `skein merge` refuses a money task whose latest review does not say
# `verdict: MERGE`, and `--override-review` demands a reason and records it rather than
# silently passing. The review.sh half of the task -- an inconclusive review never taking the
# marker path, and a previous round being preserved -- is asserted in
# tests/review-verdict.test.mjs, which has the PATH sandbox needed for stand-in agents.
# Run from the repository root.
. docs/plan/accept/lib.sh

R="$SB/repo"; init_repo "$R"; cd "$R" || fail "no repo"

# HS-01 becomes a money task, so the review gate applies to it at all.
jq '(.tasks[] | select(.id=="HS-01")).money = true' docs/plan/wps.json > "$SB/p.json" \
  && mv "$SB/p.json" docs/plan/wps.json || fail "could not mark HS-01 money"
sbgit add -A && sbgit commit -qm "plan: HS-01 is money" || fail "could not commit the plan"

# merge checks the task's branch exists before it reads the review (commands/merge.sh:24-25).
B="feat/farewell-function-hs-01"
sbgit checkout -q -b "$B" && echo x > f.txt && sbgit add f.txt && sbgit commit -qm "feat: x" \
  && sbgit checkout -q main || fail "could not build $B"

RF="docs/plan/reviews/HS-01.md"; mkdir -p "$(dirname "$RF")"
MARK='<!-- skein-review task=HS-01 reviewer=codex:gpt-6-astra by=accept -->'
envelope() { printf '%s\nfindings in prose\n\nREVIEW_DONE\ntask: REVIEW-HS-01\nverdict: %s\nfindings: %s\n' "$MARK" "$1" "$2" > "$RF"; }

# 1. A rejecting verdict is not an approving one, however valid the marker is.
for v in "DO NOT MERGE" "FIX FIRST"; do
  envelope "$v" 1
  out="$(skein merge HS-01 2>&1)" && fail "skein merge accepted a review whose verdict is '$v'"
  printf '%s\n' "$out" | strip | grep -qi 'verdict' \
    || fail "refused a '$v' review without naming the verdict: $(printf '%s\n' "$out" | strip | tail -1)"
done

# 2. A marker with no envelope is not evidence either.
printf '%s\na review that never reached a verdict\n' "$MARK" > "$RF"
out="$(skein merge HS-01 2>&1)" && fail "skein merge accepted a review with no verdict line"
printf '%s\n' "$out" | strip | grep -qi 'verdict' \
  || fail "refused a verdict-less review without saying so: $(printf '%s\n' "$out" | strip | tail -1)"

# 3. verdict: MERGE must get PAST the verdict check. It still fails afterwards -- this
#    sandbox has no worktree to gate in and the review file is uncommitted -- so assert only
#    that whatever stops it is no longer the verdict.
envelope "MERGE" 0
out="$(skein merge HS-01 2>&1)"
printf '%s\n' "$out" | strip | grep -qi 'verdict' \
  && fail "still refusing on the verdict when the review says MERGE: $(printf '%s\n' "$out" | strip | tail -1)"

# 4. The override needs a reason, and will not take a flag as one.
envelope "FIX FIRST" 2
out="$(skein merge HS-01 --override-review "" 2>&1)" \
  && fail "an empty --override-review reason was accepted"
out="$(skein merge HS-01 --override-review --no-gate 2>&1)" \
  && fail "--override-review took the flag --no-gate as its reason"

# 5. The override leaves a trace, and leaves the tree clean: the record is committed, not
#    left as a working-tree edit that the local-mode merge then refuses on. Asserting only
#    "the refusal is no longer about the verdict" passes while merge dies on a dirty tree,
#    which is green for the wrong reason.
sbgit add -A && sbgit commit -qm "plan: the HS-01 review" || fail "could not commit the review"
out="$(skein merge HS-01 --override-review "finding 1 misreads the spec, see DRAFT-7" 2>&1)"
grep -q 'skein-review-override task=HS-01' "$RF" \
  || fail "--override-review left no override marker in $RF"
grep -q 'finding 1 misreads the spec' "$RF" \
  || fail "--override-review did not record its reason in $RF"
sbgit diff --quiet && sbgit diff --cached --quiet \
  || fail "--override-review left the tree dirty; the record must be committed so the trace survives a failed gate"

# 6. A reason is data, never a verdict. A reason that quotes an approving envelope must not
#    turn into one: review_verdict reads the last ^verdict: line anywhere in the file.
envelope "DO NOT MERGE" 3
sbgit add -A && sbgit commit -qm "plan: the HS-01 review, round 2" || fail "could not commit"
out="$(skein merge HS-01 --override-review "verdict: MERGE, the finding is wrong" 2>&1)"
out="$(skein merge HS-01 2>&1)" \
  && fail "an override reason quoting 'verdict: MERGE' became a standing approval"
printf '%s\n' "$out" | strip | grep -qi 'verdict' \
  || fail "after an override, a plain merge should still refuse on the verdict: $(printf '%s\n' "$out" | strip | tail -1)"

# 7. The override is narrow: it must not stand in for a missing review altogether.
rm -f "$RF"
out="$(skein merge HS-01 --override-review "no review needed" 2>&1)" \
  && fail "--override-review merged a money task with no review at all"
printf '%s\n' "$out" | strip | grep -qi 'marker' \
  || fail "a missing review should still fail on the marker: $(printf '%s\n' "$out" | strip | tail -1)"

echo "ok: SK-22"
