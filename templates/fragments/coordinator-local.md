> **Local mode.** This repo has no `origin`. Read every `origin/{{BASE}}` below as the local
> `{{BASE}}`: workspaces fork from it, so commit briefs and the plan there before dispatching.
> Nothing is pushed and there are no pull requests: workers leave their work on their branch,
> `skein merge` squash-merges it into `{{BASE}}` here, and `skein review` writes its findings
> to `docs/plan/reviews/<ID>.md`. Push the whole repo by hand whenever you want it on GitHub.
