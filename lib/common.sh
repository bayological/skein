#!/usr/bin/env bash
# Shared helpers for every skein command. Sourced, never executed.
# Requires: git, node, jq. Commands that touch a board or a driver require gh or superset.

set -uo pipefail

: "${SKEIN_HOME:?SKEIN_HOME must be set by bin/skein}"

log()  { printf 'skein: %s\n' "$*" >&2; }
warn() { printf 'skein: warning: %s\n' "$*" >&2; }
die()  { printf 'skein: %s\n' "$*" >&2; exit "${2:-1}"; }
need() { for b in "$@"; do command -v "$b" >/dev/null 2>&1 || die "needs '$b' on PATH"; done; }

# Repo root and config. Every command runs from anywhere inside the repo.
repo_root() { git rev-parse --show-toplevel 2>/dev/null || die "not inside a git repository"; }
ROOT="$(repo_root)"
CONFIG="$ROOT/.skein/config.json"
USER_CONFIG="${SKEIN_USER_CONFIG:-$HOME/.skein/config.json}"

have_config() { [ -f "$CONFIG" ]; }

KIT_CONFIG_VERSION=1   # the config version this kit reads; lib/gate.mjs has the same number
# config_version_error: why this kit cannot use the config, or nothing. A config with no
# "version" key is version 1, as every config init wrote before the key was read.
config_version_error() {
  local v
  v="$(jq -r 'if has("version") then .version else 1 end | if type == "number" and . == floor and . >= 0 then tostring else "invalid " + tojson end' "$CONFIG" 2>/dev/null)" \
    || { echo ".skein/config.json is not valid JSON"; return 0; }
  case "$v" in "invalid "*) echo ".skein/config.json has version ${v#invalid }; this kit understands version $KIT_CONFIG_VERSION"; return 0 ;; esac
  [ "$v" -le "$KIT_CONFIG_VERSION" ] || echo ".skein/config.json is version $v; this kit understands version $KIT_CONFIG_VERSION: upgrade the kit"
}
require_config() {
  have_config || die "no .skein/config.json here: run 'skein init' first"
  local e; e="$(config_version_error)"; [ -z "$e" ] || die "$e"
}

# cfg <jq-path> [default]  — read one value from the repo config.
cfg() {
  local path="$1" def="${2:-}"
  local v
  v="$(jq -r "$path // empty" "$CONFIG" 2>/dev/null)"
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$def"
}
# ucfg <jq-path> [default] — read one value from the per-machine config.
ucfg() {
  local path="$1" def="${2:-}"
  local v=""
  [ -f "$USER_CONFIG" ] && v="$(jq -r "$path // empty" "$USER_CONFIG" 2>/dev/null)"
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$def"
}

PLAN="$ROOT/$(cfg .plan docs/plan/wps.json)"
BRIEFS="$ROOT/$(cfg .briefs docs/plan/briefs)"
PREFIX="$(cfg .prefix TASK)"
ENVELOPE="$(cfg .envelope "${PREFIX}_WORKER")"
# Local mode: no origin remote, or "mode": "local" in the config. Nothing is pushed, there are
# no pull requests, workspaces fork from the local base branch, and `skein merge` squash-merges
# locally. For experiments that live on one machine and get pushed (if ever) by hand.
LOCAL_MODE=""
{ [ "$(cfg .mode)" = local ] || ! git -C "$ROOT" remote get-url origin >/dev/null 2>&1; } && LOCAL_MODE=1
base_ref() { if [ -n "$LOCAL_MODE" ]; then printf '%s' "$1"; else printf 'origin/%s' "$1"; fi; }   # base_ref <branch>
fetch_origin() { [ -n "$LOCAL_MODE" ] || git -C "${1:-$ROOT}" fetch -q origin 2>/dev/null; return 0; }
BOARD_TYPE="${SKEIN_BOARD:-$(cfg .board.type "$([ -n "$LOCAL_MODE" ] && echo none || echo github)")}"
DRIVER_TYPE="${SKEIN_DRIVER:-$(cfg .driver.type superset)}"   # SKEIN_DRIVER=local for a machine without Superset
COORD_ENV="$(cfg .coordinatorEnv "${PREFIX}_COORDINATOR")"

# Task helpers over the plan file.
task_json() {  # task_json <ID> -> the task object, or dies
  local id="$1"
  [ -f "$PLAN" ] || die "plan file not found: $PLAN"
  local t
  t="$(jq -c --arg id "$id" '.tasks[] | select((.id|ascii_downcase) == ($id|ascii_downcase))' "$PLAN")"
  [ -n "$t" ] || die "task '$id' not found in $PLAN"
  printf '%s' "$t"
}
task_field() { jq -r --arg k "$2" '.[$k] // empty' <<<"$1"; }   # task_field <json> <key>
task_id_norm() { task_json "$1" | jq -r .id; }                    # canonical casing

