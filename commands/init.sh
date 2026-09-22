#!/usr/bin/env bash
# skein init [--name n] [--prefix P] [--board github|superset|none] [--driver superset|local]
#            [--base main] [--force-templates]
# Scaffold a repo for skein: .skein/config.json, the vendored scripts, AGENTS.md, docs/plan,
# CI, hooks and Superset lifecycle scripts. Idempotent: existing files are left alone unless
# --force-templates; the vendored scripts are always refreshed. Runs from the kit, not from
# a vendored copy (it needs the templates).
. "$SKEIN_HOME/lib/common.sh"
need git jq node
[ -d "$SKEIN_HOME/templates" ] || die "init needs the kit's templates; run ~/.claude/skills/skein/bin/skein init"

NAME=""; PREFIX=""; BOARD=github; DRIVER=superset; BASE=""; FORCE=""
while [ $# -gt 0 ]; do case "$1" in
  --name) NAME="$2"; shift 2 ;; --prefix) PREFIX="$2"; shift 2 ;; --board) BOARD="$2"; shift 2 ;;
  --driver) DRIVER="$2"; shift 2 ;; --base) BASE="$2"; shift 2 ;; --force-templates) FORCE=1; shift ;;
  *) die "unknown flag $1" ;; esac; done
cd "$ROOT"
[ -n "$NAME" ] || NAME="$(basename "$ROOT")"
[ -n "$PREFIX" ] || PREFIX="$(tr '[:lower:]' '[:upper:]' <<<"${NAME%%-*}" | tr -cd 'A-Z0-9' | cut -c1-6)"
[ -n "$BASE" ] || BASE="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')"; BASE="${BASE:-main}"
PREFIX_LC="$(tr '[:upper:]' '[:lower:]' <<<"$PREFIX")"
VENDOR="scripts/skein"; GATE="$VENDOR/skein gate"; COORD_ENV="${PREFIX}_COORDINATOR"; ENVELOPE="${PREFIX}_WORKER"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || git remote get-url origin 2>/dev/null | sed -E 's#.*[:/]([^/]+/[^/]+?)(\.git)?$#\1#')"

# --- detect the toolchain
PM=""; INSTALL=""; LOCKFILE=""; CI_SETUP=""; DEV_CMD=""; DEV_PORT=3000; PREPARE="true"
if   [ -f pnpm-lock.yaml ]; then PM=pnpm; INSTALL="pnpm install --frozen-lockfile --prefer-offline"; LOCKFILE=pnpm-lock.yaml
elif [ -f bun.lock ] || [ -f bun.lockb ]; then PM=bun; INSTALL="bun install --frozen-lockfile"; LOCKFILE="bun.lock*"
elif [ -f yarn.lock ]; then PM=yarn; INSTALL="yarn install --frozen-lockfile"; LOCKFILE=yarn.lock
elif [ -f package-lock.json ]; then PM=npm; INSTALL="npm ci --prefer-offline --no-audit --no-fund"; LOCKFILE=package-lock.json
elif [ -f package.json ]; then PM=npm; INSTALL="npm install"; LOCKFILE=package-lock.json
elif [ -f Cargo.toml ]; then PM=cargo; INSTALL="cargo fetch"; LOCKFILE=Cargo.lock
elif [ -f pyproject.toml ]; then PM=uv; INSTALL="uv sync"; LOCKFILE=uv.lock
elif [ -f go.mod ]; then PM=go; INSTALL="go mod download"; LOCKFILE=go.sum
fi
STANDARD=()
case "$PM" in
  pnpm|npm|yarn|bun)
    run="$PM run"; [ "$PM" = pnpm ] && [ -f pnpm-workspace.yaml ] && run="pnpm -r run"
    for s in typecheck lint test; do jq -e --arg s "$s" '.scripts[$s]' package.json >/dev/null 2>&1 && STANDARD+=("$run $s"); done
    jq -e '.scripts.dev' package.json >/dev/null 2>&1 && DEV_CMD="$PM run dev"
    nodev="$(cat .nvmrc 2>/dev/null | tr -d 'v\n' || true)"; nodev="${nodev:-$(jq -r '.engines.node // ""' package.json 2>/dev/null | grep -oE '[0-9]+' | head -1)}"; nodev="${nodev:-24}"
    CI_SETUP="      - uses: actions/setup-node@v4
        with:
          node-version: ${nodev}"
    [ "$PM" = pnpm ] && CI_SETUP="      - uses: pnpm/action-setup@v4
        with:
          version: $(jq -r '.packageManager // "" | sub("pnpm@";"")' package.json 2>/dev/null | grep -E '^[0-9]' || echo 10)
