#!/usr/bin/env bash
# Superset workspace setup for skein itself. Runs once per new worktree, in the worktree
# root. The kit is bash and dependency-free node, so nothing is installed: this checks the
# tools it runs on and copies the main checkout's local-only files. Idempotent; instant.
#
# Never call ./setup from here: it points ~/.local/bin/skein and ~/.claude/skills/skein-*
# at this worktree, which goes away with the workspace. Run this workspace's kit as
# ./bin/skein, or press Run for a sandbox repo to run it in.
set -euo pipefail

ROOT="${SUPERSET_ROOT_PATH:-}"
# Superset 1.35 does not export SUPERSET_WORKSPACE_NAME, whatever its docs say.
WS_NAME="${SUPERSET_WORKSPACE_NAME:-$(basename "$PWD")}"
if [ -z "$ROOT" ]; then
  echo "SUPERSET_ROOT_PATH not set; run this via Superset (or export it)." >&2
  exit 1
fi

# 1. Toolchain: git, node and jq are hard requirements (lib/common.sh); gh serves the
#    default board.
for b in git node jq; do
  command -v "$b" >/dev/null || { echo "skein needs '$b' on PATH" >&2; exit 1; }
done
command -v gh >/dev/null || echo "note: 'gh' not on PATH; the github board needs it"

# 2. Local-only files are gitignored, so a new worktree lacks them: copy them from the
#    main checkout, never over this workspace's own copy.
for rel in .env .env.local; do
  if [ -f "$rel" ]; then
    echo "$rel: already present"
  elif [ -f "$ROOT/$rel" ]; then
    cp -p "$ROOT/$rel" "$rel"
    echo "$rel: copied from the main checkout"
  else
    echo "$rel: not in the main checkout; skipping"
  fi
done

echo "workspace '$WS_NAME' ready"
