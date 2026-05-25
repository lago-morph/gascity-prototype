FROM ubuntu:24.04

# Runtime dependencies. Everything gascity + dolt + claude need at runtime
# is installed here. Binaries that don't ship via apt (dolt, gc, claude CLI, node)
# are COPYed in from the build context, pre-staged by the host.
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      tmux git jq lsof procps util-linux \
      ca-certificates openssh-client curl \
      gettext-base \
 && rm -rf /var/lib/apt/lists/*

# Dolt — for the bd-backed beads provider. Pre-staged tarball avoids the sandbox's
# TLS-inspection proxy blocking GitHub release downloads at build time.
COPY dolt-linux-amd64.tar.gz /tmp/dolt.tar.gz
RUN tar -xzf /tmp/dolt.tar.gz -C /opt \
 && ln -s /opt/dolt-linux-amd64/bin/dolt /usr/local/bin/dolt \
 && rm /tmp/dolt.tar.gz \
 && dolt config --global --add user.email gascity-prototype@example.com \
 && dolt config --global --add user.name "Gas City Prototype" \
 && dolt version

# gc — pre-built on the host using Go 1.25. Single static-ish binary.
COPY gc /usr/local/bin/gc
RUN chmod +x /usr/local/bin/gc && gc version

# bd — the Beads CLI. Required by the bd beads provider (gc shells out to it).
COPY bd /usr/local/bin/bd
RUN chmod +x /usr/local/bin/bd && bd version

# Node + Claude Code CLI. COPYed wholesale from the host's /opt to avoid npm install.
# Anywhere they originally referenced /opt/node22 and /opt/claude-code they
# continue to work because we mount them at the same paths.
COPY node22 /opt/node22
COPY claude-code /opt/claude-code
RUN ln -sf /opt/claude-code/bin/claude /opt/node22/bin/claude

# Pre-complete the first-run onboarding wizards so interactive `claude` (which
# is what gascity launches under each agent's tmux session) skips:
#   1. the theme picker             (hasCompletedOnboarding / hasSeenWelcome / theme)
#   2. the "trust this folder" gate (projects[path].hasTrustDialogAccepted)
#   3. the bypass-permissions gate  (bypassPermissionsModeAccepted)
# Without all three, agent claude hangs on a dialog forever and gc's start_call
# times out (64s) over and over.
#
# We don't list workspace paths here because they aren't bind-mounted at build
# time; entrypoint.sh re-renders this file at startup with the actual paths.
RUN mkdir -p /root/.claude \
 && cat > /root/.claude.json <<'JSON'
{
  "firstStartTime": "2026-01-01T00:00:00.000Z",
  "hasCompletedOnboarding": true,
  "hasSeenWelcome": true,
  "theme": "dark",
  "bypassPermissionsModeAccepted": true
}
JSON

ENV PATH="/opt/node22/bin:/usr/local/bin:/usr/bin:/bin"

# Workspace layout. All mutable state (rigs, beadstore, .gc, .beads) lives under
# /workspace, which is volume-mounted so it survives `docker compose restart` but
# not `docker rm`. After docker rm, the entrypoint re-clones from the GitHub repos.
RUN mkdir -p /workspace/city /workspace/rigs /workspace/beadstore /pack

# Pack content (pack.toml, prompts, formulas) is baked into /pack for the
# demo path. Bind-mount this directory in compose for live-edit development.
COPY pack /pack

# city.toml template gets envsubst'd at entrypoint into /workspace/city/city.toml.
COPY city.toml.example /pack/city.toml.example

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Tuning to keep large pushes (dolt) from tripping default HTTP buffers.
RUN git config --system http.postBuffer 524288000 \
 && git config --system http.lowSpeedLimit 0 \
 && git config --system http.lowSpeedTime 999999

WORKDIR /workspace/city
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