$CI_SETUP
          cache: pnpm"
    [ "$PM" = bun ] && CI_SETUP="      - uses: oven-sh/setup-bun@v2" ;;
  cargo) STANDARD=("cargo fmt --check" "cargo clippy --all-targets -- -D warnings" "cargo test"); CI_SETUP="      - uses: dtolnay/rust-toolchain@stable" ;;
  uv) STANDARD=("uv run ruff check ." "uv run pytest"); CI_SETUP="      - uses: astral-sh/setup-uv@v5" ;;
  go) STANDARD=("go vet ./..." "go test ./..."); CI_SETUP="      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod" ;;
esac
[ -n "$INSTALL" ] || INSTALL="true"
ENV_FILES="$(ls -a .env .env.local 2>/dev/null | tr '\n' ' ')"; ENV_FILES="${ENV_FILES:-.env}"

# --- config (left alone if present)
mkdir -p .skein
if [ -f .skein/config.json ] && [ -z "$FORCE" ]; then log "keeping existing .skein/config.json"
else
  jq -n --arg name "$NAME" --arg prefix "$PREFIX" --arg board "$BOARD" --arg repo "$REPO" --arg driver "$DRIVER" \
        --arg base "$BASE" --arg install "$INSTALL" --argjson standard "$(printf '%s\n' "${STANDARD[@]:-}" | grep -v '^$' | jq -R . | jq -s .)" \
        --arg gate "$GATE" --arg vendor "$VENDOR" --arg coord "$COORD_ENV" --arg envelope "$ENVELOPE" '{
    version: 1, name: $name, prefix: $prefix, envelope: $envelope, coordinatorEnv: $coord,
    plan: "docs/plan/wps.json", briefs: "docs/plan/briefs", vendor: $vendor, gate: $gate, baseBranch: $base,
    board: {type: $board, repo: $repo}, driver: {type: $driver}, maxAgents: 6,
    install: $install, standard: $standard, e2e: [], invariants: [], monotonic: [], secretPatterns: [], secretAllow: [],
    worker: {agent: "claude", model: "claude-opus-5", effort: "high"},
    review: {agent: "codex", model: "gpt-6-astra", fallbackModel: "claude-fable-5-1"},
    readyMarker: "workspace '"'"'.*'"'"' ready", setupScript: ".superset/setup.sh", setupTimeout: 300
  }' > .skein/config.json
  log "wrote .skein/config.json (pm=${PM:-none}, standard=${#STANDARD[@]} cmds, board=$BOARD, driver=$DRIVER)"
fi

# --- vendor the runtime
rm -rf "$VENDOR/lib" "$VENDOR/commands"; mkdir -p "$VENDOR"
cp "$SKEIN_HOME/bin/skein" "$VENDOR/skein"; cp -r "$SKEIN_HOME/lib" "$SKEIN_HOME/commands" "$VENDOR/"; cp "$SKEIN_HOME/VERSION" "$VENDOR/VERSION"
rm -f "$VENDOR/commands/init.sh" "$VENDOR/commands/upgrade.sh"   # need the kit's templates
chmod +x "$VENDOR/skein"
log "vendored skein $(cat "$VENDOR/VERSION") into $VENDOR/"

