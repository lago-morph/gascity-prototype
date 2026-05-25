# Gas City prototype

A Dockerized [Gas City](https://github.com/gastownhall/gascity) deployment you
can stand up on a laptop with one `docker compose up`. It runs a small fleet
of cooperating AI coding agents that pick up work from a shared task store,
coordinate through a supervisor agent, and operate on two demo project
repositories ("rigs"). Bead state — the persistent record of all work the
city has done — is backed up to a separate GitHub repo so you can throw the
container away and recover with a fresh one.

This repo is meant as a hands-on first-look at what Gas City actually does
without making you build it from scratch. The hard parts (Go toolchain,
dolt, `bd`, the controller, the agent prompts) are baked into the image.
You bring an Anthropic API key and an interest in watching agents argue
with each other.

## The four-repo layout

| Repo | Role |
|---|---|
| **[`gascity-prototype`](https://github.com/lago-morph/gascity-prototype)** (this one) | The deliverable: Dockerfile, compose files, agent pack, city config template, entrypoint, and these docs. |
| **[`gascity-proto-rig1`](https://github.com/lago-morph/gascity-proto-rig1)** | Demo rig #1 — an ordinary git repo that the city registers as a project for agents to work on. |
| **[`gascity-proto-rig2`](https://github.com/lago-morph/gascity-proto-rig2)** | Demo rig #2 — same idea, second concurrent project. |
| **[`gascity-proto-beadstore`](https://github.com/lago-morph/gascity-proto-beadstore)** | Dolt git-remote target. The container periodically pushes its bead-store database here for durability. |

The three sibling repos are intentionally tiny — each has a README that
points back here. You only ever clone _this_ repo to get started; the
container handles fetching the rigs and bead store itself.

## Vocabulary primer

Gas City has its own jargon. The minimum you need to read the diagrams below:

| Term | What it is |
|---|---|
| **City** | One running deployment. Has a config, a set of agents, a set of rigs, and a bead store. |
| **Rig** | A project directory (git repo) the city's agents can do work on. One city can host many rigs concurrently. |
| **Agent** | A long-running Claude session with a specific role, prompt, and scope. The city spawns one process per active agent. |
| **Pack** | A bundle of agent definitions, prompts, formulas, and orders — Gas City itself is role-agnostic; the pack supplies the roles. This prototype uses the bundled `gastown` pack. |
| **Bead** | A unit of work-tracking state — like an issue, but the agents read and write them directly. Stored in a Dolt database. |
| **Controller** | The supervisor process (`gc start`) that watches the desired set of agents and brings them up / restarts them / scales the pools. Erlang/OTP-style. |
| **Order** | A scheduled trigger ("every 5 minutes", "when this bead closes", …) that fires off agent work without a human pushing a button. |

The pack we ship here defines several specific agent roles (a coordinator, a
health-patrol, a bootstrap agent, a per-rig observer, a per-rig reviewer,
worker pools, etc.). The diagrams refer to them generically; their gastown-
specific names live in `pack.toml` and the city status output.

## Physical view — what runs where

```
┌───────────────────────────────────────────────────────────────────────────┐
│  Host machine  (your laptop, or the Anthropic sandbox)                    │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  Docker container  (image: gascity-prototype:latest)                │  │
│  │                                                                     │  │
│  │   PID 1: tini ── PID 7: gc start --foreground (the controller)      │  │
│  │              │                                                      │  │
│  │              ├── dolt sql-server   ← the bead store, local & fast   │  │
│  │              │                                                      │  │
│  │              └── tmux server (-L gascity-prototype)                 │  │
│  │                       │                                             │  │
│  │                       ├── pane: coordinator agent  ← claude process │  │
│  │                       ├── pane: health-patrol agent ← claude        │  │
│  │                       ├── pane: bootstrap agent     ← claude        │  │
│  │                       ├── pane: worker pool member  ← claude (×N)   │  │
│  │                       ├── pane: rig1 observer       ← claude        │  │
│  │                       ├── pane: rig2 observer       ← claude        │  │
│  │                       └── pane: control-dispatchers (city + 2 rigs) │  │
│  │                                                                     │  │
│  │   /workspace/   (bind-mounted from host)                            │  │
│  │     ├── city/         city config + .gc/ runtime state              │  │
│  │     ├── rigs/rig1/    cloned from gascity-proto-rig1                │  │
│  │     ├── rigs/rig2/    cloned from gascity-proto-rig2                │  │
│  │     └── beadstore/    dolt-cloned from gascity-proto-beadstore      │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
│  /etc/ssl/certs/ca-certificates.crt   ← bind-mounted into container       │
│   (sandbox only; the laptop uses the image's own CA bundle)               │
└───────────────────────────────────────────────────────────────────────────┘
                                ▲
                                │  outbound HTTPS
                                ▼
   ┌─────────────────────┐    ┌──────────────────────────┐
   │  api.anthropic.com  │    │  github.com              │
   │  (claude model)     │    │  4 lago-morph/* repos    │
   └─────────────────────┘    └──────────────────────────┘
```

Notes:

- **One container, one tmux server, many panes.** Each agent role gets its
  own tmux pane running an interactive `claude` process. The controller
  watches the panes and restarts dead ones.
- **The bead store is a real database.** Dolt runs a local SQL server inside
  the container; the agents and the controller all read/write through it.
  Periodically the database is `dolt push`ed up to the beadstore repo for
  durability.
- **`docker rm` is safe.** Lose the container and everything inside
  `/workspace/` with it; on next `docker compose up`, the entrypoint
  re-clones the rigs and `dolt clone`s the bead store, and the controller
  picks up where it left off.

## Logical view — what's connected to what

```
                          ┌──────────────────────────┐
                          │   Controller (gc start)  │
                          │   - reconciles desired   │
                          │     vs running agents    │
                          │   - fires due orders     │
                          │   - reaps dead sessions  │
                          └─────────────┬────────────┘
                                        │ spawns / restarts
                                        ▼
              ┌─────────────────────────────────────────────────┐
              │              Agents (claude processes)          │
              │                                                 │
              │   City-scope agents          Per-rig agents     │
              │   ─────────────────          ──────────────     │
              │   coordinator                rig1: observer     │
              │   health-patrol              rig1: reviewer*    │
              │   bootstrap                  rig2: observer     │
              │   worker pool (0..N)         rig2: reviewer*    │
              │                              (* spawned on demand)
              └────────────────┬────────────────────────────────┘
                               │ read / write
                               ▼
                ┌─────────────────────────────────┐
                │   Bead store (Dolt SQL)          │
                │                                  │
                │   beads ─ work items, messages,  │
                │           orders, gates, results │
                │                                  │
                │   prefixes:                      │
                │     gp-…  city-level (HQ)        │
                │     r1-…  rig1 scope             │
                │     r2-…  rig2 scope             │
                └────┬────────────────────┬────────┘
                     │                    │
            scoped operations    periodic durability push
                     │                    │
                     ▼                    ▼
            ┌─────────────┐   ┌─────────────────────────────┐
            │  rig1 repo  │   │  gascity-proto-beadstore    │
            │  rig2 repo  │   │  (refs/heads/dolt-data)     │
            └─────────────┘   └─────────────────────────────┘
```

Notes:

- **Agents talk through beads, not directly.** When the coordinator wants
  the reviewer to look at something, it writes a bead; the reviewer's
  prompt tells it to poll for beads addressed to it.
- **Scope is enforced by bead prefix.** A worker dispatched to rig1 can
  only see and create beads with the `r1-` prefix. The controller and
  the coordinator are the only things with city-wide (`gp-`) visibility.
- **The bead store is the source of truth.** If the controller restarts,
  the in-flight work is still in the beads. If the container restarts,
  the bead store is rehydrated from GitHub.

## Flow view — how a piece of work moves through the system

```
   ┌──────────────────────────────────────────────────────────────────┐
   │  ① You issue an order                                            │
   │     $ docker exec ... bd create "rewrite README in rig1"         │
   │     → bead r1-abc lands in the bead store, status=open           │
   └─────────────────────────────────────┬────────────────────────────┘
                                         │
                                         ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │  ② Coordinator notices                                           │
   │     - polls beads via its tmux prompt                            │
   │     - sees an open bead in rig1's scope, decides to dispatch     │
   │     - calls `gc sling r1-abc` to route it to the worker pool     │
   └─────────────────────────────────────┬────────────────────────────┘
                                         │
                                         ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │  ③ Controller spawns a worker                                    │
   │     - worker pool was at 0 (cost discipline); now scales to 1    │
   │     - new tmux pane, fresh `claude` process, cwd = rig1's dir    │
   │     - bead r1-abc handed off via env var / prompt                │
   └─────────────────────────────────────┬────────────────────────────┘
                                         │
                                         ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │  ④ Worker does the thing                                         │
   │     - reads files in /workspace/rigs/rig1                        │
   │     - edits the README                                           │
   │     - git commits                                                │
   │     - updates bead r1-abc to status=review, posts result         │
   └─────────────────────────────────────┬────────────────────────────┘
                                         │
                                         ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │  ⑤ Reviewer agent picks it up (optional)                         │
   │     - rig1's per-rig reviewer is scaled to 1 by demand           │
   │     - reads the diff, leaves a verdict on the bead               │
   │     - closes the bead or sends it back for another iteration     │
   └─────────────────────────────────────┬────────────────────────────┘
                                         │
                                         ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │  ⑥ Health-patrol agent keeps house                               │
   │     - reaps closed beads past their TTL                          │
   │     - notices the worker pool is idle, scales it back to 0       │
   │     - logs the lifecycle into the event stream                   │
   └─────────────────────────────────────┬────────────────────────────┘
                                         │
                                         ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │  ⑦ Durability                                                    │
   │     - periodically: dolt push origin main                        │
   │     - new bead-store state lands on the `dolt-data` branch       │
   │       of gascity-proto-beadstore on GitHub                       │
   └──────────────────────────────────────────────────────────────────┘
```

Everywhere this happens without you typing anything except step ①. The
coordinator, the worker, and the reviewer are all independent `claude`
processes coordinating through beads.

## Demo rigs

`gascity-proto-rig1` and `gascity-proto-rig2` are deliberately empty right
now — just a README each. The intention is that each rig will hold a
different small project so you can see the city fan out concurrent work
across both. What those projects are is a product-shaped decision left
for a follow-up session.

You can also point the environment at your own forks; see
[`.env.example`](.env.example) for `RIG1_URL` / `RIG2_URL` / `BEADSTORE_URL`.
Anything resolvable as a git URL works.

## Bead store

`gascity-proto-beadstore` is a normal-looking GitHub repo, but its real
content lives on the `refs/heads/dolt-data` branch as a Dolt-formatted
data ref. Plain `git clone` won't help you read it; use:

```bash
dolt clone --ref refs/heads/dolt-data \
  https://github.com/lago-morph/gascity-proto-beadstore.git
```

The container does this for you automatically on startup. The
`refs/heads/dolt-data` placement (instead of dolt's default
`refs/dolt/data`) is because the Anthropic sandbox's git proxy only
allows pushes to `refs/heads/*`; specifying it explicitly keeps the
sandbox and laptop behaving identically.

## Run on a laptop

You need: Docker, an Anthropic API key.

```bash
git clone https://github.com/lago-morph/gascity-prototype.git
cd gascity-prototype
cp .env.example .env
# edit .env: set ANTHROPIC_API_KEY=sk-ant-…
# (rig and beadstore URLs default to lago-morph/* and are fine as-is unless
#  you've forked them)
docker compose up -d
docker compose logs -f city               # watch the controller boot
docker exec gascity-prototype gc status   # see the agent fleet
```

To peek at what an agent is doing:

```bash
docker exec gascity-prototype \
  tmux -L gascity-prototype capture-pane -t <session-name> -p
```

Session names show up in `gc session list`.

To give the city work:

```bash
docker exec gascity-prototype bash -lc \
  'cd /workspace/rigs/rig1 && bd create "your task here"'
```

Container died? `docker compose up -d` again — the entrypoint re-clones
everything from GitHub and resumes.

## Run inside the Anthropic sandbox

The sandbox needs three things the laptop doesn't:

- `--network=host` so the container can reach the sandbox's local git proxy.
- The sandbox CA bundle bind-mounted so the in-container claude trusts the
  TLS-inspection cert when reaching api.anthropic.com.
- Auth via `CLAUDE_CODE_OAUTH_TOKEN` (read from
  `/home/claude/.claude/remote/.oauth_token`) plus `ANTHROPIC_BASE_URL`,
  instead of `ANTHROPIC_API_KEY`.

`docker-compose.sandbox.yml` is an overlay that adds all three. A
sandbox-flavor `.env` (gitignored) uses proxy URLs and the inherited env:

```bash
ANTHROPIC_API_KEY=
ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL                       # inherited
CLAUDE_CODE_OAUTH_TOKEN=$(cat /home/claude/.claude/remote/.oauth_token)
RIG1_URL=http://local_proxy@127.0.0.1:38985/git/lago-morph/gascity-proto-rig1
RIG2_URL=http://local_proxy@127.0.0.1:38985/git/lago-morph/gascity-proto-rig2
BEADSTORE_URL=http://local_proxy@127.0.0.1:38985/git/lago-morph/gascity-proto-beadstore.git
RIG1_BRANCH=main
RIG2_BRANCH=main
BEADSTORE_BRANCH=main
DOLT_REF=refs/heads/dolt-data
```

```bash
docker compose -f docker-compose.yml -f docker-compose.sandbox.yml up -d
```

To back the bead store up to GitHub:

```bash
docker exec gascity-prototype bash -lc \
  'cd /workspace/beadstore && dolt push origin main'
```

Expect ~60–80 s per push for a small DB.

## Repository layout

```
gascity-prototype/
├── Dockerfile                     Ubuntu 24.04 + gc + dolt + bd + claude
├── docker-compose.yml             Laptop-shaped service definition
├── docker-compose.sandbox.yml     Sandbox overlay (host net, CA mount, OAuth)
├── entrypoint.sh                  Renders city.toml, clones rigs/beadstore, gc start
├── .env.example                   Template (lago-morph URL defaults)
├── city.toml.example              Templated city config; envsubst'd at startup
├── pack/
│   └── pack.toml                  Imports the bundled gastown pack
├── docs/
│   ├── PLAN.md                    Plan + decisions + "things this build had to figure out"
│   ├── gascity-sandbox.md         Original handoff doc (kept for history)
│   └── 13-gas-city-deep-dive.md   Architectural deep-dive reference
├── build-context/                 gitignored — large binaries staged for Docker COPY
└── workspace/                     gitignored — runtime state (rigs, beadstore, .gc)
```

## Building the image from scratch

The Dockerfile expects pre-staged binaries in the build context to avoid
container-side downloads (which the sandbox's TLS-inspection proxy blocks).
On the sandbox host (or anywhere with normal outbound network):

```bash
mkdir -p build-context

# dolt
curl -fsSL -o build-context/dolt-linux-amd64.tar.gz \
  https://github.com/dolthub/dolt/releases/latest/download/dolt-linux-amd64.tar.gz

# bd
curl -fsSL -o /tmp/bd.tgz \
  https://github.com/gastownhall/beads/releases/download/v1.0.4/beads_1.0.4_linux_amd64.tar.gz
tar -xzf /tmp/bd.tgz -C /tmp && cp /tmp/bd build-context/

# gc — build with Go 1.25
curl -fsSL https://go.dev/dl/go1.25.10.linux-amd64.tar.gz | tar -xz -C /tmp/
export PATH=/tmp/go/bin:$PATH
git clone https://github.com/gastownhall/gascity.git /tmp/gascity
(cd /tmp/gascity && make install)
cp ~/go/bin/gc build-context/

# claude + node — copy from your existing Claude Code install
cp -r /opt/node22 build-context/
cp -r /opt/claude-code build-context/

cp Dockerfile entrypoint.sh city.toml.example build-context/
cp -r pack build-context/
docker build -t gascity-prototype:latest -f build-context/Dockerfile build-context/
```

On a laptop without the proxy you can also rewrite the Dockerfile to fetch
dolt and bd directly with `RUN curl …` instead of pre-staging them.

## What's not done yet

- Sample project content in the rigs (rigs are intentionally empty until we
  decide what each should demonstrate).
- A smoke test driven from outside the container that issues an order and
  watches it complete end-to-end.
- The `dolt push` durability step run on a schedule (currently manual).
- `docs/gascity-sandbox.md` is the original handoff doc and refers to the
  obsolete single-repo plan; it's preserved for history but parts of it no
  longer match what got built. `docs/PLAN.md` is the source of truth for
  the design as shipped.
