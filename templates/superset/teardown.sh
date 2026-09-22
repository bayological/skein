#!/usr/bin/env bash
# Workspace teardown: stop any long-running process an agent left behind in this worktree
# (a dev server holding its port). Scoped by the process's working directory: never a
# broad pkill, which would take other workspaces' servers and the owner's with it.
ws=$(cd "${SUPERSET_WORKSPACE_PATH:-.}" 2>/dev/null && pwd -P) || exit 0
[ -n "$ws" ] && [ "$ws" != / ] || exit 0
cwd_of() { if [ -L "/proc/$1/cwd" ]; then readlink "/proc/$1/cwd"; else lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'; fi; }
pids=""
for pid in $(pgrep -u "$(id -u)" -f 'node|bun|deno|python|cargo|next-server|vite' 2>/dev/null); do
  [ "$pid" = "$$" ] && continue
  case "$(cwd_of "$pid" 2>/dev/null)" in "$ws" | "$ws"/*) pids="$pids $pid" ;; esac
done
[ -n "$pids" ] || exit 0
echo "Stopping processes running from $ws:$pids"
kill $pids 2>/dev/null
for _ in 1 2 3 4 5; do sleep 1; kill -0 $pids 2>/dev/null || exit 0; done
kill -9 $pids 2>/dev/null
exit 0
