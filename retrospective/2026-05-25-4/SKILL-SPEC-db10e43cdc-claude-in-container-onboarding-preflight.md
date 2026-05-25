# Spec: `claude-in-container-onboarding-preflight`

- **ID**: SKILL-SPEC-db10e43cdc
- **Source retrospective**: ../2026-05-25-4.md

## Intent

Interactive `claude` in a container hangs forever on three pre-run
dialogs (theme picker, trust-this-folder, bypass-permissions warning)
that the user can't see and can't dismiss. The fix is to write
`~/.claude.json` with `hasCompletedOnboarding`, `hasSeenWelcome`,
`theme`, `bypassPermissionsModeAccepted`, and per-path
`projects[path].hasTrustDialogAccepted` for every CWD any agent uses.
Bake the global flags into the image; have the entrypoint write the
per-path projects map because it depends on runtime paths.

Without this preflight, any orchestrator (gascity, Beads, a custom
script) that launches `claude` inside a container without `-p`
(print mode) will see the start_call hang at the default 64-second
timeout and the agent will never reach a useful state. The dialogs
are invisible from outside the container's tmux session.

## Trigger

- Direct: "the agent's tmux pane is stuck on a Claude dialog",
  "claude inside the container hangs", "gc start times out on every
  named session".
- Proactive: any time a project plans to launch interactive
  `claude` (not `claude -p`) from inside a Docker container — gascity
  agents, embedded Claude Code sessions, multi-agent orchestrators.
- Negative: not needed for `claude -p` (print mode); print mode
  doesn't show the dialogs.

## Inputs

- The container's root user's home directory (typically `/root/` or a
  named non-root user's home).
- The list of CWDs (working directories) any agent will operate from.
  In gascity this is the city dir + every registered rig's path.
- Whether the image runs as root (needs `IS_SANDBOX=1` for
  `--dangerously-skip-permissions`) or as a non-root user.

## Outputs

- An image with `~/.claude.json` pre-populated with the global flags.
- An entrypoint that writes the per-CWD `projects` map at startup.
- Optionally: a `IS_SANDBOX=1` env entry in compose to allow
  `--dangerously-skip-permissions` while running as root.

## Workflow

1. In the Dockerfile, create `~/.claude/` and write
   `~/.claude.json` with the four global flags:

   ```dockerfile
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
   ```

   `firstStartTime` is required; any plausibly-old timestamp works.
   `theme` is required even though we don't care which — claude
   refuses to start without a theme set.

2. In the entrypoint, append the per-CWD trust map. Build the
   `projects` object dynamically from the known CWDs:

   ```bash
   cat > /root/.claude.json <<EOF
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
   EOF
   ```

3. If the container runs as root (most do), add `IS_SANDBOX=1` to
   the compose environment. Otherwise `claude
   --dangerously-skip-permissions` (used by gascity and many other
   orchestrators) refuses to run with: "cannot be used with root/sudo
   privileges for security reasons."

4. Bring up the stack and verify by `tmux capture-pane`-ing an agent's
   pane. The pane should show the agent's prompt screen ("Welcome
   back!" or the user-prompt template), not any dialog.

5. If a dialog still shows: identify which one (theme picker / trust
   folder / bypass permissions) and check that the corresponding flag
   is present and at the right level (global flag vs per-path
   `projects[path]` entry). Trust-folder must be per-path; the other
   two are global.

## Concrete examples

### Example 1: Gas City — three failing dialogs

Initial pane captures during the prototype build showed three distinct
failure modes across iterations:

1. First the boot pane died with "--dangerously-skip-permissions cannot
   be used with root/sudo privileges for security reasons." Fixed by
   adding `IS_SANDBOX=1` to compose env.
2. Next the deacon pane sat on the theme picker indefinitely. Fixed by
   adding `theme: "dark"`, `hasCompletedOnboarding`, `hasSeenWelcome`
   to `~/.claude.json` (NOT `~/.claude/settings.json` — that file is
   ignored for this purpose).
3. Then the mayor pane sat on "trust this folder". Fixed by adding
   `projects[/workspace/city].hasTrustDialogAccepted: true` (per-CWD).
4. Then a "bypass permissions" warning appeared. Fixed by adding
   `bypassPermissionsModeAccepted: true` globally AND in each
   `projects[path]` entry.

After all four fixes, the next `gc start` produced a fully-active
mayor pane showing "Welcome back! / Opus 4.7 (1M context)" and the
agent began processing.

### Example 2: when the per-path entry is missed

If `projects.<cwd>.hasTrustDialogAccepted` is missing for an agent's
CWD, that agent's pane shows "Quick safety check: Is this a project
you created or one you trust?" and waits for input. The global
`bypassPermissionsModeAccepted` does NOT cover this — trust is per-path
because folder-trust is conceptually scoped to a project.

Mitigation: enumerate every CWD any agent uses (city dir + every rig
path + any cwd referenced from agent.toml's `dir` field) and entry
each one. In gascity, this is the city + every rig.

## Anti-patterns

- **Putting the onboarding flags in `~/.claude/settings.json` instead
  of `~/.claude.json`.** The two files are different. `settings.json`
  is for runtime tool / permission config; `claude.json` is for
  onboarding state. The skill spec spent time trying every flag in
  the wrong file before discovering the actual location.
- **Using only the global `bypassPermissionsModeAccepted` without
  per-path `projects[path]` entries.** Trust is per-CWD; global
  bypass doesn't cover the trust dialog. You'll see the prompt for
  the specific path the agent is operating in.
- **Forgetting `firstStartTime`.** Even though the value doesn't
  matter, the field's presence is what tells claude this isn't a
  first run.
- **Forgetting `IS_SANDBOX=1` while running as root.** Even if every
  onboarding flag is set, claude refuses
  `--dangerously-skip-permissions` from root unless `IS_SANDBOX=1` is
  in env. The "right" fix is to run as non-root, but in a stack with
  many volume mounts that's a separate larger change.

## Acceptance criteria

- [ ] An interactive `tmux capture-pane` of any agent's pane shows the
      agent's working prompt, not a dialog screen.
- [ ] `gc session list` (or equivalent) shows the agent as `active`,
      not stuck in `creating` or `start-pending` for over 60 seconds.
- [ ] Adding a new rig with a new CWD requires only updating the
      entrypoint's `projects` map; no Dockerfile rebuild.
- [ ] Removing `IS_SANDBOX=1` causes the root claude check to fail —
      proving the env var is what's keeping it alive.

## Files this skill creates / modifies

- `Dockerfile` — adds the `RUN mkdir -p /root/.claude && cat > … JSON`
  block for global flags.
- `entrypoint.sh` — adds the per-path `projects` map regeneration on
  every container start.
- `docker-compose.yml` (or its sandbox overlay) — adds `IS_SANDBOX=1`
  to the service environment.
- `~/.claude.json` (inside the container) — the file that holds all
  the flags.
