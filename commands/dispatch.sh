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

fail() { emit --arg task "$ID" --arg error "$1" '{task:$task, ok:false, error:$error}'; exit 1; }

# 1. Dispatchable: brief valid, deps merged, and both on origin (workspaces fork from origin).
node "$SKEIN_HOME/lib/plan.mjs" --check "$ID" >/dev/null 2>&1 || fail "$(node "$SKEIN_HOME/lib/plan.mjs" --check "$ID" 2>&1 | tr '\n' ' ')"
node "$SKEIN_HOME/lib/plan.mjs" --dispatchable | grep -qx "$ID" || fail "$ID is not dispatchable: a dependency is not merged (see skein plan)"
git -C "$ROOT" fetch -q origin 2>/dev/null
git -C "$ROOT" diff --quiet "origin/$BASE" -- "$(task_field "$t" brief)" "$PLAN" 2>/dev/null \
  || fail "brief or plan differs from origin/$BASE: push $BASE first (workspaces fork from origin)"

# 2. Caps, then the claim. The claim is the lock between coordinators.
capmsg="$(check_caps)" || fail "$capmsg"
log "$capmsg"
BOARD_URL="$(board_claim "$ID" "$TITLE" "$BRANCH")" || exit 1

# 3. Workspace, setup, sanity.
created="$(driver_create "$WS_NAME" "$BRANCH" "$BASE" "$TAG")" || { board_release "$ID" ready; exit 1; }
WS="$(jq -r .ws <<<"$created")"; SETUP="$(jq -r .setup <<<"$created")"
driver_wait_setup "$WS" "$SETUP" "$(cfg .setupTimeout 300)" || { board_release "$ID" blocked; fail "setup failed in workspace $WS"; }
PATH_WS="$(driver_path "$WS")"; [ -d "$PATH_WS" ] || fail "cannot find the worktree for $WS_NAME"
[ -f "$PATH_WS/$(task_field "$t" brief)" ] || fail "brief missing in the worktree (is it on origin/$BASE?)"
git -C "$PATH_WS" fetch -q origin 2>/dev/null
HEAD="$(git -C "$PATH_WS" rev-parse --short HEAD)"; MAIN="$(git -C "$PATH_WS" rev-parse --short "origin/$BASE")"
[ "$HEAD" = "$MAIN" ] || fail "workspace HEAD $HEAD is not origin/$BASE $MAIN"

# 4. The worker prompt: fixed, bounded, and the same for every task.
PROMPT="$(cfg .workerPrompt)"
[ -n "$PROMPT" ] || PROMPT="You are worker {ID} in a multi-agent build of {NAME}. Read AGENTS.md, then {BRIEF}, and follow the brief exactly. Work only in this workspace and on this branch. Your gate is \`{GATE} {ID}\`; do not use any other workflow or skill to test, review or ship. When the gate passes, push the branch, open a draft pull request, and end your final message with the completion envelope described in AGENTS.md. Never merge a pull request."
PROMPT="${PROMPT//\{ID\}/$ID}"; PROMPT="${PROMPT//\{NAME\}/$(cfg .name "$(basename "$ROOT")")}"
PROMPT="${PROMPT//\{BRIEF\}/$(task_field "$t" brief)}"; PROMPT="${PROMPT//\{GATE\}/$GATE}"

TERM_ID="$(driver_launch "$WS" "$AGENT" "$MODEL" "$EFFORT" "$PROMPT")" || { board_release "$ID" blocked; exit 1; }
board_comment "$ID" "Dispatched by $(me): workspace \`$WS_NAME\`, branch \`$BRANCH\`, agent $AGENT${MODEL:+ ($MODEL)}, head $HEAD."
emit --arg task "$ID" --arg ws "$WS" --arg term "$TERM_ID" --arg branch "$BRANCH" --arg head "$HEAD" \
     --arg model "$AGENT:$MODEL${EFFORT:+:$EFFORT}" --arg path "$PATH_WS" --arg board "$BOARD_URL" \
  '{task:$task, ok:true, workspace:$ws, terminal:$term, branch:$branch, head:$head, model:$model, worktree:$path, board:$board}'
