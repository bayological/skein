#!/usr/bin/env bash
# Acceptance for SK-20: the Superset driver waits on the agent state Superset CLI 2.0 reports
# instead of re-reading the screen, `skein watch` answers as soon as a worker's turn ends,
# every call that names a workspace, terminal or project passes --local, and `skein doctor`
# names a CLI that lacks the commands. Run from the repository root.
#
# The `superset` on PATH is a stand-in that answers in the shapes superset 2.0.0 printed on
# 2026-10-27, so nothing reaches a real Superset (AGENTS.md rule 10). It plays one agent turn
# by the clock: the agent works between two instants and rests outside them.
. docs/plan/accept/lib.sh

R="$SB/repo"; init_repo "$R"; cd "$R" || fail "no repo"
jq '.driver.type = "superset"' .skein/config.json > "$SB/config.json" && mv "$SB/config.json" .skein/config.json
F="$SB/superset"; mkdir -p "$F" "$SB/home" "$SB/wt-1"
git rev-parse --show-toplevel > "$F/root"; printf '%s\n' "$SB/wt-1" > "$F/wt"
# driver_launch records Claude Code's folder trust in $HOME/.claude.json, and skein watch keeps its
# log in SKEIN_STATE_DIR: keep both in the sandbox.
export FAKE_SUPERSET="$F" HOME="$SB/home" SKEIN_STATE_DIR="$SB/state"

cat > "$SB/bin/superset" <<'NODE'
#!/usr/bin/env node
// State in $FAKE_SUPERSET: calls.jsonl (every argv, one JSON array a line), turn ("<start>
// <end>", epoch seconds), screen.before and screen.after (the agent's screen before and after
// the turn ends), setup (the setup terminal's screen), root, wt, and old (present: a CLI from
// before `schema`).
const fs = require("fs"), path = require("path");
const F = process.env.FAKE_SUPERSET, argv = process.argv.slice(2);
fs.appendFileSync(path.join(F, "calls.jsonl"), JSON.stringify(argv) + "\n");
const read = (n) => { try { return fs.readFileSync(path.join(F, n), "utf8"); } catch { return ""; } };
const opt = (n) => { const i = argv.indexOf(n); return i < 0 ? undefined : argv[i + 1]; };
const out = (o) => { process.stdout.write(JSON.stringify(o) + "\n"); process.exit(0); };
const err = (m, code = 1) => { process.stderr.write(m + "\n"); process.exit(code); };
const now = () => Date.now() / 1000;
const sleepUntil = (t) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, Math.max(0, (t - now()) * 1000));
const [start, end] = (read("turn").trim() || "0 0").split(/\s+/).map(Number);
const ws = { id: "ws-1", name: "feat: farewell function (HS-01)", projectId: "proj-1", type: "worktree", worktreePath: read("wt").trim(), tags: "running" };
if (argv[0] === "--version") { process.stdout.write("2.0.0\n"); process.exit(0); }
const cmd = argv.filter((a) => !a.startsWith("-")).slice(0, 2).join(" ").replace(/^workspaces /, "ws ");
switch (cmd) {
  case "schema":
    if (fs.existsSync(path.join(F, "old"))) err("error: unknown command 'schema'");
    out({ name: "superset", version: "2.0.0", commands: [
      { path: ["agents"], commands: ["create", "read", "wait"].map((c) => ({ path: ["agents", c] })) },
      { path: ["terminals"], commands: ["list", "read", "send", "wait"].map((c) => ({ path: ["terminals", c] })) },
      { path: ["workspaces"], commands: ["archive", "create", "get", "list", "update"].map((c) => ({ path: ["workspaces", c] })) },
    ] });
  case "auth whoami": out({ userId: "user-1" });
  case "projects list": out([{ id: "proj-1", name: "hello-swarm", path: read("root").trim(), repo: null }]);
  case "ws list": out([ws]);
  case "ws get": out(ws);
  case "terminals list": out({ sessions: [
    { terminalId: "term-setup", workspaceId: "ws-1", createdAt: 1, exited: false, exitCode: 0, attached: false, title: "agent@box:~/wt-1", customTitle: null },
    { terminalId: "term-1", workspaceId: "ws-1", createdAt: 2, exited: false, exitCode: 0, attached: false, title: "HS-01 worker", customTitle: null },
  ] });
  case "terminals read":
    out({ terminalId: opt("--terminal"), text: opt("--terminal") === "term-setup" ? read("setup") : read(now() < end ? "screen.before" : "screen.after") });
  case "terminals send": out({ terminalId: opt("--terminal") });
  case "terminals wait": {
    const timeout = Number(opt("--timeout") || 600), m = read("setup").match(new RegExp(opt("--match")));
    if (m) out({ terminalId: opt("--terminal"), matched: m[0] });
    sleepUntil(now() + timeout);
    err(`Error: Timed out after ${timeout}s without a match for ${opt("--match")}\nHint: Check the screen with \`superset terminals read\``);
  }
  case "agents create": out({ kind: "terminal", sessionId: "term-1", label: "Claude" });
  case "agents wait": {
    // working holds from start to end; settled (idle) holds before start and from end on.
    const until = opt("--until") || "settled", timeout = Number(opt("--timeout") || 600), t = now();
    const at = until === "working" ? (t < start ? start : t < end ? t : Infinity) : (t < start || t >= end ? t : end);
    if (at <= t + timeout) { sleepUntil(at); out({ terminalId: opt("--terminal"), state: until === "working" ? "working" : "idle", lastEventType: until === "working" ? "Start" : "Stop" }); }
    sleepUntil(t + timeout);
    err(`Error: Timed out after ${timeout}s; agent is ${now() >= start && now() < end ? "working" : "idle"}\nHint: Raise --timeout, or check it with \`superset terminals read\``);
  }
  default: err(`fake superset: unhandled: ${argv.join(" ")}`, 2);
}
NODE
chmod +x "$SB/bin/superset"

