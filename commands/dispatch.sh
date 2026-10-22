#!/usr/bin/env bash
# skein dispatch <TASK> [--tag t] [--model m] [--agent a] [--effort e]
# Claim the task on the board, create the workspace, wait for setup, launch the worker.
# Prints one JSON line. Every refusal here has cost a rerun somewhere: a stale brief, a
# workspace forked from old main, a worker racing the install, a cap already spent.
. "$SKEIN_HOME/lib/common.sh"; require_config; load_board; load_driver; . "$SKEIN_HOME/lib/caps.sh"
need git jq node

TASK=""; TAG=running; MODEL="-"; AGENT=""; EFFORT=""
while [ $# -gt 0 ]; do case "$1" in
  --tag) TAG="$2"; shift 2 ;; --model) MODEL="$2"; shift 2 ;; --agent) AGENT="$2"; shift 2 ;; --effort) EFFORT="$2"; shift 2 ;;
  -*) die "unknown flag $1" ;; *) TASK="$1"; shift ;; esac; done
[ -n "$TASK" ] || die "usage: skein dispatch <TASK> [--tag t] [--model m] [--agent a] [--effort e]"

t="$(task_json "$TASK")"; ID="$(jq -r .id <<<"$t")"; TITLE="$(task_field "$t" title)"
BRANCH="$(task_branch "$t")"; WS_NAME="$(task_ws_name "$t")"
[ -z "$AGENT" ] && AGENT="$(cfg .worker.agent claude)"
[ "$MODEL" = "-" ] && MODEL="$(cfg .worker.model -)"
[ -z "$EFFORT" ] && EFFORT="$(cfg .worker.effort)"
GATE="$(cfg .gate 'scripts/skein/skein gate')"
BASE="$(cfg .baseBranch main)"

CLAIMED=""; WS=""
# One exit path for every failure: a claim is released (back to ready, assignee cleared) and
# a half-built workspace is deleted, so a bad dispatch never strands the board or the cap.
fail() {
  [ -n "$WS" ] && driver_delete "$WS" 2>/dev/null
  [ -n "$CLAIMED" ] && board_release "$ID" ready 2>/dev/null
  emit --arg task "$ID" --arg error "$1" '{task:$task, ok:false, error:$error}'; exit 1
}

# 1. Dispatchable: brief valid, deps merged, and both on origin (workspaces fork from origin;
#    in local mode, from the local base branch, so both must be committed there).
node "$SKEIN_HOME/lib/plan.mjs" --check "$ID" >/dev/null 2>&1 || fail "$(node "$SKEIN_HOME/lib/plan.mjs" --check "$ID" 2>&1 | tr '\n' ' ')"
node "$SKEIN_HOME/lib/plan.mjs" --dispatchable | grep -qx "$ID" || fail "$ID is not dispatchable: a dependency is not merged (see skein plan)"
BASE_REF="$(base_ref "$BASE")"; fetch_origin
SYNC_HINT="push $BASE first (workspaces fork from origin)"; [ -n "$LOCAL_MODE" ] && SYNC_HINT="commit them on $BASE first (workspaces fork from it)"
git -C "$ROOT" diff --quiet "$BASE_REF" -- "$(task_field "$t" brief)" "$PLAN" 2>/dev/null \
  || fail "brief or plan differs from $BASE_REF: $SYNC_HINT"