# Naming (COORDINATOR.md, "Naming"): branch <type>/<slug>-<id>, workspace "<type>: <slug words> (<ID>)".
task_branch() {
  local t="$1" id type slug
  id="$(jq -r '.id|ascii_downcase' <<<"$t")"; type="$(task_field "$t" type)"; slug="$(task_field "$t" slug)"
  if [ -n "$type" ] && [ -n "$slug" ]; then printf '%s/%s-%s' "$type" "$slug" "$id"; else printf '%s' "$id"; fi
}
task_ws_name() {
  local t="$1" id type slug
  id="$(jq -r .id <<<"$t")"; type="$(task_field "$t" type)"; slug="$(task_field "$t" slug)"
  if [ -n "$type" ] && [ -n "$slug" ]; then printf '%s: %s (%s)' "$type" "${slug//-/ }" "$id"; else printf '%s' "$(tr '[:upper:]' '[:lower:]' <<<"$id")"; fi
}

# Load the board and driver implementations named in config.
load_board()  { local f="$SKEIN_HOME/lib/boards/$BOARD_TYPE.sh";  [ -f "$f" ] || die "unknown board type '$BOARD_TYPE'";  . "$f"; }
load_driver() { local f="$SKEIN_HOME/lib/drivers/$DRIVER_TYPE.sh"; [ -f "$f" ] || die "unknown driver type '$DRIVER_TYPE'"; . "$f"; }

# Who am I, for claims. GitHub login when gh is present, else the OS user.
me() { gh api user -q .login 2>/dev/null || id -un; }

# Review output. `skein review` writes it and `skein merge` judges it, so the reading of it
# lives here and both see the same lines.

# review_verdict <file>: the value of the LAST line that begins `verdict:`, uppercased and
# trimmed, or nothing. A reviewer's prose may use the word, so the match is anchored and only
# the envelope counts; the last one wins, because a later round appends.
review_verdict() {
  [ -f "${1:-}" ] || return 0
  LC_ALL=C sed -n 's/^verdict:[[:space:]]*//p' "$1" 2>/dev/null | tail -1 \
    | tr -d '\r' | tr '[:lower:]' '[:upper:]' | sed 's/[[:space:]]*$//'
  return 0
}

# The words a sandbox that never started leaves behind: bwrap prints them when the kernel or a
# non-setuid binary refuses an unprivileged user namespace, and the reviewer then apologises
# into its output file instead of reviewing.
REVIEW_SANDBOX_SIGNATURE='bwrap:|RTM_NEWADDR|setting up uid map|Failed to create'

# review_sandbox_failed <file>: true when the output carries one of those signatures.
review_sandbox_failed() { LC_ALL=C grep -qE "$REVIEW_SANDBOX_SIGNATURE" "${1:-}" 2>/dev/null; }

# review_inconclusive <file>: true when the output is not a real review, either because it
# carries no REVIEW_DONE envelope at all, or because it carries a sandbox-failure signature
# AND reports no findings. Both halves, so a genuine review that quotes one of those strings
# inside a finding survives.
review_inconclusive() {
  local f="${1:-}"
  [ -s "$f" ] || return 0
  grep -q 'REVIEW_DONE' "$f" 2>/dev/null || return 0
  review_sandbox_failed "$f" && LC_ALL=C grep -qE '^findings:[[:space:]]*0[[:space:]]*$' "$f" 2>/dev/null
}

# review_agent_usable <agent>: can this agent actually produce a review on this machine?
# Sets REVIEW_AGENT_UNUSABLE to the check that failed, "version" or "sandbox", so the caller
# can say which. Free and fast: no model call. A version is not enough for codex, whose
# read-only sandbox needs an unprivileged user namespace: where one is refused,
# `codex --version` still exits 0 while `codex exec --sandbox read-only` dies before reading a
# file. SKEIN_SKIP_SANDBOX_PROBE=1 forces the probe to pass, for a CI that is sandboxed
# correctly and for the kit's own tests.
REVIEW_AGENT_UNUSABLE=""
review_agent_usable() {
  local agent="${1:-}"
  REVIEW_AGENT_UNUSABLE=""
  "$agent" --version >/dev/null 2>&1 || { REVIEW_AGENT_UNUSABLE=version; return 1; }
  [ "$agent" = codex ] || return 0
  [ "${SKEIN_SKIP_SANDBOX_PROBE:-}" = 1 ] && return 0
  if command -v bwrap >/dev/null 2>&1; then
    bwrap --ro-bind / / --unshare-user true >/dev/null 2>&1 && return 0
  elif command -v unshare >/dev/null 2>&1; then
    unshare --user --map-root-user true >/dev/null 2>&1 && return 0
  else
    return 0   # nothing here to probe (macOS, where codex sandboxes with Seatbelt)
  fi
  REVIEW_AGENT_UNUSABLE=sandbox; return 1
}

# review_override_marker <id> <by> <verdict>: the auditable line `skein merge
# --override-review` leaves where the review lives. It writes `verdict=` and not `verdict:`,
# so review_verdict can never read an override as an approval.
review_override_marker() { printf '<!-- skein-review-override task=%s by=%s verdict=%s -->' "$1" "$2" "${3:-none}"; }

# One JSON line to stdout: the machine-readable result every running command ends with.
emit() { jq -cn "$@"; }
