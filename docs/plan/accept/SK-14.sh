#!/usr/bin/env bash
# Acceptance for SK-14: dispatch, merge and review refuse a second task id instead of acting
# on the last one, and a single id still parses. A machine cap of 0 stops every dispatch at
# the cap check, before any claim or workspace. Run from the repository root.
. docs/plan/accept/lib.sh

R="$SB/repo"; init_repo "$R"; cd "$R" || fail "no repo"
for cmd in dispatch merge review; do
  out="$(SKEIN_MAX_AGENTS=0 skein "$cmd" HS-01 HS-02 2>&1)" && fail "skein $cmd HS-01 HS-02 succeeded"
  printf '%s\n' "$out" | grep -q 'one task per call: got HS-01 and HS-02' \
    || fail "skein $cmd HS-01 HS-02 did not refuse the second task id: $(printf '%s\n' "$out" | tail -2)"
done
out="$(SKEIN_MAX_AGENTS=0 skein dispatch HS-01 --model x HS-02 2>&1)" && fail "a second id after a flag was accepted"
printf '%s\n' "$out" | grep -q 'one task per call' || fail "a second id after a flag was not refused: $out"

out="$(SKEIN_MAX_AGENTS=0 skein dispatch HS-01 2>&1)"
printf '%s\n' "$out" | grep -q 'machine cap reached' || fail "skein dispatch HS-01 did not reach the cap check: $out"
[ -z "$(ls -A "$SKEIN_WORKTREES" 2>/dev/null)" ] || fail "a workspace was created"

echo "ok: SK-14"