# driver <function> [args]: call one driver function the way a skein command does.
driver() { SKEIN_HOME="$KIT" bash -c '. "$SKEIN_HOME/lib/common.sh"; require_config; load_driver; "$@"' driver "$@"; }
# turn <start> <end>: the agent works from now+start to now+end, in seconds.
turn() { echo "$(( $(date +%s) + $1 )) $(( $(date +%s) + $2 ))" > "$F/turn"; }
# within <secs> <out-file> <command...>: run the command in the background, kill it after secs.
within() {
  local secs="$1" o="$2"; shift 2
  "$@" > "$o" 2>&1 & local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt "$secs" ]; do sleep 1; i=$((i + 1)); done
  kill -0 "$pid" 2>/dev/null && { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 124; }
  wait "$pid"
}
envelope() { printf 'HS_WORKER_DONE\ntask: HS-01\nsummary: %s\nfiles: src\nhandoff: none\n' "$1"; }

# 1. Setup: one `terminals wait` for the ready or fatal line, not a read every 3 seconds.
printf 'installing\nworkspace %s ready\n' "'feat: farewell function (HS-01)'" > "$F/setup"
driver driver_wait_setup ws-1 term-setup 20 || fail "driver_wait_setup failed on a setup screen with the readiness marker"
printf 'installing\nnpm ERR! code ELIFECYCLE\n' > "$F/setup"
driver driver_wait_setup ws-1 term-setup 20 2>"$SB/setup.err" && fail "driver_wait_setup passed a setup screen that failed"
grep -q 'npm ERR!' "$SB/setup.err" || fail "driver_wait_setup did not print the fatal line: $(cat "$SB/setup.err")"
[ "$(jq -c 'select(.[0:2] == ["terminals","wait"] and index("term-setup"))' "$F/calls.jsonl" | wc -l | tr -d ' ')" = 2 ] \
  || fail "driver_wait_setup does not wait with one 'superset terminals wait' per call"

