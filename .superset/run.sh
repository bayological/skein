#!/usr/bin/env bash
# Superset Run button. skein has no server to start, so Run gives this workspace's kit a
# repo to act on: it rebuilds a throwaway sandbox (a bare origin and a clone: no GitHub, no
# Superset, no network), smoke-tests the kit there, and leaves a shell in it where `skein`
# is this worktree's bin/skein. One sandbox per workspace, named after the worktree, so
# parallel workspaces never share one; nothing listens on a port. teardown.sh deletes it.
set -euo pipefail

KIT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
SANDBOX="${TMPDIR:-/tmp}/skein-sandbox-$(basename "$KIT")"   # the path teardown.sh removes
"$KIT/.superset/teardown.sh"                                  # the last Run's, workers first
[ ! -e "$SANDBOX" ] || { echo "could not remove $SANDBOX" >&2; exit 1; }

# The sandbox environment; another shell gets it with `. $SANDBOX/env.sh`. Without the two
# dirs the local driver keeps worktrees and run logs in ~/.skein under the repo's basename,
# shared by every sandbox; without SKEIN_KIT_GIT, `skein upgrade` git-pulls this worktree.
mkdir -p "$SANDBOX/bin"
ln -s "$KIT/bin/skein" "$SANDBOX/bin/skein"
cat > "$SANDBOX/env.sh" <<EOF
export PATH="$SANDBOX/bin:\$PATH" SKEIN_WORKTREES="$SANDBOX/worktrees" SKEIN_RUNS="$SANDBOX/runs" SKEIN_KIT_GIT=1
cd "$SANDBOX/repo"
EOF

# A repo for the kit to act on: one package with a passing test, and a dev script so init
# renders every Superset template, pushed to a local origin. Sandbox commits are
# unattended, so they never wait on a signing key.
sbgit() { git -c commit.gpgsign=false -c user.name="skein sandbox" -c user.email=sandbox@localhost "$@"; }
sbgit init -q --bare -b main "$SANDBOX/origin.git"
sbgit init -q -b main "$SANDBOX/repo"
. "$SANDBOX/env.sh"
sbgit remote add origin "$SANDBOX/origin.git"
printf '{ "name": "sandbox", "private": true, "scripts": { "dev": "node --version", "test": "node --test" } }\n' > package.json
mkdir test
printf 'import test from "node:test";\ntest("sandbox", () => {});\n' > test/sandbox.test.mjs
sbgit add -A && sbgit commit -qm "sandbox: one package, one test" && sbgit push -q origin main

# Smoke checks. Each runs; the summary names any that failed.
FAILED=""
step() {  # step <title> <command...>
  local title="$1"; shift
  printf '\n==> %s\n' "$title"
  "$@" || FAILED="$FAILED${FAILED:+, }$title"
}
kit_parses() {  # every kit script, including the ones the sandbox never reaches
  local f rc=0
  for f in "$KIT"/bin/skein "$KIT"/setup "$KIT"/commands/*.sh "$KIT"/lib/*.sh "$KIT"/lib/*/*.sh "$KIT"/.superset/*.sh; do
    bash -n "$f" || rc=1
  done
  for f in "$KIT"/lib/*.mjs; do node --check "$f" || rc=1; done
  [ "$rc" = 0 ] && echo "ok"
}
init_sandbox() {  # scaffold; the rendered scripts must parse; push to main as a coordinator does
  local f
  skein init --name sandbox --prefix SBX --board none --driver local || return 1
  for f in scripts/githooks/pre-push .superset/*.sh; do bash -n "$f" || return 1; done
  sbgit add -A && sbgit commit -qm "skein init" && SBX_COORDINATOR=1 sbgit push -q origin main
}
step "kit scripts parse" kit_parses
step "skein init" init_sandbox
step "skein doctor" skein doctor
step "skein plan" skein plan
step "skein status" skein status
step "skein gate --standard-only" skein gate --standard-only

status=0
if [ -z "$FAILED" ]; then printf '\n✓ smoke passed\n'; else status=1; printf '\n✗ smoke failed: %s\n' "$FAILED"; fi
cat <<EOF
sandbox    $SANDBOX/repo
skein      $KIT/bin/skein
elsewhere  . $SANDBOX/env.sh
Kit edits apply at once; \`skein upgrade\` refreshes the sandbox's vendored copy.
EOF
[ -t 0 ] || exit "$status"
PS1='(skein sandbox) \w \$ ' exec bash --norc -i
