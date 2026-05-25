# ADR: Split compose into a laptop file and a sandbox overlay

- **ID**: ADR-31143cd0d0
- **Status**: Draft (not yet adopted to docs/adr/)
- **Date**: 2026-05-25
- **Source retrospective**: ../2026-05-25-4.md
- **PRs covered**: #2

## Context

The Gas City prototype needs to run in two distinct environments:
the user's laptop (normal egress to github.com and api.anthropic.com,
auth via `ANTHROPIC_API_KEY`) and the Anthropic sandbox (egress goes
through a local git proxy at `127.0.0.1:<port>`, TLS interception
requires bind-mounting the host's CA bundle, auth via
`CLAUDE_CODE_OAUTH_TOKEN` from a host-side file). The runtime
differences are:

| Concern | Laptop | Sandbox |
|---|---|---|
| Network mode | default (bridge) | `network_mode: host` |
| CA bundle | image's own ca-certificates | bind-mount host's `/etc/ssl/certs/ca-certificates.crt` |
| Auth | `ANTHROPIC_API_KEY` env | `ANTHROPIC_BASE_URL` + `CLAUDE_CODE_OAUTH_TOKEN` |
| URL form (rigs/beadstore) | `https://github.com/...` | `http://local_proxy@127.0.0.1:.../git/...` |

Two viable compose patterns: (a) a single compose file with
environment-conditional toggles, or (b) a base compose file + a
sandbox overlay file that adds the sandbox-specific bits.

## Decision

Ship `docker-compose.yml` as the laptop-shaped service definition
and a separate `docker-compose.sandbox.yml` overlay that adds host
networking, the CA-bundle mount, and OAuth-token auth, rather than
parameterizing a single compose file with environment-dependent
toggles.

Laptop users run `docker compose up`; sandbox users run
`docker compose -f docker-compose.yml -f docker-compose.sandbox.yml up`.

## Alternatives considered

- **Single parameterized compose file with environment toggles.**
  Rejected because compose doesn't have first-class conditionals;
  you'd implement env-driven volume mounts and network modes via
  `${VAR:-default}` substitutions and document each one. The
  resulting file is hard to read because the laptop-shaped path is
  hidden behind defaults, and a typo in the env file silently picks
  the wrong path.
- **Separate `Dockerfile.sandbox` + separate compose.** Rejected
  because the image itself is identical between environments — all
  the environment-specific concerns are runtime (volume mounts,
  network, env vars), not build-time. Two Dockerfiles would
  duplicate the image surface unnecessarily.
- **A wrapper shell script (`run.sh`) that detects the environment
  and chooses arguments.** Rejected because compose overlays are the
  documented mechanism for exactly this case and reading
  `docker-compose.sandbox.yml` makes the differences obvious to a
  reviewer. A wrapper script hides them inside imperative code.

## Consequences

- Easier: the laptop reader sees a normal-looking compose file and
  has no idea the sandbox path exists unless they read the README.
- Easier: every sandbox-specific concern is in one place
  (`docker-compose.sandbox.yml`, 22 lines) — a reviewer can scan it
  to understand exactly what's different.
- Easier: when the sandbox's network policy changes, only the
  overlay file moves.
- Harder: sandbox users need to remember `-f docker-compose.yml -f
  docker-compose.sandbox.yml`. The README spells this out but it's
  an extra invocation hurdle. A `Makefile` target or a `.envrc` hint
  could ease this.
- Accepted trade-off: explicit overlay file (clearer for review,
  slightly more typing) vs. single conditional file (one command,
  less clear).

## References

- [`../2026-05-25-4.md`](../2026-05-25-4.md) — the source retrospective.
- `docker-compose.yml` — laptop base.
- `docker-compose.sandbox.yml` — sandbox overlay.
- `README.md` — documents both invocations.
- PRs the decision was made in: #2.
