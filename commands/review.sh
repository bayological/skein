#!/usr/bin/env bash
# skein review <TASK> [--agent codex|claude] [--model m]
# Cross-model review of the task's PR in a read-only worktree forked from the PR branch,
# headless. Posts the findings as one PR comment and prints the file. Mandatory for tasks
# marked money or pii; the coordinator triages each finding on its merits.
# Local mode (no origin): reviews the task branch's diff against the base branch and writes
# the findings, with the marker `skein merge` looks for, to docs/plan/reviews/<ID>.md, moving
# the previous round to <ID>.rN.md first.
# Exits non-zero without touching <ID>.md when the round was inconclusive: no envelope, or a
# sandbox that failed and found nothing. That output goes to <ID>.inconclusive.md instead.
. "$SKEIN_HOME/lib/common.sh"; require_config; load_board; load_driver
need jq; [ -n "$LOCAL_MODE" ] || need gh
TASK=""; AGENT=""; MODEL=""
while [ $# -gt 0 ]; do case "$1" in
  --agent) AGENT="$2"; shift 2 ;; --model) MODEL="$2"; shift 2 ;; -*) die "unknown flag $1" ;; *) [ -z "$TASK" ] || die "one task per call: got $TASK and $1"; TASK="$1"; shift ;; esac; done
[ -n "$TASK" ] || die "usage: skein review <TASK> [--agent codex|claude] [--model m]"
t="$(task_json "$TASK")"; ID="$(jq -r .id <<<"$t")"; BRANCH="$(task_branch "$t")"; SLUG="$(task_field "$t" slug)"
[ -z "$AGENT" ] && AGENT="$(cfg .review.agent codex)"
[ -z "$MODEL" ] && MODEL="$(cfg .review.model)"
# `codex` may be a shim with nothing behind it (Superset installs one), and its read-only
# sandbox may be refused by this kernel long after `--version` succeeds; prove both, and say
# which one failed, because "codex not usable" sent the last operator looking in the wrong place.
if [ "$AGENT" = codex ] && ! review_agent_usable codex; then
  case "$REVIEW_AGENT_UNUSABLE" in
    sandbox) warn "codex runs but its sandbox does not: no unprivileged user namespace can be created here, so 'codex exec --sandbox read-only' would die before reading a file. Falling back to claude (set SKEIN_SKIP_SANDBOX_PROBE=1 to force the probe to pass)" ;;
    *) warn "codex is not usable: 'codex --version' failed, so nothing is behind the command. Falling back to claude" ;;
  esac
  AGENT=claude; MODEL="$(cfg .review.fallbackModel claude-fable-5-1)"
fi

if [ -n "$LOCAL_MODE" ]; then
  git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BRANCH" || die "no local branch $BRANCH"
  PRNUM=""; PRURL="branch $BRANCH"
else
  PR="$(gh pr list --head "$BRANCH" --state open --json number,url -q '.[0]' 2>/dev/null)"
  [ -n "$PR" ] || die "no open PR for branch $BRANCH"
  PRNUM="$(jq -r .number <<<"$PR")"; PRURL="$(jq -r .url <<<"$PR")"
fi

RBRANCH="review-${SLUG:-$(tr '[:upper:]' '[:lower:]' <<<"$ID")}-$(date +%s)"
created="$(driver_create "review: ${SLUG:-$ID} ($ID)" "$RBRANCH" "$BRANCH" review)" || exit 1
WS="$(jq -r .ws <<<"$created")"; RPATH="$(driver_path "$WS")"
driver_wait_setup "$WS" "$(jq -r .setup <<<"$created")" "$(cfg .setupTimeout 300)" || warn "review workspace setup did not finish cleanly; reviewing anyway"

