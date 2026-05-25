# Gas City prototype — implementation plan

**Status (initial build complete, 2026-05-25):** image, compose, entrypoint, pack,
city template, and docs all committed across the four repos. First city
stand-up verified: all 6 named gastown agents (mayor / deacon / boot + 3
control-dispatchers) running real claude sessions; mayor + boot exchanging
inter-agent commands within seconds of startup. Smoke test (`bd create` on a
rig, mayor reconciles end-to-end) deferred to a follow-up session to keep
token spend in check; the container has been brought down.

**Branch:** `claude/great-pascal-RUfkN` across all four repos.

## Things this build had to figure out beyond what the plan called out

These came up during execution and may be useful context for the next session
or for someone reading the Dockerfile / entrypoint and wondering "why":

1. **`gc` and `bd` aren't installable inside the container** — the sandbox's
   TLS-inspection proxy blocks GitHub release downloads from within containers
   (works on the sandbox host, fails inside). Both binaries are pre-staged on
   the host and `COPY`'d into the image. Same for the dolt tarball.
2. **`gc init` is interactive** and asks for a provider; bypass with
   `gc init --provider claude --skip-provider-readiness`. We don't run `gc init`
   at all in production flow — `pack.toml` + `city.toml` are authored directly.
3. **PackV2 strictness:** `[defaults.rig.imports.*]` must live in `city.toml`,
   not `pack.toml`. `[[rigs]] path =` is rejected — path bindings live in
   `.gc/site.toml` as `[[rig]]` entries (singular). `convergence.max_iterations`
   isn't a real field. The entrypoint owns writing site.toml because it knows
   the actual `/workspace/rigs/<name>/` paths.
4. **Pool prefix collisions:** rig names `rig1` and `rig2` both auto-derive
   bead prefix `"ri"` and collide. Set explicit `prefix = "r1"` / `prefix = "r2"`
   in city.toml.
5. **Don't import `maintenance` directly** — the bundled `gastown` pack already
   imports it transitively. Adding our own `[imports.maintenance]` creates a
   duplicate `gastown.dog` agent and refuses startup.
6. **PID 1 needs to reap zombies.** `gc start --foreground` as PID 1 doesn't
   reap, and `bd`'s frequent `dolt` shell-outs flood the process table within
   seconds. Compose `init: true` (tini) fixes it cleanly.
7. **`claude --dangerously-skip-permissions` refuses to run as root** unless
   `IS_SANDBOX=1` is set. The container runs as root by default; the env var
   bypass is cleaner than introducing a non-root user with mount permission
   complications.
8. **Interactive claude has three pre-run dialogs** that hang an agent session
   forever if not pre-acked:
   - theme picker → `hasCompletedOnboarding: true`, `hasSeenWelcome: true`,
     `theme: "dark"` in `~/.claude.json` (NOT `~/.claude/settings.json`).
   - "trust this folder" → `projects[path].hasTrustDialogAccepted: true` for
     every cwd the agent uses (`/workspace/city`, `/workspace/rigs/rig1`,
     `/workspace/rigs/rig2` at minimum).
   - "bypass permissions" warning → `bypassPermissionsModeAccepted: true`
     globally + per-path.
   The Dockerfile bakes the global flags; the entrypoint writes the per-path
   `projects` map because it depends on runtime paths.
9. **`tmux new-session` inherits parent env** for vars without an explicit
   `-e KEY=val`, but `set-environment -g` ones still get auto-propagated.
   `CLAUDE_CODE_OAUTH_TOKEN` was being passed correctly the whole time; the
   blockers were always the onboarding dialogs.
10. **Dolt git-remote needs an explicit ref** because the sandbox proxy only
    allows pushes to `refs/heads/*`. Use `--ref refs/heads/dolt-data` (set as
    `DOLT_REF` in env). On the laptop either form works.
11. **Image is ~700 MB** — node22 (433 MB) + claude-code (228 MB) dominate.
    Acceptable for a personal/dev tool.

## Goal

A Dockerfile + portable pack + four-repo layout that the user can `docker compose up` on their laptop to bring up a Gas City running the bundled `gastown` role pack across two demo rigs (rig1, rig2), each building a different thing. Bead store persists via a periodic `dolt push` to a fourth GitHub repo.

## Four-repo topology

