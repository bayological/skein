# One wave of a skein swarm, recorded in a throwaway sandbox.
#
# Re-record from the repository root:  vhs docs/demo/demo.tape
# It needs vhs, ttyd and ffmpeg on PATH. docs/demo/README.md explains what it shows.
#
# The sandbox is built by docs/demo/setup.sh while the recording is hidden: a copy of
# examples/hello-swarm with no origin remote, so skein runs in local mode with board none
# and driver local. The workers are docs/demo/claude, a stub that makes each task's commit,
# so this spends nothing and plays the same way every time.

Output docs/assets/demo.gif

Require vhs
Require ttyd
Require ffmpeg

Set Shell "bash"
Set FontSize 16
Set Width 1200
Set Height 700
Set Padding 20
Set Framerate 10
Set TypingSpeed 35ms
Set Theme "Catppuccin Mocha"

Hide
Type "unset PROMPT_COMMAND; source docs/demo/setup.sh" Enter
Sleep 10s
Show

# 1. The plan: what is ready, and what can run together.
Type "# hello-swarm: three tasks. worker commits scripted for the recording" Enter
Sleep 1500ms
Type "skein plan" Enter
Sleep 5s

# 2. Two workers, one wave. Each gets a git worktree and a branch of its own.
Type "skein dispatch HS-01" Enter
Sleep 5s
Type "skein dispatch HS-02" Enter
Sleep 6s
Type "clear" Enter

# 3. What is running here, and what each worker says about itself.
Type "skein status" Enter
Sleep 7s

# 4. HS-02 reported done with checks: not run. The gate decides.
Type "# a worker's claim is not evidence: run the gate the coordinator runs" Enter
Sleep 2s
Type `(cd "$(wt HS-02)" && skein gate HS-02)` Enter
Sleep 8s

# 5. Back to the same session, with the failure. Then gate it again.
Type `skein send HS-02 "the gate failed test-integrity: put the three tests in test/greet.test.mjs back, with the new expected values"` Enter
Sleep 6s
Type `(cd "$(wt HS-02)" && skein gate HS-02)` Enter
Sleep 6s
Type "clear" Enter

# 6. Merge both. Each merge reruns the gate in the worker's worktree first.
Type "skein merge HS-01" Enter
Sleep 2500ms
Type "skein merge HS-02" Enter
Sleep 3500ms
Type "clear" Enter

# 7. HS-03 was waiting on both.
Type "skein plan" Enter
Sleep 5s
