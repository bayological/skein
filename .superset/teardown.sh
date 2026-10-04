#!/usr/bin/env bash
# Superset workspace teardown. Setup starts nothing; Run leaves a sandbox repo outside the
# worktree (run.sh), and any worker a local-driver dispatch started there runs in its own
# process group, so it outlives the Run pane. Stop those workers by the pid files the
# driver keeps, as driver_delete does (never a pattern match), then delete the sandbox.
# run.sh calls this first, so every Run starts from nothing.
KIT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P) || exit 0
SANDBOX="${TMPDIR:-/tmp}/skein-sandbox-$(basename "$KIT")"   # the path run.sh builds
[ -d "$SANDBOX" ] || exit 0

for pidfile in "$SANDBOX"/runs/*/*.pid; do
  [ -f "$pidfile" ] || continue
  pid=$(cat "$pidfile")
  [ -n "$pid" ] || continue
  kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null
done
rm -rf "$SANDBOX"
echo "removed $SANDBOX"
exit 0
