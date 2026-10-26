#!/usr/bin/env bash
# Acceptance for SK-13: skein init takes the name, prefix, base, board and driver from a kept
# .skein/config.json, refuses a flag that contradicts it without changing anything, and still
# derives them from the folder in a repo with no config. Run from the repository root.
. docs/plan/accept/lib.sh

# 1. Plain init over the example's kept config, in a folder that would derive SANDBO.
R="$SB/sandbox-copy"; example_repo "$R"
out="$(cd "$R" && skein init 2>&1)" || fail "plain skein init failed: $out"
grep -q 'HS_WORKER_DONE' "$R/AGENTS.md" || fail "AGENTS.md does not name HS_WORKER_DONE, the kept config's envelope"
grep -q 'SANDBO_' "$R/AGENTS.md" && fail "AGENTS.md names the SANDBO prefix derived from the folder name"
grep -q 'HS_COORDINATOR' "$R/scripts/githooks/pre-push" || fail "the pre-push hook does not check HS_COORDINATOR"
printf '%s\n' "$out" | grep -q 'skein init done for hello-swarm (HS-xx tasks, board=none, driver=local, base=main' \
  || fail "the closing summary does not report the kept config: $(printf '%s\n' "$out" | grep 'init done')"

# 2. A contradicting flag is refused before anything is written.
( cd "$R" && sbgit add -A && sbgit commit -qm "chore: skein init" ) >/dev/null || fail "could not commit the init"
out="$(cd "$R" && skein init --prefix XX 2>&1)" && fail "skein init --prefix XX succeeded over a kept config whose prefix is HS"
printf '%s\n' "$out" | grep -q -- '--prefix XX differs from the kept .skein/config.json (HS)' \
  || fail "the refusal does not name the flag and the kept value: $out"
[ -z "$(cd "$R" && git status --porcelain)" ] || fail "the refused init changed files: $(cd "$R" && git status --porcelain | head -3)"
out="$(cd "$R" && skein init --driver superset 2>&1)" && fail "skein init --driver superset succeeded over a kept driver local"
out="$(cd "$R" && skein init --prefix HS --driver local 2>&1)" || fail "flags that match the kept config were refused: $out"

# 3. With no config, init still derives the name and prefix from the folder.
F="$SB/widget-app"; mkdir -p "$F"
( cd "$F" && git init -q -b main && printf 'widget\n' > README.md && sbgit add -A && sbgit commit -qm widget ) >/dev/null || fail "could not build $F"
( cd "$F" && skein init >/dev/null 2>&1 ) || fail "skein init failed in a repo with no config"
[ "$(jq -r .prefix "$F/.skein/config.json")" = WIDGET ] || fail "a fresh init no longer derives the prefix WIDGET from widget-app"
grep -q 'WIDGET_WORKER_DONE' "$F/AGENTS.md" || fail "a fresh init's AGENTS.md does not name WIDGET_WORKER_DONE"

echo "ok: SK-13"
