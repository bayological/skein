#!/usr/bin/env bash
# skein merge <TASK> [--no-gate] [--override-review "<reason>"]
# The coordinator's merge: rerun the gate in the worker's worktree, squash-merge the PR,
# close the claim, delete the workspace (its teardown runs), then the task branch, and mark
# the task done in the plan and log it.
# Refuses a task claimed by someone else, never merges a money/pii task without the review
# marker on its PR, never merges one whose latest review does not say `verdict: MERGE`, and
# honours --no-gate only when the PR's CI gate check succeeded.
# --override-review "<reason>" covers the verdict and nothing else: the marker, the gate, the
# clean tree and the claim all still apply, and the reason is recorded where the review lives
# before the gate runs, so an override always leaves a trace.
# Local mode (no origin): no PR. The gate runs in the worktree as always, then the branch is
# squash-merged into the base branch here, the review marker is a file, and nothing is pushed.
. "$SKEIN_HOME/lib/common.sh"; require_config; load_board; load_driver
need jq git node; [ -n "$LOCAL_MODE" ] || need gh
TASK=""; NOGATE=""; OVERRIDE=""; OVERRIDDEN=""
while [ $# -gt 0 ]; do case "$1" in
  --no-gate) NOGATE=1; shift ;;
  --override-review)
    [ $# -ge 2 ] || die "--override-review needs a reason: say why the review is wrong, for the record"
    # `skein merge X --override-review --no-gate` must not record "--no-gate" as the reason
    # and silently drop the flag.
    case "$2" in -*) die "--override-review needs a reason, not a flag: got '$2'" ;; esac
    OVERRIDDEN=1; OVERRIDE="$2"; shift 2 ;;
  -*) die "unknown flag $1" ;;
  *) [ -z "$TASK" ] || die "one task per call: got $TASK and $1"; TASK="$1"; shift ;;
esac; done
[ -n "$TASK" ] || die "usage: skein merge <TASK> [--no-gate] [--override-review \"<reason>\"]"
# An override is a record, not a shrug: a blank reason would leave nothing behind to audit.
[ -z "$OVERRIDDEN" ] || [ -n "$(printf '%s' "$OVERRIDE" | tr -d '[:space:]')" ] \
  || die "--override-review needs a reason: say why the review is wrong, for the record"
t="$(task_json "$TASK")"; ID="$(jq -r .id <<<"$t")"; BRANCH="$(task_branch "$t")"
BASE="$(cfg .baseBranch main)"; GATE_ENTRY="$ROOT/$(cfg .vendor scripts/skein)/skein"

owner="$(board_owner "$ID")"; me="$(me)"
[ -z "$owner" ] || [ "$owner" = "$me" ] || die "$ID is claimed by $owner, not you"

SENSITIVE=""; { [ "$(task_field "$t" money)" = "true" ] || [ "$(task_field "$t" pii)" = "true" ]; } && SENSITIVE=1
VERDICT=""; VERDICT_SRC=""; REVIEW_FILE=""
if [ -n "$LOCAL_MODE" ]; then
  [ -z "$NOGATE" ] || die "--no-gate trusts a CI gate check, and local mode has no CI: run the gate"
  git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BRANCH" || die "no local branch $BRANCH"
  REVIEW_FILE="$ROOT/$(cfg .reviews docs/plan/reviews)/$ID.md"
  if [ -n "$SENSITIVE" ]; then
    grep -q "<!-- skein-review task=$ID " "$REVIEW_FILE" 2>/dev/null \
      || die "$ID is money/pii and $REVIEW_FILE has no skein review marker: run 'skein review $ID' first"
    VERDICT="$(review_verdict "$REVIEW_FILE")"; VERDICT_SRC="$REVIEW_FILE"
  fi
