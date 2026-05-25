# agent instruction

**Never let staging directories leak into history even if gitignored.** Build-context dirs containing large pre-staged binaries (700+MB in this project) sit on disk between sessions. Always check `git status` immediately before `git add`, and prefer adding files by name (`git add Dockerfile entrypoint.sh`) over `git add -A` in repos with active staging dirs. A leaked 400MB `node22` directory is a one-line gitignore fix only if you catch it before the commit.

*Grounded in: build-context/ accumulated 700MB of pre-staged binaries (node22, claude-code, gc, dolt, bd) during this session; only gitignore convention prevented them from landing in commits.*

# justification

This session's `build-context/` accumulated ~700 MB across `node22` (433 MB), `claude-code` (228 MB), `gc` (100 MB), and `dolt` + `bd` tarballs. Without the early `build-context/*` gitignore entry, `git add -A retrospective/` or `git add -A` would have staged all of it. The leakage is recoverable but ugly (a force-push, a clean rebase, or a fresh branch) and frustrating in a multi-agent setup where another agent on the same branch might have already pulled the polluted history. The cost of the rule is one `git status` glance before staging (sub-second). The cost of skipping is "a 700 MB push that takes minutes, fails on github's filter limits, and leaves your branch in a half-committed state." This rule is especially important after the `stage-binaries-on-host-for-docker-build` skill has been used; that skill creates the dir, this rule prevents it from leaking.
