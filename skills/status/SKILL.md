---
name: skein-status
description: What is happening across the flock right now: claims on the board, workers on this machine, both caps, and what is ready to dispatch. Read-only. Use when asked "status", "what's running", "what's ready", or "what happened while I was away".
---

# /skein-status

```bash
skein status
skein plan
```
Report in this order, one line per item: what needs the user (BLOCKED, needs-owner, a
review to triage), what is DONE awaiting the gate, what is working, what is ready to
dispatch under the caps, and what is blocked on deps. Never send anything to a worker from
this skill; offer the next action instead.