# 2. Launch: started is the agent working, as Superset reports it, not a match on the screen.
printf '> do the task\n' > "$F/screen.before"; turn -1 600
term="$(within 40 "$SB/launch.out" driver driver_launch ws-1 claude - "" "do the task" && tail -1 "$SB/launch.out")" \
  || fail "driver_launch did not report a started agent within 40s: $(tail -3 "$SB/launch.out")"
[ "$term" = term-1 ] || fail "driver_launch printed '$term', not the session id term-1"
jq -e 'select(.[0:2] == ["agents","wait"] and index("working"))' "$F/calls.jsonl" >/dev/null \
  || fail "driver_launch does not wait for the agent to be working"
jq -e '.projects["'"$SB/wt-1"'"].hasTrustDialogAccepted' "$HOME/.claude.json" >/dev/null \
  || fail "driver_launch no longer records Claude Code's folder trust for the worktree"

# 3. Watch: the worker's turn ends 3s in, and the watch says DONE then, not a poll interval later.
envelope "the farewell function, with its test" > "$F/screen.after"; printf 'working on it\n' > "$F/screen.before"; turn -1 3
within 25 "$SB/watch.out" skein watch HS-01 - - 1 300 || fail "skein watch did not report within 25s of the turn ending (poll 300s): $(strip < "$SB/watch.out" | tail -3)"
grep -q 'SKEIN_WATCH task=HS-01 outcome=DONE' "$SB/watch.out" || fail "skein watch did not report DONE: $(strip < "$SB/watch.out" | head -3)"

# 4. Watch --resume: the agent rests with last round's envelope on screen, a new turn starts 2s
#    in and ends 4s in. Only the new envelope counts, and it counts as soon as the turn ends.
envelope "the farewell function" > "$F/screen.before"
{ cat "$F/screen.before"; envelope "the farewell function, review fixed"; } > "$F/screen.after"; turn 2 4
within 25 "$SB/resume.out" skein watch HS-01 - - 1 300 --resume || fail "skein watch --resume did not report within 25s of the new turn ending: $(strip < "$SB/resume.out" | tail -3)"
grep -q 'outcome=DONE' "$SB/resume.out" || fail "skein watch --resume did not report DONE"
grep -q 'review fixed' "$SB/resume.out" || fail "skein watch --resume did not show the new round's envelope"

# 5. Every call that names a workspace, terminal or project says --local: without it, CLI 2.0
#    sends terminals and agents commands to the cloud when the account has cloud workspaces.
bad="$(jq -r 'select(.[0] != "schema" and .[0] != "--version" and .[0:2] != ["auth","whoami"]) | select(index("--local") | not) | join(" ")' "$F/calls.jsonl" | sort -u | head -5)"
[ -z "$bad" ] || fail "superset calls without --local: $bad"

# 6. A CLI without agents wait and terminals wait: watch refuses at once rather than polling or
#    spinning, and doctor names it. Doctor passes 2.0.
touch "$F/old"; printf 'working on it\n' > "$F/screen.before"; turn 100 200
within 15 "$SB/old.out" skein watch HS-01 - - 1 300; rc=$?
[ "$rc" != 0 ] && [ "$rc" != 124 ] || fail "skein watch on a CLI without agents wait did not refuse within 15s (exit $rc)"
grep -q 'superset update' "$SB/old.out" || fail "skein watch on a CLI without agents wait does not say to run superset update: $(tail -2 "$SB/old.out")"
skein doctor 2>&1 | strip | grep -q 'superset update' || fail "skein doctor does not report a Superset CLI without agents wait and terminals wait"
rm -f "$F/old"
skein doctor 2>&1 | strip | grep -q 'superset update' && fail "skein doctor reports Superset CLI 2.0 as too old"

echo "ok: SK-20"
