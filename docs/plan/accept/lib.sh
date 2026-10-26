#!/usr/bin/env bash
# Shared by the acceptance scripts in this directory. Sourced from the repository root by a
# task's `accept` step. Coordinator-owned (docs/plan/**), so a task cannot change the check
# that judges it.
#
# Everything happens in a throwaway sandbox (AGENTS.md rule 10): a temp directory holds the
# repos, the local driver's worktrees and run logs, and the per-machine config, and stand-ins
# for gh, codex and claude sit first on PATH, so nothing reaches a network, an account or a
# real agent. The kit under test is this worktree's bin/skein.
set -u

KIT="$PWD"
[ -x "$KIT/bin/skein" ] || { echo "run this from the repository root" >&2; exit 2; }
SB="$(mktemp -d)"
trap 'rm -rf "${SB:?}"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
strip() { sed "s/$(printf '\033')\[[0-9;]*m//g"; }   # drop terminal colour codes

mkdir -p "$SB/bin"
for b in gh codex claude; do printf '#!/bin/sh\nexit 1\n' > "$SB/bin/$b"; chmod +x "$SB/bin/$b"; done
ln -s "$KIT/bin/skein" "$SB/bin/skein"
printf '{ "maxAgents": 3 }\n' > "$SB/machine.json"
export PATH="$SB/bin:$PATH" SKEIN_WORKTREES="$SB/worktrees" SKEIN_RUNS="$SB/runs" \
  SKEIN_USER_CONFIG="$SB/machine.json" SKEIN_KIT_GIT=1
unset SKEIN_MAX_AGENTS SKEIN_DRIVER SKEIN_BOARD SKEIN_PROJECT_ID

# Sandbox commits are unattended (AGENTS.md rule 12).
sbgit() { git -c commit.gpgsign=false -c user.name="skein accept" -c user.email=accept@localhost "$@"; }

# example_repo <dir>: a committed copy of examples/hello-swarm with no origin (local mode).
example_repo() {
  mkdir -p "$1" && cp -R "$KIT/examples/hello-swarm/." "$1"/ \
    && ( cd "$1" && git init -q -b main && sbgit add -A && sbgit commit -qm "example: hello-swarm" ) \
    || fail "could not build the example repo in $1"
}

# init_repo <dir>: example_repo, then skein init with explicit flags, committed.
init_repo() {
  example_repo "$1"
  ( cd "$1" && skein init --name hello-swarm --prefix HS --board none --driver local >/dev/null 2>&1 \
    && sbgit add -A && sbgit commit -qm "chore: skein init" ) || fail "skein init failed in $1"
}

# fake_workspace <repo> <key> <name> [envelope text]: what the local driver records for a
# workspace (lib/drivers/local.sh:31-32, 101-108), with an optional run log holding one
# assistant message, so status and dispatch see a workspace without any agent running.
fake_workspace() {
  local run="$SKEIN_RUNS/$(basename "$1")"
  mkdir -p "$run" "$SB/wt-$2"
  jq -n --arg n "$3" --arg p "$SB/wt-$2" '{name: $n, tag: "running", path: $p, branch: "x"}' > "$run/wt-$2.meta.json"
  [ -z "${4:-}" ] || jq -cn --arg t "$4" '{type: "assistant", message: {content: [{type: "text", text: $t}]}}' > "$run/wt-$2.jsonl"
}
