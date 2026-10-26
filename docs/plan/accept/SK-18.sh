#!/usr/bin/env bash
# Acceptance for SK-18: a config whose version is newer than the kit understands is refused
# by every command that requires a config; version 1 and a config with no version key still
# work; skein doctor reports the version. Run from the repository root.
. docs/plan/accept/lib.sh

R="$SB/repo"; init_repo "$R"; cd "$R" || fail "no repo"
[ "$(jq -r .version .skein/config.json)" = 1 ] || fail "the example's config is not version 1"
skein brief HS-01 --check >/dev/null 2>&1 || fail "a version 1 config is refused"
skein doctor 2>&1 | strip | grep -q '\.skein/config\.json (.*version 1)' || fail "skein doctor does not report the config version"

jq '.version = 2' .skein/config.json > "$SB/c.json" && mv "$SB/c.json" .skein/config.json || fail "could not edit the config"
for cmd in "brief HS-01 --check" "status" "dispatch HS-01"; do
  out="$(SKEIN_MAX_AGENTS=0 skein $cmd 2>&1)" && fail "skein $cmd accepted a version 2 config"
  printf '%s\n' "$out" | grep -q 'config.json is version 2; this kit understands version 1' \
    || fail "skein $cmd did not say why it refused the version 2 config: $(printf '%s\n' "$out" | tail -1)"
done

jq 'del(.version)' .skein/config.json > "$SB/c.json" && mv "$SB/c.json" .skein/config.json || fail "could not edit the config"
skein brief HS-01 --check >/dev/null 2>&1 || fail "a config with no version key is refused; older configs must keep working"

echo "ok: SK-18"