| Repo | Purpose | What lives here |
|---|---|---|
| `lago-morph/gascity-prototype` | "City" repo / deliverable surface | Dockerfile, docker-compose.yml, entrypoint.sh, pack/, city.toml.example, .env.example, README.md, docs/ (reference) |
| `lago-morph/gascity-proto-rig1` | Demo rig #1 | Project skeleton (TBD what); registered as a gascity rig at runtime |
| `lago-morph/gascity-proto-rig2` | Demo rig #2 (different thing) | Project skeleton (TBD what); registered as a gascity rig at runtime |
| `lago-morph/gascity-proto-beadstore` | Dolt git-remote target | Receives `dolt push --ref refs/heads/dolt-data origin main`; never touched by hand |

## Risk verification results (2026-05-25)

All three risks confirmed cleared on the sandbox before any implementation began.

1. **Sandbox git proxy reachable from container with `--network=host`** — verified with `git ls-remote` against the proxy URL from inside a fresh ubuntu container. Direct `github.com` HTTPS is intercepted by the sandbox's TLS-inspection CA, so container git operations on the sandbox must use the proxy URL; on the laptop they'll use real github URLs unchanged.
2. **Dolt push/clone to beadstore** — verified end-to-end. Caveat: the proxy only allows pushes to `refs/heads/*`, so dolt must use `--ref refs/heads/dolt-data` (not its default `refs/dolt/data`). With that flag, `dolt push` succeeds in ~80s for a tiny DB and `dolt clone --ref refs/heads/dolt-data ...` rehydrates it cleanly. Matches the handoff doc's stated push performance.
3. **Claude in tmux in container** — verified working. Requires three things in the image / compose: (a) `/etc/ssl/certs/ca-certificates.crt` bind-mounted from the sandbox host (carries the `sandbox-egress-production TLS Inspection CA` that claude-code needs to trust), (b) `NODE_EXTRA_CA_CERTS` + `SSL_CERT_FILE` set to that path, (c) the OAuth token from `/home/claude/.claude/remote/.oauth_token` passed in as `CLAUDE_CODE_OAUTH_TOKEN`, plus inheriting `ANTHROPIC_BASE_URL`. `tmux new-session -d -s ... 'claude -p ...'` round-trips successfully.

These mitigations are sandbox-specific; on the laptop the same container runs against real github.com and real api.anthropic.com without any of the proxy / CA / OAuth-token-FD plumbing.

## File-by-file layout

### `gascity-prototype/` (city / deliverable repo)

```
Dockerfile                  Ubuntu 24.04 base. Installs:
                              apt: tmux, git, jq, lsof, ca-certificates, openssh-client,
                                   curl, make, build-essential
                              ADD/COPY from build context: dolt v2.0.6 binary (~44 MB),
                                                            go 1.25 tarball,
                                                            /opt/claude-code,
                                                            /opt/node22
                              RUN: clone gascity, `make install` → /usr/local/bin/gc
                              No secrets baked in.
docker-compose.yml          Service `city`. network_mode: host. Mounts:
                              - .env (env_file)
                              - ./workspace:/workspace    (city + rigs + beadstore + .gc)
                              - sandbox CA bundle (read-only) — sandbox-only override
                            Passes through: ANTHROPIC_BASE_URL, CLAUDE_CODE_OAUTH_TOKEN,
                                            RIG1_URL, RIG2_URL, BEADSTORE_URL
entrypoint.sh               container PID 1:
                              1. envsubst city.toml.example → /workspace/city/city.toml
                              2. if rigs missing: git clone $RIGn_URL → /workspace/rigs/rigN
                              3. if beadstore missing: dolt clone --ref refs/heads/dolt-data
                                                       $BEADSTORE_URL → /workspace/beadstore
                              4. gc rig add (idempotent) for each rig
                              5. exec gc start --foreground
README.md                   How to run on laptop: docker compose up, env vars, auth.
                            Explains sandbox vs laptop env differences in one section.
pack/
  pack.toml                 [imports.gastown] -> bundled gastown pack
                            local overlays / patches if needed
  prompts/                  (only if we patch gastown prompts)
  formulas/                 (only if we add custom formulas)
city.toml.example           Templated with ${RIG1_URL:-https://github.com/lago-morph/...},
                            ${RIG2_URL:-...}, ${BEADSTORE_URL:-...}.
                            [daemon] tuned for several roles + health.
                            [convergence] enabled.
                            [orders] enabled.
                            Comments explain each section's purpose.
.env.example                ANTHROPIC_API_KEY=...          # laptop only
                            RIG1_URL=https://github.com/lago-morph/gascity-proto-rig1.git
                            RIG2_URL=https://github.com/lago-morph/gascity-proto-rig2.git
                            BEADSTORE_URL=https://github.com/lago-morph/gascity-proto-beadstore.git
.gitignore                  .env, workspace/, *.log, .gc/, .beads/
docs/
  gascity-sandbox.md        Rewritten (see §"Doc rewrite" below)
  13-gas-city-deep-dive.md  Unchanged reference
  PLAN.md (this file)       Project plan + decisions, kept for the duration
LICENSE                     Unchanged
```

