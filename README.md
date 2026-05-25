# Gas City prototype

A Dockerized [Gas City](https://github.com/gastownhall/gascity) deployment that
runs the bundled `gastown` role pack (mayor / deacon / boot / witness /
refinery / polecat / crew / dog) across two demo rigs, with the bead store
durably backed up to a separate GitHub repo via Dolt's git-remote support.

## Topology

Four GitHub repos, each on branch `claude/great-pascal-RUfkN`:

| Repo | Role |
|---|---|
| `lago-morph/gascity-prototype` (this one) | Dockerfile, compose, pack, city template, entrypoint, docs |
| `lago-morph/gascity-proto-rig1` | Demo rig #1 |
| `lago-morph/gascity-proto-rig2` | Demo rig #2 |
| `lago-morph/gascity-proto-beadstore` | Dolt git-remote target for the bead store |

## Run on your laptop

You'll need: docker, an `ANTHROPIC_API_KEY`.

```bash
git clone https://github.com/lago-morph/gascity-prototype.git
cd gascity-prototype
cp .env.example .env
# edit .env: set ANTHROPIC_API_KEY=sk-ant-...; rig/beadstore URLs default to lago-morph
docker compose up -d
docker compose logs -f city           # watch the controller boot up
docker exec gascity-prototype gc status   # see all agents and rigs
```

To peek at the mayor's session output:

```bash
docker exec gascity-prototype tmux -L gascity-prototype capture-pane -t gastown__mayor -p
```

To issue work to a rig:

```bash
docker exec gascity-prototype bash -lc 'cd /workspace/rigs/rig1 && bd create "..."'
```

Container dies / you `docker rm`? Just `docker compose up -d` again. Rigs and
bead store re-clone from GitHub; the dolt server picks up where it left off.

## Run inside the Anthropic sandbox

The sandbox needs three things that the laptop doesn't:

- `--network=host` so the container can reach the sandbox's local git proxy.
- The sandbox CA bundle bind-mounted so Node trusts the TLS-inspection cert.
- Auth via `CLAUDE_CODE_OAUTH_TOKEN` (read from
  `/home/claude/.claude/remote/.oauth_token`) plus `ANTHROPIC_BASE_URL`,
  rather than `ANTHROPIC_API_KEY`.

The `docker-compose.sandbox.yml` overlay handles all three. Build a sandbox
`.env` (gitignored) with the proxy-rewritten URLs and the sandbox env vars,
then bring up the stack with both compose files layered:

```bash
# .env (sandbox-flavor)
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

### Bead store durability

The bead store runs as a local Dolt SQL server inside the container (fast).
To back it up to the `gascity-proto-beadstore` GitHub repo:

```bash
docker exec gascity-prototype bash -lc 'cd /workspace/beadstore && dolt push origin main'
```

The push uses `--ref refs/heads/dolt-data` (set in `.env` as `DOLT_REF`)
because the sandbox's git proxy only allows pushes to `refs/heads/*`,
not Dolt's default `refs/dolt/data`. Expect ~60-80 s per push for a small DB.

## Repository layout

```
gascity-prototype/
├── Dockerfile               Ubuntu 24.04 + gc + dolt + bd + claude-code
├── docker-compose.yml       Laptop-shaped service definition
├── docker-compose.sandbox.yml   Sandbox overlay (host net, CA mount, OAuth)
├── entrypoint.sh            Renders city.toml, clones rigs/beadstore, gc start
├── .env.example             Template (lago-morph URL defaults)
├── city.toml.example        Templated city config; envsubst'd at startup
├── pack/
│   └── pack.toml            Imports the bundled gastown pack
├── docs/
│   ├── gascity-sandbox.md   Original handoff doc (to be rewritten)
│   ├── 13-gas-city-deep-dive.md
│   └── PLAN.md              Plan + decisions for this build
├── build-context/           gitignored — large binaries staged for Docker COPY
└── workspace/               gitignored — runtime state (rigs, beadstore, .gc)
```

## Building from scratch

The Dockerfile expects pre-staged binaries in the build context (avoids
container-side downloads that the sandbox's TLS-inspection proxy blocks).
On the sandbox host:

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
# claude + node (just copy from the sandbox host)
cp -r /opt/node22 build-context/
cp -r /opt/claude-code build-context/

cp Dockerfile entrypoint.sh city.toml.example build-context/
cp -r pack build-context/
docker build -t gascity-prototype:latest -f build-context/Dockerfile build-context/
```

On the laptop the same flow works without the proxy concern; you can also
pull pre-built dolt + bd directly inside the Dockerfile instead of pre-staging.
