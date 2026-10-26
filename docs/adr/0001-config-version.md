# DRAFT SK-18: a config version newer than the kit is refused

## Context
`skein init` has always written `"version": 1` into `.skein/config.json`, and nothing read it.
The bash commands take each value they need through `cfg`, which falls back to a default when
the key is missing or the file does not parse; the gate parses the file and reads the keys it
knows. So a kit handed a config written for a later kit ran as if it understood it: the
commands silently used defaults for keys whose meaning had changed, and the gate judged the
work with only the checks it knew — and still printed `status=PASS`.

The key only becomes a version once something refuses to go on when it is too new.

## Decision
A config is accepted when its `version` is absent, or is a JSON number that is a whole number
no greater than the kit's. Anything else stops the run before any value is read:

- absent is version 1, because that is what every config `init` wrote before the key was read;
- a version that is not a whole number (a string, a fraction, a negative) is refused as
  malformed, quoted as JSON writes it so `"1"` is tellable from `1`;
- a greater version is refused as too new, telling the reader to upgrade the kit;
- a file that is not valid JSON is refused rather than read as defaults.

Three places apply it, with the same three messages: `require_config`, which every running
command calls; `skein doctor`, which reports the version and flags a bad one; and the gate,
which stops with exit 2 — the code it already uses for a config it cannot use — on stderr,
with no result line, so a repository that parses `SKEIN_GATE_RESULT` sees no verdict rather
than a false one. `skein plan` and `skein init` are unchanged: neither calls `require_config`.

The number lives in two places, `KIT_CONFIG_VERSION` in `lib/common.sh` and `CONFIG_VERSION`
in `lib/gate.mjs`, each commented as the other's twin, because the kit is bash and Node and
shares nothing between them.

**Bumping it is one change, not three.** Changing what a config key means means raising
`KIT_CONFIG_VERSION`, the gate's `CONFIG_VERSION` and the literal `init` writes together, and
adding the migration that rewrites an older config to the new shape to `skein upgrade`. A bump
without that migration leaves every repository that vendored the kit refusing to run until
someone edits its config by hand.

## Consequences
An older kit, or an older vendored gate still sitting in a repository's CI, stops loudly on a
config it does not understand instead of judging the work partly and passing it. The cost is
that a config bump makes old kits fail rather than degrade, which is the point: the failure
names the config, the version and the fix.

A repository whose config has been edited into invalid JSON now gets one clear message from
every command, where before each key quietly became its default.
