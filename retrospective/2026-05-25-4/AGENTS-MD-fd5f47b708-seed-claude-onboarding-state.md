# agent instruction

**Pre-seed claude onboarding state when launching claude inside a container.** When `gc` (or any orchestrator) will launch interactive `claude` processes from inside a container, write `~/.claude.json` with `hasCompletedOnboarding: true`, `hasSeenWelcome: true`, `theme: "dark"`, `bypassPermissionsModeAccepted: true`, and per-path `projects[path].hasTrustDialogAccepted: true` for every CWD any agent will use before the controller starts.

*Grounded in: three separate dialogs (theme picker, folder-trust gate, bypass-permissions warning) silently consumed every interactive claude session and timed out every `gc start_call` until the flags were seeded.*

# justification

Interactive claude shows three pre-run dialogs to a first-time user: theme picker, trust-this-folder gate, and a bypass-permissions warning. Each dialog blocks the session until a human dismisses it. Inside a container being driven by a controller, no human is watching the tmux pane — the dialog waits forever and the parent `gc` call times out at 64 s. The reconciler then re-attempts, hits the same dialog, times out again. Without the seeded state, ~5 reconciler cycles passed before the agent (me, on the outside) caught what was happening by `tmux capture-pane`-ing into the agent's pane. Once seeded, every agent reaches its prompt within seconds. The cost of seeding is ~10 lines of JSON written once at image build + once at entrypoint. The cost of not seeding is "the whole stack doesn't work and the failure mode is hidden inside an invisible tmux pane."
