# agent instruction

**Bring services down before iterating on their build.** When a rebuild cycle takes minutes and the next change is uncertain, run `docker compose down` first so a partial rebuild can't accidentally restart a stale image. Rebuild-while-running has the same hazard as editing a deployed config: the loop spends tokens on the wrong version while you debug.

*Grounded in: at least two rebuild cycles in this session implicitly kept the previous container running while `docker build` produced a new image; `docker compose up -d` then needed an explicit `down` first or it would no-op.*

# justification

The build/run iteration in this session had two failure modes when I forgot to `down` first: (a) the still-running container with the stale image kept consuming tokens (its claude agents continued polling) while I built the new one, and (b) `docker compose up -d` on the new image is a no-op for an already-running container even with `restart: unless-stopped` — you have to bring it down explicitly to pick up new env vars or volume changes. Two builds in this session needed an extra `compose down` + retry once I noticed the wrong version was running. The marginal cost of an upfront `compose down` is ~1 s; the cost of skipping is "wrong version runs in a loop for minutes plus a re-run to fix."
