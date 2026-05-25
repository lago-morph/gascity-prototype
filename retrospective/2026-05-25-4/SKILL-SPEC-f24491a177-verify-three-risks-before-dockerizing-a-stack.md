# Spec: `verify-three-risks-before-dockerizing-a-stack`

- **ID**: SKILL-SPEC-f24491a177
- **Source retrospective**: ../2026-05-25-4.md

## Intent

Before writing a Dockerfile that bundles multiple network-accessing tools,
identify the three or so highest-risk integrations and verify each
end-to-end in a throwaway container or one-shot exec. Spend roughly
30 minutes here; the cost of finding a blocker at build time is multiple
5-minute rebuild cycles plus context-loss, whereas finding it upfront
usually costs one extra `docker run` with `--rm`.

## Trigger

- Direct: "build a Docker image for X stack", "containerize this Y service",
  "Dockerize gascity / Beads / a multi-agent setup".
- Proactive: any time a Dockerfile would bundle three or more components
  that each have non-trivial integration (auth tokens, custom git remotes,
  filesystem-based IPC, sub-process spawning). Especially in a sandbox or
  proxied environment.
- Negative: don't use for a single-binary "FROM alpine; COPY my-app" image
  with no network dependencies. The fixed cost dominates the savings.

## Inputs

- A short description of what the image will run.
- Knowledge of the runtime environment (sandbox? developer laptop?
  CI runner?).
- Access to docker on the build environment.

## Outputs

- A list of 2–4 risk items, each with a verified status (cleared /
  cleared-with-workaround / blocked).
- For each cleared-with-workaround risk: the workaround captured as a
  one-paragraph note in the Dockerfile / compose / docs (so it's recoverable
  later).
- A go/no-go decision before writing the Dockerfile.

## Workflow

1. Enumerate the riskiest 2–4 integrations. Use these prompts to find them:
   - "What requires the container to reach the outside network?" (Auth
     tokens, package registries, git remotes, S3, etc.)
   - "What requires the container to spawn subprocesses?" (CLI shellouts,
     tmux, dolt SQL servers, sidecars.)
   - "What requires the container to share state with the host?" (Volumes
     for credentials, OIDC token caches, X11 sockets.)
   - "What's the integration most novel to this stack?" (The thing you
     haven't done before — that one almost always has a surprise.)
2. For each risk, design a single one-shot verification:
   - Tooling check: `docker run --rm <base> bash -c '<one command that
     exercises the risk>'`.
   - Network check: include `--network=host` (or whichever mode the real
     image will use) so the test exercises the same routing.
   - Bring in only the minimum: don't build the full image to verify
     proxy reach.
3. Run each verification. Record the result inline (in the chat or a
   scratch file).
4. For each cleared-with-workaround risk, write a comment block now (in
   `docs/`, in the future Dockerfile as a header comment, or in `PLAN.md`).
   The information will not stay in working memory through the build.
5. If any risk is genuinely blocked (not just workaround-required), stop
   and surface to the user with options. Do not start writing the
   Dockerfile.
6. If all are cleared, write the Dockerfile. As you go, pattern-match
   against the recorded workarounds — most of them want a `COPY` of a
   bind mount, a baked-in env var, or an entrypoint quirk.

## Concrete examples

### Example 1: Gas City prototype — 3 risks, all cleared with workarounds

Three risks identified at session start:

1. **Container-to-proxy reachability** — sandbox has a local git proxy
   at `127.0.0.1:38985`. Will it work from inside a container?
   Verified via `docker run --rm --network=host ubuntu:24.04 bash -c
   'git ls-remote http://local_proxy@127.0.0.1:38985/git/lago-morph/...'`.
   Result: works with `--network=host`. Workaround: compose
   `network_mode: host` on sandbox.
2. **Dolt push to a GitHub repo through the proxy** — does dolt's
   git-remote feature work with the proxy URL? First attempt failed
   ("HTTP 403"); turned out the proxy only allows pushes to
   `refs/heads/*`, not the default `refs/dolt/data`. Workaround:
   `dolt remote add --ref refs/heads/dolt-data origin <url>`.
3. **Claude in tmux in container** — does the interactive `claude`
   process get a working OAuth/API auth inside a container?
   Initial probes failed (TLS interception); fixed by mounting
   `/etc/ssl/certs/ca-certificates.crt` from the host and setting
   `NODE_EXTRA_CA_CERTS`. Subsequent probes failed on theme picker /
   trust dialogs; fixed by pre-seeding `~/.claude.json`. All recorded
   as compose env vars + image-baked settings.

Total: ~30 minutes upfront. The two workarounds (`--ref refs/heads/dolt-data`,
CA bundle mount) would have presented at build time or first-run time as
opaque failures; finding them as risk-clearance items meant the Dockerfile
landed mostly right on iteration 2.

### Example 2: when to skip — single-purpose static binary

A Dockerfile that bundles only a self-contained Rust binary with `FROM
gcr.io/distroless/cc-debian12` and no network dependencies at runtime
doesn't need this skill. The risk surface is too small to justify the
overhead.

## Anti-patterns

- **Writing the Dockerfile first, debugging at build time.** The
  rebuild loop is 30+ seconds at minimum (often minutes), so any
  network-related failure costs you a full cycle. Three failures =
  10+ minutes per workaround discovery. The risk-clearance pass costs
  a similar amount of time but front-loads the failures into low-stakes
  one-shot containers where the failure mode is visible.
- **Identifying more than 4 risks and trying to verify all of them.**
  Diminishing returns; the goal is to surface the highest-cost
  surprises, not exhaustively check every assumption. Pick the 2–4
  with highest cost-of-finding-late × probability-of-failing.
- **Skipping the "record the workaround" step.** Workarounds that
  aren't written down at risk-clearance time get rediscovered later
  the hard way. Drop them into the future Dockerfile or compose file
  as a comment now.
- **Verifying with the wrong network mode.** If the real image will
  use `--network=host`, run the verification with `--network=host`.
  A clean default-bridge test followed by a host-network production
  is misleading.

## Acceptance criteria

- [ ] Each of the 2–4 risk items has a verified-status record before
      the first commit of the Dockerfile.
- [ ] Each "cleared with workaround" risk has its workaround written
      down somewhere version-controlled (PLAN, Dockerfile comment,
      docs) by end of the verification pass.
- [ ] If any risk is blocked, the session pauses and surfaces to the
      user before further Dockerfile work.
- [ ] Total time spent in risk verification is bounded (~30 minutes
      for a 3-risk stack); if it exceeds an hour, the risks were
      mis-scoped and need re-listing.

## Files this skill creates / modifies

- `docs/PLAN.md` (or equivalent) — a "Risk verification results" section
  capturing each risk + verification command + result.
- Future `Dockerfile` — header comments encoding workarounds that
  affect image construction.
- Future `docker-compose.yml` — env / volume / network entries that
  encode workarounds that affect runtime.
