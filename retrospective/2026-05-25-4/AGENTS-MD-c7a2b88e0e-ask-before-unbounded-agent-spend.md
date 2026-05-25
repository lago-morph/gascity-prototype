# agent instruction

**Ask before letting a multi-agent fleet run unbounded inside a container.** Before you let the city's reconciler spin up always-on agent processes that consume tokens per tick, surface the cost shape to the user (which agents, what they poll, expected per-hour token spend) and confirm. The agents-as-product-managers model says the agent owns cost discipline; standing up 6 always-on claude sessions without confirmation is a violation of that contract.

*Grounded in: 6 named gastown agents (mayor, deacon, boot, 3 control-dispatchers) came live during smoke-test phase without an explicit cost check; only stopped because the agent self-caught and asked retroactively.*

# justification

The Gas City prototype's `gastown` pack defines 6 always-on agents (mayor, deacon, boot, plus 3 control-dispatchers) and a dog pool that scales on demand. Each always-on agent runs as its own `claude` process, polling for work — every reconciler tick the controller wakes a sleeping agent costs API tokens, and the always-on contract means those agents stay alive for hours unless the controller is stopped. In this session I let the full fleet come live during smoke-test verification without surfacing the cost shape first; I caught it within a minute and brought the container down, but the right pattern is "surface, ask, then proceed." The handoff doc (§4.5) explicitly assigned cost discipline to the operating agent. Cost of the rule: one extra confirmation question before bringing a multi-agent fleet live. Cost of skipping: an unbounded token burn that the user only sees on their next billing line.
