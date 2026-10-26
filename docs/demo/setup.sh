#!/usr/bin/env bash
# Builds the throwaway sandbox the demo runs in. demo.tape sources this while the recording
# is hidden, so the tape starts on a repository that is ready to coordinate.
#
# Nothing here touches a network, a board, a real repository or anything under the owner's
# home. The sandbox is a copy of examples/hello-swarm with no origin remote, which puts skein
# in local mode with board none and driver local (AGENTS.md rule 10). Sourced, not executed:
# the tape's shell keeps PATH, the sandbox variables and wt().
#
# Everything that writes runs in a subshell under `set -e`, and the caller's directory only
# changes once that subshell has succeeded. A half-built sandbox then cannot leave the shell
# pointing somewhere else, which is what makes it safe to source from a real checkout.

_demo_fail() { printf 'docs/demo/setup.sh: %s\n' "$1" >&2; }

if [ -z "${BASH_SOURCE[0]:-}" ]; then
  _demo_fail "source this from bash: it reads BASH_SOURCE to find the kit"
  return 1 2>/dev/null || exit 1
fi

KIT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
D="${SKEIN_DEMO_DIR:-/tmp/skein-demo}"

if [ ! -d "$KIT/examples/hello-swarm" ] || [ ! -x "$KIT/bin/skein" ]; then
  _demo_fail "$KIT does not look like a skein checkout"
  return 1 2>/dev/null || exit 1
fi
case "$D" in
  /*/?*) ;;
  *) _demo_fail "SKEIN_DEMO_DIR must be an absolute path below the root, not '$D'"
     return 1 2>/dev/null || exit 1 ;;
esac

# Every path the kit would otherwise keep under the owner's home moves into the sandbox, so
# no personal path can reach the recording.
export PATH="$D/bin:$PATH"
export SKEIN_WORKTREES="$D/worktrees"
export SKEIN_RUNS="$D/runs"
export TMPDIR="$D/tmp"
export SKEIN_USER_CONFIG="$D/machine.json"

(
  set -e
  rm -rf "$D"
  mkdir -p "$D/bin" "$D/tmp" "$D/worktrees" "$D/runs"
  cp -R "$KIT/examples/hello-swarm/." "$D/repo"
  ln -s "$KIT/bin/skein" "$D/bin/skein"
  ln -s "$KIT/docs/demo/claude" "$D/bin/claude"
  ln -s "$KIT/docs/demo/gh" "$D/bin/gh"
  printf '{ "maxAgents": 3 }\n' > "$SKEIN_USER_CONFIG"

  # The sandbox repository. Its commits are unattended, so signing is off and the author is
  # fixed (AGENTS.md rule 12); skein's own merge commits read the same local config.
  cd "$D/repo"
  git init -q -b main
  git config commit.gpgsign false
  git config user.name "skein demo"
  git config user.email "demo@localhost"
  # The example ships no ignore file and the install writes node_modules/, which would leave
  # every worktree dirty for the gate's clean-tree check. info/exclude is local to this
  # sandbox and shared by its worktrees, so the example itself stays as it is.
  printf 'node_modules/\n' >> .git/info/exclude
  git add -A
  git commit -qm "example: hello-swarm"
  # The flags match the example's own .skein/config.json, which init keeps: it takes the
  # name, prefix, board and driver from that config, and refuses a flag that contradicts it
  # unless --force-templates rewrites the config (commands/init.sh:22-37).
  skein init --name hello-swarm --prefix HS --board none --driver local >/dev/null 2>&1
  git add -A
  git commit -qm "chore: skein init"
) || { _demo_fail "could not build the sandbox in $D"; return 1 2>/dev/null || exit 1; }

cd "$D/repo" || { _demo_fail "no sandbox repository at $D/repo"; return 1 2>/dev/null || exit 1; }

# wt <ID> prints a task's worktree the way a coordinator finds it: the local driver writes
# one metadata file per workspace under $SKEIN_RUNS (lib/drivers/local.sh:31-32).
wt() {
  jq -r --arg id "($1)" 'select(.name | contains($id)) | .path' \
    "$SKEIN_RUNS/repo"/*.meta.json 2>/dev/null | head -1
}

PS1='$ '
clear