OUT="${TMPDIR:-/tmp}/skein-review-$ID-$(date +%s).md"
PROMPT="$(node "$SKEIN_HOME/lib/render.mjs" "$SKEIN_HOME/templates/review-prompt.md" /dev/stdout ID="$ID" PR="$PRURL" BRIEF="$(task_field "$t" brief)" BASE="$(base_ref "$(cfg .baseBranch main)")" MONEY="$(task_field "$t" money)")"
log "reviewing $ID ($([ -n "$PRNUM" ] && echo "PR #$PRNUM" || echo "$PRURL")) with $AGENT${MODEL:+ $MODEL} in $RPATH"
# The reviewer reads; it never writes, runs the build, or reaches the network on its own.
# codex: its read-only sandbox. claude: only read tools and git diff/log/show are allowed;
# anything else is denied in headless mode.
READ_TOOLS="Read,Grep,Glob,LS,Bash(git diff:*),Bash(git log:*),Bash(git show:*),Bash(git status:*),Bash(cat:*),Bash(sed -n:*),Bash(head:*),Bash(tail:*),Bash(wc:*),Bash(ls:*)"
case "$AGENT" in
  codex)
    # Headless on purpose: out of quota, Codex's interactive screen opens on an "Upgrade"
    # menu that a pasted keystroke can confirm. codex exec just exits with the reset time.
    ( cd "$RPATH" && codex exec ${MODEL:+-m "$MODEL"} -c model_reasoning_effort=high --sandbox read-only -o "$OUT" "$PROMPT" < /dev/null ) >/dev/null 2>&1 \
      || warn "codex exec exited non-zero; check $OUT" ;;
  claude)
    ( cd "$RPATH" && claude -p "$PROMPT" ${MODEL:+--model "$MODEL"} --allowedTools "$READ_TOOLS" > "$OUT" 2>/dev/null ) \
      || warn "claude exited non-zero; check $OUT" ;;
  *) die "unknown review agent $AGENT" ;;
esac
[ -s "$OUT" ] || die "review produced no output ($OUT)"
RDIR="$ROOT/$(cfg .reviews docs/plan/reviews)"; RFILE="$RDIR/$ID.md"
FALLBACK="$(cfg .review.fallbackModel claude-fable-5-1)"
# An inconclusive review is not a review, so it never takes the path `skein merge` reads and
# never lands on a real one. A reviewer whose sandbox died before reading a single file still
# writes output, and that output used to overwrite the findings of the round before it.
if review_inconclusive "$OUT"; then
  WHY="no REVIEW_DONE envelope"
  review_sandbox_failed "$OUT" && WHY="a sandbox failure and no findings"
  KEPT="$OUT"
  if [ -n "$LOCAL_MODE" ]; then
    mkdir -p "$RDIR"; KEPT="$RDIR/$ID.inconclusive.md"
    { printf '<!-- skein-review-inconclusive task=%s reviewer=%s by=%s why=%s -->\n' "$ID" "$AGENT${MODEL:+:$MODEL}" "$(me)" "$WHY"; cat "$OUT"; } > "$KEPT"
  fi
  driver_delete "$WS"
  git -C "$ROOT" branch -q -D "$RBRANCH" 2>/dev/null || true
  die "$ID: $AGENT reported $WHY, so this is not a review. Its output is at $KEPT and $RFILE is untouched. Retry with: skein review $ID --agent claude --model $FALLBACK"
fi
# The marker is what `skein merge` requires for money/pii tasks: a word in a comment is not evidence.
{ printf '<!-- skein-review task=%s reviewer=%s by=%s -->\n' "$ID" "$AGENT${MODEL:+:$MODEL}" "$(me)"; cat "$OUT"; } > "$OUT.comment"
if [ -n "$LOCAL_MODE" ]; then
  mkdir -p "$RDIR"
  # A new round never destroys the one before it: the previous file moves to <ID>.rN.md with
  # the lowest free N, and the latest stays at <ID>.md, where merge looks.
  PREV=""
  if [ -s "$RFILE" ]; then
    N=1; while [ -e "$RDIR/$ID.r$N.md" ]; do N=$((N+1)); done
    PREV="$RDIR/$ID.r$N.md"; cp "$RFILE" "$PREV" || die "could not keep the previous review at $PREV; not overwriting $RFILE"
  fi
  cp "$OUT.comment" "$RFILE" && log "wrote review to $RFILE${PREV:+ (previous round kept at $PREV)} (commit it with the plan)" && OUT="$RFILE"
else
  gh pr comment "$PRNUM" --body-file "$OUT.comment" >/dev/null 2>&1 && log "posted review to $PRURL" || warn "could not post the PR comment; findings are in $OUT"
fi
board_release "$ID" gating
driver_delete "$WS"
# The review branch only gave the read-only worktree a checkout and holds no commits; the
# driver removes the worktree but not the branch.
git -C "$ROOT" branch -q -D "$RBRANCH" 2>/dev/null || true
emit --arg task "$ID" --arg pr "$PRURL" --arg file "$OUT" --arg agent "$AGENT:$MODEL" '{task:$task, ok:true, pr:$pr, file:$file, reviewer:$agent}'
