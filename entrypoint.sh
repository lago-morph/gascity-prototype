#!/usr/bin/env bash
# Gas City prototype entrypoint. Runs as PID 1 in the container.
#
# Flow:
#   1. Render city.toml from the template + env vars.
#   2. Clone each rig from its GitHub URL if not already cloned.
#   3. Clone the dolt bead store from its GitHub URL if not already cloned.
#   4. Register the rigs with gc (idempotent).
#   5. exec gc start --foreground.

set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*"; }

: "${RIG1_URL:?RIG1_URL must be set (see .env.example)}"
: "${RIG2_URL:?RIG2_URL must be set (see .env.example)}"
: "${BEADSTORE_URL:?BEADSTORE_URL must be set (see .env.example)}"

# Branches to track on each remote. On the sandbox we develop on a feature
# branch; on the laptop main is fine. Override per-repo via env.
RIG1_BRANCH="${RIG1_BRANCH:-main}"
RIG2_BRANCH="${RIG2_BRANCH:-main}"
BEADSTORE_BRANCH="${BEADSTORE_BRANCH:-main}"

# Dolt git-remote ref. The sandbox's git proxy only allows refs/heads/*, so we
# can't use dolt's default refs/dolt/data. On the laptop either works; pin the
# branch namespace here so both environments behave identically.
DOLT_REF="${DOLT_REF:-refs/heads/dolt-data}"

WORKSPACE="${WORKSPACE:-/workspace}"
CITY_DIR="${WORKSPACE}/city"
RIGS_DIR="${WORKSPACE}/rigs"
BEADSTORE_DIR="${WORKSPACE}/beadstore"

mkdir -p "$CITY_DIR" "$RIGS_DIR" "$BEADSTORE_DIR"

# ---------- 1. render city.toml ----------
# Per-path claude trust + bypass-permissions acks, so the interactive claude
# sessions gc spawns don't hang on dialogs. Image baked the global flags; the
# per-path entries land here because they depend on entrypoint-known paths.
log "stamping claude per-path trust acks"
cat > /root/.claude.json <<JEOF
{
  "firstStartTime": "2026-01-01T00:00:00.000Z",
  "hasCompletedOnboarding": true,
  "hasSeenWelcome": true,
  "theme": "dark",
  "bypassPermissionsModeAccepted": true,
  "projects": {
    "${CITY_DIR}": {"hasTrustDialogAccepted": true, "bypassPermissionsModeAccepted": true},
    "${RIGS_DIR}/rig1": {"hasTrustDialogAccepted": true, "bypassPermissionsModeAccepted": true},
    "${RIGS_DIR}/rig2": {"hasTrustDialogAccepted": true, "bypassPermissionsModeAccepted": true}
  }
}
JEOF

log "rendering city.toml from template"
export RIG1_URL RIG2_URL BEADSTORE_URL
envsubst < /pack/city.toml.example > "${CITY_DIR}/city.toml"
# pack.toml lives alongside city.toml; copy it in (gc looks for it next to city.toml)
cp /pack/pack.toml "${CITY_DIR}/pack.toml"

# .gc/site.toml carries machine-local rig path bindings (gc >=1.0 requires
# rig.path to live here, not in city.toml). The entrypoint owns this binding
# because it owns the on-disk layout under /workspace/rigs/.
mkdir -p "${CITY_DIR}/.gc"
cat > "${CITY_DIR}/.gc/site.toml" <<EOF
workspace_name = "gascity-prototype"

[[rig]]
name = "rig1"
path = "${RIGS_DIR}/rig1"

[[rig]]
name = "rig2"
path = "${RIGS_DIR}/rig2"
EOF
# Pack subdirectories (prompts, formulas, agents) are referenced from pack.toml
# via relative paths; symlink them next to city.toml.
for sub in prompts formulas agents; do
  if [ -d "/pack/${sub}" ] && [ ! -e "${CITY_DIR}/${sub}" ]; then
    ln -s "/pack/${sub}" "${CITY_DIR}/${sub}"
  fi
done

# ---------- 2. clone rigs ----------
clone_rig() {
  local name=$1 url=$2 branch=$3
  local dest="${RIGS_DIR}/${name}"
  if [ -d "${dest}/.git" ]; then
    log "rig ${name}: already present, fetching"
    git -C "$dest" fetch --quiet origin "$branch" || log "  fetch failed (continuing)"
  else
    log "rig ${name}: cloning from ${url} (branch ${branch})"
    git clone --quiet --branch "$branch" "$url" "$dest"
  fi
}
clone_rig rig1 "$RIG1_URL" "$RIG1_BRANCH"
clone_rig rig2 "$RIG2_URL" "$RIG2_BRANCH"

# ---------- 3. clone bead store ----------
# A dolt-managed repo. .dolt/ presence is the marker that we already have data.
if [ -d "${BEADSTORE_DIR}/.dolt" ]; then
  log "beadstore: already present"
  # Optional periodic refresh — disabled by default; the running dolt server
  # owns the local copy during a session.
else
  log "beadstore: cloning from ${BEADSTORE_URL} (ref ${DOLT_REF})"
  # Try git-remote-style clone. If the remote has no dolt data yet (first run),
  # initialize an empty dolt DB and register the remote so a later push populates it.
  if ! dolt clone --ref "$DOLT_REF" "$BEADSTORE_URL" "$BEADSTORE_DIR" 2>/tmp/dolt-clone.log; then
    if grep -qE 'contains no Dolt data|no such ref|could not find' /tmp/dolt-clone.log; then
      log "beadstore: remote has no dolt data yet, initializing empty"
      rm -rf "$BEADSTORE_DIR"
      mkdir -p "$BEADSTORE_DIR"
      ( cd "$BEADSTORE_DIR" \
        && dolt init --fun=false \
        && dolt remote add --ref "$DOLT_REF" origin "$BEADSTORE_URL" )
    else
      log "beadstore: dolt clone failed unexpectedly:"
      cat /tmp/dolt-clone.log
      exit 1
    fi
  fi
fi

# ---------- 4. register rigs with gc ----------
cd "$CITY_DIR"

register_rig() {
  local name=$1
  local path="${RIGS_DIR}/${name}"
  if gc rig list 2>/dev/null | grep -q "^${name}\b"; then
    log "rig ${name}: already registered"
  else
    log "rig ${name}: registering"
    gc rig add "$path" --name "$name" || log "  registration failed (continuing — will retry under controller)"
  fi
}
# gc rig add requires the controller to be queryable. For first-run flow, this
# may need to happen after `gc start`; some versions of gc accept it pre-start.
# We try here and silently move on if it doesn't take — `gc start` itself will
# pick up rigs declared in city.toml.

# ---------- 5. install pack imports (idempotent) ----------
# Bundled gastown/maintenance packs are embedded in the gc binary, but gc still
# requires packs.lock + materialized imports under .gc/imports/ before start.
if [ ! -f "${CITY_DIR}/packs.lock" ]; then
  log "installing pack imports"
  gc import install 2>&1 | sed 's/^/[gc import] /' || {
    log "gc import install failed"
    exit 1
  }
fi

# ---------- 6. exec gc start ----------
log "starting controller (foreground)"
exec gc start --foreground
