#!/usr/bin/env bash
# skein upgrade — resync the vendored runtime from the installed kit. Config, plan, briefs
# and rendered docs are left alone; only scripts/skein/ (and the kit-owned pre-push hook)
# are refreshed. Run from the kit: ~/.claude/skills/skein/bin/skein upgrade.
. "$SKEIN_HOME/lib/common.sh"; require_config
[ -d "$SKEIN_HOME/templates" ] || die "upgrade needs the kit; run ~/.claude/skills/skein/bin/skein upgrade"
cd "$ROOT"; VENDOR="$(cfg .vendor scripts/skein)"
old="$(cat "$VENDOR/VERSION" 2>/dev/null || echo none)"; new="$(cat "$SKEIN_HOME/VERSION")"
[ -n "${SKEIN_KIT_GIT:-}" ] || ( cd "$SKEIN_HOME" && git pull -q --ff-only 2>/dev/null ) || warn "could not git pull the kit; upgrading from the local copy"
new="$(cat "$SKEIN_HOME/VERSION")"
rm -rf "$VENDOR/lib" "$VENDOR/commands"; mkdir -p "$VENDOR"
cp "$SKEIN_HOME/bin/skein" "$VENDOR/skein"; cp -r "$SKEIN_HOME/lib" "$SKEIN_HOME/commands" "$VENDOR/"; cp "$SKEIN_HOME/VERSION" "$VENDOR/VERSION"
rm -f "$VENDOR/commands/init.sh" "$VENDOR/commands/upgrade.sh"
mkdir -p "$VENDOR/templates"; cp "$SKEIN_HOME/templates/brief.md.tmpl" "$SKEIN_HOME/templates/review-prompt.md" "$VENDOR/templates/"
chmod +x "$VENDOR/skein"
node "$SKEIN_HOME/lib/render.mjs" "$SKEIN_HOME/templates/pre-push.tmpl" scripts/githooks/pre-push BASE="$(cfg .baseBranch main)" COORD_ENV="$COORD_ENV"; chmod +x scripts/githooks/pre-push
log "vendored skein $old -> $new in $VENDOR/ (config, plan, briefs untouched)"