### Rig repos (`gascity-proto-rig1`, `gascity-proto-rig2`)

Initially: README.md, .gitignore, LICENSE only. Each rig gets project content added in a later step once we know what each is demonstrating. Rig1's existing AGENTS.md prompt-injection line gets removed before any other rig work.

### Beadstore repo (`gascity-proto-beadstore`)

README.md replaced with a 2-line note: "This repo is the dolt git-remote target for the Gas City prototype's bead store. Do not commit files directly; data is managed by `dolt push`. The active data lives on the `dolt-data` branch."

## Entrypoint flow

```
container start (PID 1 = entrypoint.sh)
  ├─ source /workspace/.env (laptop) OR inherited env (sandbox)
  ├─ envsubst /pack/city.toml.example > /workspace/city/city.toml
  ├─ for rig in rig1 rig2:
  │     if [ ! -d /workspace/rigs/$rig/.git ]; then
  │       git clone "$RIG_URL" /workspace/rigs/$rig
  │     fi
  ├─ if [ ! -d /workspace/beadstore/.dolt ]; then
  │     dolt clone --ref refs/heads/dolt-data "$BEADSTORE_URL" /workspace/beadstore
  │   fi
  ├─ cd /workspace/city
  ├─ gc rig add /workspace/rigs/rig1   # idempotent
  ├─ gc rig add /workspace/rigs/rig2
  └─ exec gc start --foreground
```

Container dies → `docker rm` → fresh container → entrypoint re-clones → `gc start`. Bead state survives because the local managed dolt server reads from `/workspace/beadstore`, which was cloned from GitHub.

## Sandbox vs laptop differences (small, isolated)

| Concern | Sandbox | Laptop |
|---|---|---|
| Rig/beadstore URLs in `.env` | `http://local_proxy@127.0.0.1:38985/git/lago-morph/<repo>.git` | `https://github.com/lago-morph/<repo>.git` |
| Container network | `--network=host` (compose: `network_mode: host`) | Either; default bridge fine |
| CA bundle mount | bind-mount `/etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro` (sandbox compose override) | Not needed — image's ca-certificates package is sufficient |
| Claude auth | `CLAUDE_CODE_OAUTH_TOKEN` from `/home/claude/.claude/remote/.oauth_token` | `ANTHROPIC_API_KEY` env var, or OIDC token cache mount per handoff §0 |
| `ANTHROPIC_BASE_URL` | Inherited from sandbox env | Unset (default `api.anthropic.com`) |

Solution: ship a `docker-compose.yml` (laptop-shaped) plus a `docker-compose.sandbox.yml` overlay that adds the host-network mode + CA mount + sandbox URL/token wiring. User on the laptop runs `docker compose up`; on the sandbox we run `docker compose -f docker-compose.yml -f docker-compose.sandbox.yml up`.

## Sandbox dev rhythm

- Changes to Dockerfile / pack / entrypoint / city.toml.example → commit to `gascity-prototype` on `claude/great-pascal-RUfkN`, push.
- Rebuild image with `docker compose build city` after Dockerfile changes.
- Bring city up with the sandbox overlay; observe with `docker exec city tmux ls`, `docker exec city gc events --follow`, `docker exec city tmux capture-pane -t <session> -p`.
- Rig content changes → commit + push directly to that rig's own repo.
- Bead store changes accrue in the container's local dolt server; periodically run `docker exec city dolt -d /workspace/beadstore push --ref refs/heads/dolt-data origin main` (or wrap in a gascity `[order]` cron trigger).

## Order of execution