# --- templates (left alone if present)
STANDARD_LINES="$(printf '%s\n' "${STANDARD[@]:-}" | grep -v '^$' | paste -sd'\n' -)"
STANDARD_YAML="$(printf '%s\n' "${STANDARD[@]:-}" | grep -v '^$' | sed 's/^/          /')"
render() {  # render <template> <dest>
  local tpl="$1" dest="$2"
  if [ -e "$dest" ] && [ -z "$FORCE" ] && [ "${3:-}" != always ]; then log "keeping $dest"; return 0; fi
  node "$SKEIN_HOME/lib/render.mjs" "$SKEIN_HOME/templates/$tpl" "$dest" \
    NAME="$NAME" PREFIX="$PREFIX" PREFIX_LC="$PREFIX_LC" ENVELOPE="$ENVELOPE" COORD_ENV="$COORD_ENV" BASE="$BASE" \
    PLAN="docs/plan/wps.json" BRIEFS="docs/plan/briefs" VENDOR="$VENDOR" GATE="$GATE" INSTALL="$INSTALL" \
    STANDARD_LINES="${STANDARD_LINES:-# no standard commands detected: add typecheck/lint/test scripts}" \
    STANDARD_YAML="${STANDARD_YAML:-          echo no standard commands configured}" CI_SETUP="$CI_SETUP" \
    LOCKFILE="${LOCKFILE:-package-lock.json}" BOARD="$BOARD" REPO="$REPO" ENV_FILES="$ENV_FILES" ENV_WITHHOLD="" PREPARE="$PREPARE" \
    DEV_CMD="${DEV_CMD:-echo 'no dev command configured'}" DEV_PORT="$DEV_PORT" \
    PROJECT_RULES="" PROJECT_HYGIENE="" PROJECT_ONBOARDING=""
  log "wrote $dest"
}
render AGENTS.md.tmpl AGENTS.md
render COORDINATOR.md.tmpl docs/plan/COORDINATOR.md
render COORDINATOR-PROMPT.md.tmpl docs/plan/COORDINATOR-PROMPT.md
render ONBOARDING.md.tmpl docs/plan/ONBOARDING.md
render wps.json.tmpl docs/plan/wps.json
mkdir -p docs/plan/briefs docs/adr; touch docs/plan/briefs/.gitkeep
[ -f docs/adr/README.md ] || cp "$SKEIN_HOME/templates/adr-README.md" docs/adr/README.md
render ci.yml.tmpl .github/workflows/skein-gate.yml
render pre-push.tmpl scripts/githooks/pre-push always; chmod +x scripts/githooks/pre-push
[ -f .superset/config.json ] || { mkdir -p .superset; cp "$SKEIN_HOME/templates/superset/config.json" .superset/config.json; log "wrote .superset/config.json"; }
render superset/setup.sh.tmpl .superset/setup.sh; chmod +x .superset/setup.sh
[ -f .superset/teardown.sh ] || { cp "$SKEIN_HOME/templates/superset/teardown.sh" .superset/teardown.sh; chmod +x .superset/teardown.sh; log "wrote .superset/teardown.sh"; }
[ -n "$DEV_CMD" ] && { render superset/run.sh.tmpl .superset/run.sh; chmod +x .superset/run.sh; }
grep -qx '.superset/config.local.json' .gitignore 2>/dev/null || printf '.superset/config.local.json\n' >> .gitignore
# Dead-code tools would flag the vendored runtime as unused files; tell knip to skip it.
if [ -f knip.json ] && ! jq -e --arg v "$VENDOR/**" '(.ignore // []) | index($v)' knip.json >/dev/null 2>&1; then
  jq --arg v "$VENDOR/**" '.ignore = ((.ignore // []) + [$v] | unique)' knip.json > knip.json.tmp && mv knip.json.tmp knip.json && log "added $VENDOR/** to knip.json ignore"
fi
git config core.hooksPath scripts/githooks

cat <<NEXT

skein init done for $NAME ($PREFIX-xx tasks, board=$BOARD, driver=$DRIVER, base=$BASE).

Next:
  1. Fill "## Project rules" in AGENTS.md (money, data, infrastructure) and the invariants
     in .skein/config.json. The /skein-init skill can interview you for these.
  2. Check .skein/config.json "standard" commands and add "e2e" if the repo has a heavier suite.
  3. Add the first task to docs/plan/wps.json and write its brief (/skein-brief).
  4. Commit, push $BASE, then: skein doctor && skein plan.
NEXT
