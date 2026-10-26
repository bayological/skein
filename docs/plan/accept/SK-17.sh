#!/usr/bin/env bash
# Acceptance for SK-17: skein status lists as workers only workspaces whose name carries a
# task id from the plan, and still reads those workers' state. Run from the repository root.
. docs/plan/accept/lib.sh

R="$SB/repo"; init_repo "$R"; cd "$R" || fail "no repo"
envelope="$(printf 'HS_WORKER_DONE\ntask: HS-01\nsummary: farewell added')"
fake_workspace "$R" coord "coordinator notes" "$envelope"
fake_workspace "$R" hs01 "feat: farewell function (HS-01)" "$envelope"
fake_workspace "$R" chat "notes about hs-01 (draft)" "$envelope"

out="$(skein status 2>&1 | strip)"
printf '%s\n' "$out" | grep -q 'coordinator notes' && fail "skein status lists a workspace with no task id: $(printf '%s\n' "$out" | grep 'coordinator notes')"
printf '%s\n' "$out" | grep -q 'notes about hs-01' && fail "skein status lists a workspace that mentions an id without carrying (<ID>)"
printf '%s\n' "$out" | grep -q '(HS-01) *DONE, awaiting gate' || fail "skein status no longer reports HS-01's worker as done: $(printf '%s\n' "$out" | grep -A1 'workers on')"

echo "ok: SK-17"