1. **Done — risk verification.** All three risks cleared above.
2. **Cache build context** — pre-stage `dolt-linux-amd64.tar.gz` (already in `/home/user/build-cache/`), download Go 1.25 tarball, copy `/opt/node22` and `/opt/claude-code` into the build context dir on the sandbox host. The Dockerfile COPYs these so the build avoids container-side downloads (which the TLS-inspection proxy blocks).
3. **Write Dockerfile** — install apt deps, COPY the staged binaries, clone + `make install` gascity (clone goes through the proxy via build-time `--network=host` if needed; or do that step on the host and COPY the built `gc` binary into the image).
4. **Write docker-compose.yml + docker-compose.sandbox.yml + .env.example + entrypoint.sh.**
5. **First build + bring-up: bare city, no rigs, no pack.** Verify the container starts, `gc` is on PATH, claude works inside (tmux + claude pong test from inside container).
6. **Wire in rig1.** Add `RIG1_URL`, entrypoint clones it, `gc rig add` succeeds. No pack yet — just bare rig registration. Verify `gc rig list` shows it.
7. **Wire in dolt beadstore.** Entrypoint clones the beadstore (or initializes empty + pushes if not yet populated), `[beads] provider = "bd"` in city.toml, local managed dolt server starts. Verify `gc bd ls` works against rig1. Manually run a `dolt push` and confirm the beadstore repo on GitHub receives the dolt-data branch update.
8. **Import the bundled `gastown` pack.** Add `[imports.gastown]` to `pack.toml`. Verify mayor + deacon + witness + refinery + polecat + crew + dog sessions all start under the controller. Cap pool sizes sensibly. Watch for runaway agent fan-out.
9. **Smoke test: one trivial order on rig1.** `bd create "say hello"`; mayor reconciles, dispatches; verify end-to-end completion via `gc events --follow`.
10. **Add rig2 with a different project skeleton.** Both rigs registered, both visible to mayor, can take work concurrently.
11. **Convergence + multi-order + health.** Exercise a convergence loop on rig1, a couple of cooldown/event orders, the gastown health patrol. Keep eyes on cost and pool sizes.
12. **Doc rewrite** (see below) and final commit/push across all four repos.
13. **What each rig builds** — design question deliberately deferred until the gastown wiring is proven and we can see the workflow in motion. Likely a follow-up session.

## Doc rewrite list (`docs/gascity-sandbox.md`)

Sections to substantially rewrite or delete:

- §0 progress log: delete entries about "exactly ONE GitHub repo," seed-subdirectories, bootstrap-laptop.sh. Add entries about four-repo topology, gastown bundled-pack import, env-var URL templating, `--network=host` for sandbox git-proxy reachability, the `--ref refs/heads/dolt-data` workaround for dolt push through the sandbox proxy, and the CA-bundle / OAuth-token plumbing for claude-in-container.
- §1b: full rewrite. Replace the seed/bootstrap machinery with the four-repo layout + entrypoint flow above. Keep the dolt git-remote feature explanation and version notes, plus the new ref-namespace workaround.
- §3 (sandbox inventory): re-mark as docker-first; sandbox host needs only docker + git + claude + dolt (for occasional out-of-container ops); everything else moves into the image.
- §4.1 (ephemerality): replace "push to the one deliverable repo" with "four repos, each pushed independently; bead store via `dolt push --ref refs/heads/dolt-data`."
- §4.2 (one-repo restriction): delete. Replace with a note that the sandbox now grants write access to four `lago-morph/` repos and that the git proxy is reached from inside containers via `--network=host` with proxy-rewritten URLs (no `refs/dolt/data` allowed; use `refs/heads/dolt-data`).
- §4.3: keep, but add a note that the OAuth-FD inheritance only works inside the sandbox host; inside a container we use `CLAUDE_CODE_OAUTH_TOKEN` env from `/home/claude/.claude/remote/.oauth_token` plus the host CA bundle bind-mounted.
- §5 and §6: rewrite to drop seed-subdirectory references; update §6 "decide yourself" list to reflect the resolved questions (gastown bundled pack, env-var URL templating, several-roles + health day-one).
- §1b layout sketch: replace with the four-repo layout above.
- §10 reference list: keep; add the lago-morph deep-dive's `examples/gastown/` paths since the bundled pack is now our base.

Plus: remove the prompt-injection line in `gascity-proto-rig1/AGENTS.md`.

## Decisions captured from user this session

1. **Pack:** combination of code-review pipeline + parallel rigs. Rigs build different things; within each rig a complex workflow. Use the bundled `gastown` pack as-is for now.
2. **Day-one ambition:** several roles + formulas + multiple in-flight orders + health.
3. **URLs:** env-var-templated with lago-morph defaults.
4. **Beadstore repo:** dolt remote only, no other content.
5. **Bead-store runtime model:** local managed dolt server (fast), with periodic `dolt push` to the beadstore repo for durability.
