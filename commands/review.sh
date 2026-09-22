#!/usr/bin/env bash
# skein review <TASK> [--agent codex|claude] [--model m]
# Cross-model review of the task's PR in a read-only worktree forked from the PR branch,
# headless. Posts the findings as one PR comment and prints the file. Mandatory for tasks
# marked money or pii; the coordinator triages each finding on its merits.
. "$SKEIN_HOME/lib/common.sh"; require_config; load_board; load_driver
need gh jq
TASK=""; AGENT=""; MODEL=""
while [ $# -gt 0 ]; do case "$1" in
  --agent) AGENT="$2"; shift 2 ;; --model) MODEL="$2"; shift 2 ;; -*) die "unknown flag $1" ;; *) TASK="$1"; shift ;; esac; done
[ -n "$TASK" ] || die "usage: skein review <TASK> [--agent codex|claude] [--model m]"
t="$(task_json "$TASK")"; ID="$(jq -r .id <<<"$t")"; BRANCH="$(task_branch "$t")"; SLUG="$(task_field "$t" slug)"
[ -z "$AGENT" ] && AGENT="$(cfg .review.agent codex)"
[ -z "$MODEL" ] && MODEL="$(cfg .review.model)"
command -v "$AGENT" >/dev/null 2>&1 || { [ "$AGENT" = codex ] && { warn "codex not installed; falling back to claude"; AGENT=claude; MODEL="$(cfg .review.fallbackModel claude-fable-5-1)"; }; }

PR="$(gh pr list --head "$BRANCH" --state open --json number,url -q '.[0]' 2>/dev/null)"
[ -n "$PR" ] || die "no open PR for branch $BRANCH"
PRNUM="$(jq -r .number <<<"$PR")"; PRURL="$(jq -r .url <<<"$PR")"

created="$(driver_create "review: ${SLUG:-$ID} ($ID)" "review-${SLUG:-$(tr '[:upper:]' '[:lower:]' <<<"$ID")}-$(date +%s)" "$BRANCH" review)" || exit 1
WS="$(jq -r .ws <<<"$created")"; RPATH="$(driver_path "$WS")"
driver_wait_setup "$WS" "$(jq -r .setup <<<"$created")" "$(cfg .setupTimeout 300)" || warn "review workspace setup did not finish cleanly; reviewing anyway"

OUT="${TMPDIR:-/tmp}/skein-review-$ID-$(date +%s).md"
PROMPT="$(node "$SKEIN_HOME/lib/render.mjs" "$SKEIN_HOME/templates/review-prompt.md" /dev/stdout ID="$ID" PR="$PRURL" BRIEF="$(task_field "$t" brief)" BASE="origin/$(cfg .baseBranch main)" MONEY="$(task_field "$t" money)")"
log "reviewing $ID (PR #$PRNUM) with $AGENT${MODEL:+ $MODEL} in $RPATH"
case "$AGENT" in
  codex)
    # Headless on purpose: out of quota, Codex's interactive screen opens on an "Upgrade"
    # menu that a pasted keystroke can confirm. codex exec just exits with the reset time.
    ( cd "$RPATH" && codex exec ${MODEL:+-m "$MODEL"} -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox -o "$OUT" "$PROMPT" < /dev/null ) >/dev/null 2>&1 \
      || warn "codex exec exited non-zero; check $OUT" ;;
  claude)
    ( cd "$RPATH" && claude -p "$PROMPT" ${MODEL:+--model "$MODEL"} --dangerously-skip-permissions > "$OUT" 2>/dev/null ) \
      || warn "claude exited non-zero; check $OUT" ;;
  *) die "unknown review agent $AGENT" ;;
esac
[ -s "$OUT" ] || die "review produced no output ($OUT)"
gh pr comment "$PRNUM" --body-file "$OUT" >/dev/null 2>&1 && log "posted review to $PRURL" || warn "could not post the PR comment; findings are in $OUT"
board_release "$ID" gating
driver_delete "$WS"
emit --arg task "$ID" --arg pr "$PRURL" --arg file "$OUT" --arg agent "$AGENT:$MODEL" '{task:$task, ok:true, pr:$pr, file:$file, reviewer:$agent}'
