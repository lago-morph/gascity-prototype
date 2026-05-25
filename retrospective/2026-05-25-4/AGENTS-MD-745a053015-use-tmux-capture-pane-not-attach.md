# agent instruction

**Use `tmux capture-pane` to inspect agent output, not attach.** When inspecting what an in-container agent is doing, run `docker exec <container> tmux -L <socket> capture-pane -t <session> -pS -100`. Don't try to attach to the tmux session — there's no interactive TTY back to the user and an attach inside `docker exec` either fails or hangs the exec shell.

*Grounded in: the gascity skill suggests `gc session attach mayor` to watch an agent; in a container without a live TTY, capture-pane is the only working sampler.*

# justification

Gas City's docs and skill descriptions assume a human operator at a TTY who can `gc session attach mayor` to watch an agent's tmux pane interactively. In a server-style container driven by an outer agent (the layout the prototype uses), there's no TTY back to the user — `gc session attach` either fails immediately or blocks the `docker exec` shell forever waiting for keystrokes that will never come. The right pattern for inspecting agent output is `docker exec <container> tmux -L gascity-prototype capture-pane -t <session> -pS -200` which prints the pane's current contents (including scrollback) to stdout as a one-shot snapshot. This session used capture-pane to diagnose every dialog hang (theme picker, trust folder, bypass-permissions) and to confirm the mayor was thinking. Cost of the rule: a slightly longer command than `gc session attach`. Cost of skipping: a `docker exec` shell stuck waiting for a keystroke, plus a missed diagnostic opportunity (you saw a "active" status but didn't see the dialog screen the pane was actually showing).
