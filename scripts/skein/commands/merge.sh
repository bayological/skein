#!/usr/bin/env bash
# skein merge <TASK> [--no-gate]
# The coordinator's merge: rerun the gate in the worker's worktree, squash-merge the PR,
# close the claim, delete the workspace (its teardown runs), then the task branch, and mark
# the task done in the plan and log it.
# Refuses a task claimed by someone else, never merges a money/pii task without the review
# marker on its PR, and honours --no-gate only when the PR's CI gate check succeeded.
# Local mode (no origin): no PR. The gate runs in the worktree as always, then the branch is
# squash-merged into the base branch here, the review marker is a file, and nothing is pushed.
. "$SKEIN_HOME/lib/common.sh"; require_config; load_board; load_driver
need jq git node; [ -n "$LOCAL_MODE" ] || need gh
TASK=""; NOGATE=""
while [ $# -gt 0 ]; do case "$1" in --no-gate) NOGATE=1; shift ;; -*) die "unknown flag $1" ;; *) TASK="$1"; shift ;; esac; done
[ -n "$TASK" ] || die "usage: skein merge <TASK> [--no-gate]"
t="$(task_json "$TASK")"; ID="$(jq -r .id <<<"$t")"; BRANCH="$(task_branch "$t")"
BASE="$(cfg .baseBranch main)"; GATE_ENTRY="$ROOT/$(cfg .vendor scripts/skein)/skein"

owner="$(board_owner "$ID")"; me="$(me)"
[ -z "$owner" ] || [ "$owner" = "$me" ] || die "$ID is claimed by $owner, not you"

SENSITIVE=""; { [ "$(task_field "$t" money)" = "true" ] || [ "$(task_field "$t" pii)" = "true" ]; } && SENSITIVE=1
if [ -n "$LOCAL_MODE" ]; then
  [ -z "$NOGATE" ] || die "--no-gate trusts a CI gate check, and local mode has no CI: run the gate"
  git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BRANCH" || die "no local branch $BRANCH"
  REVIEW_FILE="$ROOT/$(cfg .reviews docs/plan/reviews)/$ID.md"
  [ -z "$SENSITIVE" ] || grep -q "<!-- skein-review task=$ID " "$REVIEW_FILE" 2>/dev/null \
    || die "$ID is money/pii and $REVIEW_FILE has no skein review marker: run 'skein review $ID' first"
else
  PR="$(gh pr list --head "$BRANCH" --state open --json number,url,reviews,comments -q '.[0]' 2>/dev/null)"
  [ -n "$PR" ] || die "no open PR for branch $BRANCH"
  PRNUM="$(jq -r .number <<<"$PR")"; PRURL="$(jq -r .url <<<"$PR")"
  if [ -n "$SENSITIVE" ]; then
    # Evidence is the marker `skein review` posts, from a collaborator, naming this task.
    n="$(gh pr view "$PRNUM" --json comments -q "[.comments[] | select((.body | test(\"<!-- skein-review task=$ID \")) and (.authorAssociation | IN(\"OWNER\",\"MEMBER\",\"COLLABORATOR\")))] | length" 2>/dev/null || echo 0)"
    [ "$n" -gt 0 ] || die "$ID is money/pii and PR #$PRNUM carries no skein review marker from a collaborator: run 'skein review $ID' first"
  fi
fi

WS="$(driver_find "$ID")"; WPATH=""; [ -n "$WS" ] && WPATH="$(driver_path "$WS")"
if [ -n "$NOGATE" ]; then
  ok="$(gh pr checks "$PRNUM" --json name,state -q '[.[] | select((.name | test("gate"; "i")) and .state=="SUCCESS")] | length' 2>/dev/null || echo 0)"
  [ "$ok" -gt 0 ] || die "--no-gate needs a successful CI gate check on PR #$PRNUM; none found"
  log "--no-gate: CI gate check succeeded on PR #$PRNUM"
else
  [ -n "$WPATH" ] && [ -d "$WPATH" ] || die "no local worktree for $ID to run the gate in (use --no-gate only if CI ran it)"
  fetch_origin "$WPATH"
  [ -x "$WPATH/$(cfg .vendor scripts/skein)/skein" ] && GATE_ENTRY="$WPATH/$(cfg .vendor scripts/skein)/skein"
  ( cd "$WPATH" && bash "$GATE_ENTRY" gate "$ID" ) || die "gate failed for $ID; not merging"
fi

if [ -n "$LOCAL_MODE" ]; then
  # Squash the branch onto the base branch in the coordinator's checkout. The subject follows
  # the PR-title rule ("<type>: <summary> (<ID>)") so `skein plan` sees the task merged.
  [ "$(git -C "$ROOT" symbolic-ref --short HEAD 2>/dev/null)" = "$BASE" ] || die "check out $BASE in $ROOT before merging"
  git -C "$ROOT" diff --quiet && git -C "$ROOT" diff --cached --quiet || die "$ROOT has uncommitted changes: commit or stash them first"
  type="$(task_field "$t" type)"; title="$(task_field "$t" title)"; slug="$(task_field "$t" slug)"
  SUBJECT="${type:-feat}: ${title:-${slug//-/ }} ($ID)"
  BODY="$(git -C "$ROOT" log --reverse --format='- %s' "$BASE..$BRANCH")"
  [ -n "$BODY" ] || die "branch $BRANCH has no commits beyond $BASE: nothing to merge"
  if ! git -C "$ROOT" merge -q --squash "$BRANCH" >/dev/null 2>&1; then
    git -C "$ROOT" reset -q --hard HEAD; die "squash of $BRANCH onto $BASE conflicts: have the worker rebase on $BASE, then gate again"
  fi
  git -C "$ROOT" commit -q -m "$SUBJECT" -m "$BODY" || { git -C "$ROOT" reset -q --hard HEAD; die "commit of the squash failed"; }
  MERGED="$(git -C "$ROOT" rev-parse --short HEAD)"; PRURL=""
  log "merged $BRANCH into $BASE as $MERGED"
else
  gh pr ready "$PRNUM" >/dev/null 2>&1 || true
  # No --delete-branch: gh deletes a local branch that a worktree has checked out by removing the
  # worktree first, so the driver would then find no lifecycle teardown to run and the worker's
  # database, containers and dev servers would outlive it. Delete the workspace, then the branch.
  gh pr merge "$PRNUM" --squash >/dev/null || die "merge failed for PR #$PRNUM"
  MERGED="$PRURL"; log "merged $PRURL"
fi
board_close "$ID" "$PRURL"
[ -n "$WS" ] && driver_delete "$WS"
# Already gone when the repo deletes head branches on merge; nothing to report then.
[ -n "$LOCAL_MODE" ] || env "$COORD_ENV=1" git -C "$ROOT" push -q origin --delete "$BRANCH" 2>/dev/null || true
if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git -C "$ROOT" branch -q -D "$BRANCH" || warn "could not delete local branch $BRANCH (is its worktree still there?)"
fi

# Record: done in the plan, a line in the log, pushed by the coordinator (local mode: committed only).
( cd "$ROOT" && { [ -n "$LOCAL_MODE" ] || git pull -q --rebase origin "$BASE" 2>/dev/null; }
  tmp="$(mktemp)"; jq --arg id "$ID" '(.tasks[] | select(.id==$id)).done = true' "$PLAN" > "$tmp" && mv "$tmp" "$PLAN"
  mkdir -p "$(dirname "$PLAN")"; printf '%s  %s merged %s by %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$ID" "$MERGED" "$me" >> "$(dirname "$PLAN")/LOG.md"
  git add "$PLAN" "$(dirname "$PLAN")/LOG.md" && git commit -q -m "plan: $ID merged ($MERGED)" \
    && { [ -n "$LOCAL_MODE" ] || env "$COORD_ENV=1" git push -q origin "HEAD:$BASE"; } && log "plan updated on $BASE" ) || warn "could not record the merge in the plan; do it by hand"
emit --arg task "$ID" --arg pr "$MERGED" '{task:$task, ok:true, merged:$pr}'
