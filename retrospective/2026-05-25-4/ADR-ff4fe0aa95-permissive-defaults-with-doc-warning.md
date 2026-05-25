# ADR: Bake permissive defaults into the image with a prominent security note

- **ID**: ADR-ff4fe0aa95
- **Status**: Draft (not yet adopted to docs/adr/)
- **Date**: 2026-05-25
- **Source retrospective**: ../2026-05-25-4.md
- **PRs covered**: #2

## Context

Gas City spawns interactive `claude` processes via tmux with the
`--dangerously-skip-permissions` flag (which lets the agent run any
shell command without per-action approval). Two safety gates inside
`claude` block this from working out-of-the-box in a server-like
container:

1. The `--dangerously-skip-permissions` flag itself refuses to run as
   root unless the env var `IS_SANDBOX=1` is set.
2. Each agent's first run, even with the flag, hits an interactive
   "bypass permissions warning" dialog that requires a typed-and-
   accepted confirmation. This dialog is invisible to the user
   running `docker compose up` and there's no way to dismiss it
   from outside the tmux session.

The dialogs and the root check exist to prevent a user from
accidentally giving an unprivileged process unrestricted shell
access on a real machine. In our case the container IS the sandbox —
it's an isolated, throwaway, agent-purpose runtime. The user has
already accepted the bypass-permissions risk by choosing to run
Gas City at all.

## Decision

Bake `IS_SANDBOX=1` and `bypassPermissionsModeAccepted=true` into the
image (the env var via `docker-compose.yml`'s `environment:` block,
the acceptance flag via `~/.claude.json`) so interactive claude does
not hang on safety dialogs in headless containers, and document the
security implication in the README rather than gating each user
behind a manual one-time setup.

## Alternatives considered

- **Don't bake the flags; require each user to run an interactive
  setup once.** Rejected because the dialog appears inside a tmux
  pane the user never sees (they're running `docker compose up -d`,
  not attaching), so there's nowhere to type the acceptance.
  Documentation alone can't bridge "an invisible dialog needs your
  attention."
- **Run the container as a non-root user.** Rejected for this
  session because the prototype has multiple bind mounts and the
  rig + beadstore + .gc directories all get written from inside the
  container; orchestrating UID matching across the mounts is a
  separate larger change. Worth revisiting if the image is ever
  meant for production-shaped use.
- **Patch gascity to not pass `--dangerously-skip-permissions`.**
  Rejected because the flag is a design choice in gascity, not a bug;
  the city's reconciler relies on agents being able to invoke `bd`,
  `gc`, `git`, etc. without per-action approval. Patching it away
  would break the agent contract.
- **Run an entirely separate setup container that completes the
  dialog once.** Rejected as Rube Goldberg — same outcome as baking
  the flag, more moving parts.

## Consequences

- Easier: `docker compose up` works on the first try; no invisible
  dialog blocks startup.
- Easier: the image is internally consistent — every agent process
  gets the same permissive treatment, no per-CWD surprises.
- Harder: anyone shipping this image to a context where the agents
  might handle untrusted input is opting every agent into bypass-
  permissions mode unconditionally. The README needs a prominent
  warning so the user knows what they signed up for.
- Accepted trade-off: usability (the image just works) vs. defense-
  in-depth (a future foot-gun is loaded by default). For a
  learning/demo container, the trade is correct. For a production-
  shaped use of this image, the user must explicitly evaluate the
  risk.

## References

- [`../2026-05-25-4.md`](../2026-05-25-4.md) — the source retrospective.
- `Dockerfile` — RUN block that writes `~/.claude.json` with global
  permissive flags.
- `docker-compose.yml` — `IS_SANDBOX=1` env entry, with a comment
  block flagging the security trade-off.
- `README.md` — should grow a "Security note" section calling this
  out explicitly (currently missing — flagged in the retro's
  "what's not done yet" section).
- `entrypoint.sh` — writes the per-path `projects[path]` map at
  runtime.
- PRs the decision was made in: #2.
