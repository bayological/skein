#!/usr/bin/env bash
# skein status — every task running anywhere (the board) and every worker running here
# (the driver), with both caps. Read-only: never sends anything to a worker.
. "$SKEIN_HOME/lib/common.sh"; require_config; load_board; load_driver; . "$SKEIN_HOME/lib/caps.sh"
B=$'\033[1m'; D=$'\033[2m'; R=$'\033[0m'; G=$'\033[32m'; Y=$'\033[33m'; RED=$'\033[31m'; C=$'\033[36m'
printf '%sskein status%s  %s  %s\n\n' "$B" "$R" "$(cfg .name "$(basename "$ROOT")")" "$(date '+%H:%M:%S')"
printf '%scaps%s  machine %s/%s  repo %s/%s  (board: %s, driver: %s)\n\n' "$B" "$R" "$(driver_running_count)" "$(machine_cap)" "$(board_running_count)" "$(repo_cap)" "$BOARD_TYPE" "$DRIVER_TYPE"

printf '%sboard%s (claims across all coordinators)\n' "$B" "$R"
board="$(board_list)"
if [ -z "$board" ]; then echo "  no claimed tasks"; else printf '%s\n' "$board" | awk -F'\t' '{printf "  %-10s %-9s %-14s %s\n", $1, $2, $3, $4}'; fi
echo

# The plan's task ids, once: "<lowercase id>|<the plan's own casing>" per line.
plan_ids=""
[ -f "$PLAN" ] && plan_ids="$(jq -r '.tasks[]? | select(.id) | "\(.id|ascii_downcase)|\(.id)"' "$PLAN" 2>/dev/null)"

# ws_task_id <workspace name> — the plan id this is a workspace name for, in the plan's own
# casing, or empty. The two forms task_ws_name makes (lib/common.sh:71-75): the name carries
# "(<ID>)", compared without case, as driver_find also finds it (lib/drivers/local.sh:99); or
# the name is the lowercased id, the fallback for a task with no type or slug.
ws_task_id() {
  local lname lid id
  lname="$(tr '[:upper:]' '[:lower:]' <<<"$1")"
  while IFS='|' read -r lid id; do
    [ -n "$lid" ] || continue
    case "$lname" in *"($lid)"*) printf '%s' "$id"; return 0 ;; esac
    [ "$lname" = "$lid" ] && { printf '%s' "$id"; return 0; }
  done <<<"$plan_ids"
  return 0
}

printf '%sworkers on this machine%s\n' "$B" "$R"
workspaces="$(driver_list)"
listed=0; skipped=0
while IFS=$'\t' read -r ws name path tags; do
  [ -n "$ws" ] || continue
  id="$(ws_task_id "$name")"
  if [ -z "$id" ]; then skipped=$((skipped+1)); continue; fi
  listed=$((listed+1))
  term="$(driver_agent_terminal "$ws")"
  state="${D}no agent${R}"; said=""
  if [ -n "$term" ]; then
    text="$(driver_read "$ws" "$term" 200)"
    if grep -q "${ENVELOPE}_DONE" <<<"$text" && grep -q -i -E "task:[[:space:]]*${id}\b" <<<"$text"; then state="${G}DONE, awaiting gate${R}"
    elif grep -q "${ENVELOPE}_BLOCKED" <<<"$text" && grep -q -i -E "task:[[:space:]]*${id}\b" <<<"$text"; then state="${RED}BLOCKED${R}"
    elif grep -q -i -E "usage limit|limit reached|rate limit" <<<"$text"; then state="${RED}usage limit${R}"
    elif grep -q -E "Waiting for API|will retry|API Error" <<<"$(tail -n 12 <<<"$text")"; then state="${Y}API retry${R}"
    elif grep -q -E "… \([0-9]+[hms]|^● " <<<"$(tail -n 12 <<<"$text")"; then state="${G}working${R}"
    else state="${Y}idle at prompt${R}"; fi
    said="$(grep -E '^\s*●\s+[A-Z]' <<<"$text" | grep -v -E '●\s+(Bash|Read|Write|Edit|Grep|Glob|Agent|Task)\(' | tail -1 | sed 's/^\s*●\s*//' | cut -c1-160)"
  fi
  commits="-"; dirty="-"
  if [ -n "$path" ] && [ -d "$path" ]; then
    commits="$(git -C "$path" rev-list --count "$(base_ref "$(cfg .baseBranch main)")..HEAD" 2>/dev/null || echo '?')"
    dirty="$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  fi
  printf '  %s%-40s%s %s  %s%s%s\n' "$B" "$name" "$R" "$state" "$D" "${tags:+[$tags]}" "$R"
  printf '      commits %-3s uncommitted %-3s %s%s%s\n' "$commits" "$dirty" "$C" "$path" "$R"
  [ -n "$said" ] && printf '      last note  %s\n' "$said"
done <<<"$workspaces"
[ "$listed" -gt 0 ] || echo "  none"
[ "$skipped" -gt 0 ] && printf '  %s%s other workspace(s) here carry no task id%s\n' "$D" "$skipped" "$R"
printf '\n%sworking = spinner active · idle at prompt = finished a turn without an envelope · the gate, not this view, decides done%s\n' "$D" "$R"