else
  PR="$(gh pr list --head "$BRANCH" --state open --json number,url,reviews,comments -q '.[0]' 2>/dev/null)"
  [ -n "$PR" ] || die "no open PR for branch $BRANCH"
  PRNUM="$(jq -r .number <<<"$PR")"; PRURL="$(jq -r .url <<<"$PR")"
  if [ -n "$SENSITIVE" ]; then
    # Evidence is the marker `skein review` posts, from a collaborator, naming this task: the
    # most recent one, because its envelope is what gets judged. One call, never a loop.
    CBODY="${TMPDIR:-/tmp}/skein-merge-review-$ID-$$.md"
    gh pr view "$PRNUM" --json comments -q "[.comments[] | select((.body | test(\"<!-- skein-review task=$ID \")) and (.authorAssociation | IN(\"OWNER\",\"MEMBER\",\"COLLABORATOR\")))] | last | .body // \"\"" > "$CBODY" 2>/dev/null || : > "$CBODY"
    # The marker is the evidence, never the file's size: with no such comment the jq result is
    # empty and `gh` still prints a newline, so a one-byte file would pass a [ -s ] test and a
    # money task with no review at all would fall through with no verdict to refuse.
    grep -q "<!-- skein-review task=$ID " "$CBODY" 2>/dev/null \
      || { rm -f "$CBODY"; die "$ID is money/pii and PR #$PRNUM carries no skein review marker from a collaborator: run 'skein review $ID' first"; }
    VERDICT="$(review_verdict "$CBODY")"; VERDICT_SRC="PR #$PRNUM"; rm -f "$CBODY"
  fi
fi

# The local merge's preconditions, ahead of everything that writes: an override records itself
# in the working tree and commits it, so it must not be the edit that dirties the tree the
# squash later refuses, nor land on a checkout that is not the base branch.
if [ -n "$LOCAL_MODE" ]; then
  [ "$(git -C "$ROOT" symbolic-ref --short HEAD 2>/dev/null)" = "$BASE" ] || die "check out $BASE in $ROOT before merging"
  git -C "$ROOT" diff --quiet && git -C "$ROOT" diff --cached --quiet || die "$ROOT has uncommitted changes: commit or stash them first"
fi

# The marker proves a review ran; only its envelope says the review approved. `DO NOT MERGE`
# used to satisfy this check exactly as well as `MERGE`, so a review that rejected the work
# and a review that never happened both read as a pass.
if [ -n "$SENSITIVE" ] && [ "$VERDICT" != MERGE ]; then
  [ -n "$OVERRIDDEN" ] || die "$ID is money/pii and its latest review ($VERDICT_SRC) does not approve: verdict: ${VERDICT:-<none>}, not MERGE. Fix the findings and review again, or record an override: skein merge $ID --override-review \"<reason>\""
  # Recorded before the gate runs, so the trace outlives a merge that then fails for another
  # reason. Appended once: a re-run must not dirty the tree the local merge needs clean.
  MARK="$(review_override_marker "$ID" "$me" "$VERDICT")"
  # The reason is data, never a verdict. Quoted, so a reason reading `verdict: MERGE` cannot
  # become the last envelope line in the file and a standing approval for every later merge.
  QUOTED="$(printf '%s\n' "$OVERRIDE" | sed 's/^/> /')"
  if [ -n "$LOCAL_MODE" ]; then
    # Appended once, so a re-run neither duplicates the record nor commits again. `--` because
    # a reason may begin with a dash.
    if ! { grep -qF -- "$MARK" "$REVIEW_FILE" 2>/dev/null && grep -qF -- "$QUOTED" "$REVIEW_FILE" 2>/dev/null; }; then
      printf '\n%s\n%s\n' "$MARK" "$QUOTED" >> "$REVIEW_FILE" \
        || die "could not record the override in $REVIEW_FILE; not merging without the trace"
      # Committed here, the way the plan update is committed at the end, so the trace survives
      # a gate that fails next and the squash still finds the clean tree it requires. A machine
      # with no git identity (a bare CI runner) records it as skein rather than refusing.
      git -C "$ROOT" add "$REVIEW_FILE" || die "could not stage $REVIEW_FILE; not merging without the trace"
      # The reason goes in the body, never the subject: `skein plan` reads a subject ending in
      # "(<ID>)" as that task's squash-merge (lib/plan.mjs:56-58).
      if [ -n "$(git -C "$ROOT" config user.email 2>/dev/null)" ]; then
        git -C "$ROOT" commit -q -m "plan: $ID review override" -m "$OVERRIDE"
      else
        git -C "$ROOT" -c user.name=skein -c user.email=skein@localhost commit -q -m "plan: $ID review override" -m "$OVERRIDE"
      fi || die "could not commit the override record in $REVIEW_FILE; not merging without the trace"
    fi
  else
    printf '%s\n\n%s\n' "$MARK" "$QUOTED" | gh pr comment "$PRNUM" --body-file - >/dev/null 2>&1 \
      || die "could not record the override on PR #$PRNUM; not merging without the trace"
  fi
  log "--override-review by $me: $ID merges though its review ($VERDICT_SRC) said ${VERDICT:-nothing}; the reason is recorded there"
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
