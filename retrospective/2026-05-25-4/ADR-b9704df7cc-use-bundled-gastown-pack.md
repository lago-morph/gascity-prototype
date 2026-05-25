# ADR: Use the bundled gastown pack rather than authoring a custom pack

- **ID**: ADR-b9704df7cc
- **Status**: Draft (not yet adopted to docs/adr/)
- **Date**: 2026-05-25
- **Source retrospective**: ../2026-05-25-4.md
- **PRs covered**: #2, #3

## Context

The Gas City prototype needs a set of agent roles to demonstrate multi-agent
coordination. Gas City itself is role-agnostic — it provides the
controller, bead store, runtime providers, and pack-composition machinery
but explicitly ships no built-in agent roles. The pack supplies the roles.
The deep-dive docs (`docs/13-gas-city-deep-dive.md` §14) document five
bundled packs that ship inside the `gc` binary, of which `gastown` is the
worked example role taxonomy (mayor coordinator, deacon health-patrol,
boot bootstrap, witness observer, refinery reviewer, polecat worker,
crew named-worker, dog utility-pool).

The user's explicit guidance in this session was "for now use the pack
configuration that mimics gastown." Authoring a custom pack from scratch
would have meant designing role definitions, writing prompt templates,
defining formulas, and authoring orders — a session of work that was
explicitly deferred.

## Decision

Import the gascity-bundled gastown pack via `[imports.gastown]` in
`pack.toml` rather than designing this project's role taxonomy from scratch.

## Alternatives considered

- **Author a custom pack from scratch.** Rejected for this session
  because the user-stated intent was "what does gastown look like
  running" and we did not yet have a product-shaped answer for what
  unique roles this prototype would need. Designing a pack first
  would couple the choice to the prototype's still-undefined demo
  use cases.
- **Import only the `core` pack and add specific gastown roles
  selectively.** Rejected because the gastown pack already structures
  its agents around the mayor/deacon/boot city-scope + witness/
  refinery/polecat per-rig-scope pattern that's exactly what we want
  to demonstrate. Cherry-picking would be a refactor of someone else's
  pack with no upside.
- **Import a third-party pack from a public registry.** Rejected
  because no equivalent third-party pack exists at the time of
  writing, and the bundled gastown pack resolves in-process from the
  embedded FS in the `gc` binary (no network round-trip on import),
  which is faster and more reliable than fetching from a registry.

## Consequences

- Easier: zero pack authoring up front. The prototype goes from
  empty repo to a 6-agent fleet in one Dockerfile build.
- Easier: any role-level fixes in upstream gascity (gastown pack)
  flow through automatically on the next `gc` upgrade.
- Harder: the role names visible in `gc status` are gastown-specific
  jargon (mayor, deacon, boot, witness, refinery, polecat, crew, dog)
  rather than generic descriptive names. The README primer in PR #3
  papered over this by using generic terms ("coordinator",
  "health-patrol", "worker pool") but the actual command output still
  shows gastown names.
- Harder: customizing role behavior means writing pack overrides /
  patches rather than editing the source directly. A future
  prototype-specific role would need to live in our own `pack/` dir
  alongside the imported one.
- Accepted trade-off: prototype clarity (zero work) vs. teaching
  clarity (role names are surprising). The README docs the mapping
  but a follow-up could relabel the gastown roles via pack patches if
  the role names become a friction point.

## References

- [`../2026-05-25-4.md`](../2026-05-25-4.md) — the source retrospective.
- `pack/pack.toml` — the file that declares the import.
- `city.toml.example` — the file that declares `[defaults.rig.imports.gastown]`
  for per-rig roles.
- `docs/13-gas-city-deep-dive.md` §14 — reference for what bundled packs exist.
- PRs the decision was made in: #2 (initial wiring), #3 (README primer
  that documents the role-name mapping).