# 2. A leftover branch from an earlier dispatch: harmless if it has no commits of its own
#    (delete it so the workspace forks from today's origin), a stop if it has work on it.
fetch_origin
for ref in "refs/heads/$BRANCH" "refs/remotes/origin/$BRANCH"; do
  git -C "$ROOT" show-ref --verify --quiet "$ref" || continue
  if git -C "$ROOT" merge-base --is-ancestor "$ref" "$BASE_REF"; then
    case "$ref" in
      refs/heads/*) git -C "$ROOT" branch -q -D "$BRANCH" && log "deleted stale local branch $BRANCH (no commits of its own)" ;;
      *) env "$COORD_ENV=1" git -C "$ROOT" push -q origin --delete "$BRANCH" 2>/dev/null && log "deleted stale remote branch $BRANCH (no commits of its own)" ;;
    esac
  else
    fail "branch $BRANCH already exists with commits on it: resume that work (skein status) or delete the branch first"
  fi
done

# 3. Caps, then the claim. The claim is the lock between coordinators.
capmsg="$(check_caps)" || fail "$capmsg"
log "$capmsg"
BOARD_URL="$(board_claim "$ID" "$TITLE" "$BRANCH")" || exit 1
CLAIMED=1
# Two coordinators can pass the cap check together and both claim. The claim is what counts,
# so recount now that ours is on the board and back out if the repo is over its cap.
[ "$(board_running_count)" -le "$(repo_cap)" ] || fail "repo cap exceeded after claiming ($(board_running_count) > $(repo_cap)); claim released, try again later"

# 4. Workspace, setup, sanity.
created="$(driver_create "$WS_NAME" "$BRANCH" "$BASE" "$TAG")" || fail "workspace creation failed"
WS="$(jq -r .ws <<<"$created")"; SETUP="$(jq -r .setup <<<"$created")"
driver_wait_setup "$WS" "$SETUP" "$(cfg .setupTimeout 300)" || fail "setup failed in workspace $WS (see its setup output)"
PATH_WS="$(driver_path "$WS")"; [ -d "$PATH_WS" ] || fail "cannot find the worktree for $WS_NAME"
[ -f "$PATH_WS/$(task_field "$t" brief)" ] || fail "brief missing in the worktree (is it on $BASE_REF?)"
fetch_origin "$PATH_WS"
HEAD="$(git -C "$PATH_WS" rev-parse --short HEAD)"; MAIN="$(git -C "$PATH_WS" rev-parse --short "$BASE_REF")"
[ "$HEAD" = "$MAIN" ] || fail "workspace HEAD $HEAD is not $BASE_REF $MAIN"

# 5. The worker prompt: fixed, bounded, and the same for every task.
PROMPT="$(cfg .workerPrompt)"
[ -n "$PROMPT" ] || PROMPT="You are worker {ID} in a multi-agent build of {NAME}. Read AGENTS.md, then {BRIEF}, and follow the brief exactly. Work only in this workspace and on this branch. Your gate is \`{GATE} {ID}\`; do not use any other workflow or skill to test, review or ship. When the gate passes, push the branch, open a draft pull request, and end your final message with the completion envelope described in AGENTS.md. Never merge a pull request."
# Local mode: no remote to push to and no PR to open; the coordinator merges the branch.
[ -n "$LOCAL_MODE" ] && [ -z "$(cfg .workerPrompt)" ] && PROMPT="You are worker {ID} in a multi-agent build of {NAME}. Read AGENTS.md, then {BRIEF}, and follow the brief exactly. Work only in this workspace and on this branch. Your gate is \`{GATE} {ID}\`; do not use any other workflow or skill to test, review or ship. This repo has no remote: when the gate passes, leave everything committed on this branch (do not push, do not open a pull request), and end your final message with the completion envelope described in AGENTS.md. Never merge into {BASE}."
PROMPT="${PROMPT//\{ID\}/$ID}"; PROMPT="${PROMPT//\{NAME\}/$(cfg .name "$(basename "$ROOT")")}"
PROMPT="${PROMPT//\{BRIEF\}/$(task_field "$t" brief)}"; PROMPT="${PROMPT//\{GATE\}/$GATE}"; PROMPT="${PROMPT//\{BASE\}/$BASE}"

TERM_ID="$(driver_launch "$WS" "$AGENT" "$MODEL" "$EFFORT" "$PROMPT")" || fail "the agent did not start"
board_comment "$ID" "Dispatched by $(me): workspace \`$WS_NAME\`, branch \`$BRANCH\`, agent $AGENT${MODEL:+ ($MODEL)}, head $HEAD."
emit --arg task "$ID" --arg ws "$WS" --arg term "$TERM_ID" --arg branch "$BRANCH" --arg head "$HEAD" \
     --arg model "$AGENT:$MODEL${EFFORT:+:$EFFORT}" --arg path "$PATH_WS" --arg board "$BOARD_URL" \
  '{task:$task, ok:true, workspace:$ws, terminal:$term, branch:$branch, head:$head, model:$model, worktree:$path, board:$board}'
