# ADR: Route dolt git-remote traffic to refs/heads/dolt-data instead of dolt's default refs/dolt/data

- **ID**: ADR-9c34f2b612
- **Status**: Draft (not yet adopted to docs/adr/)
- **Date**: 2026-05-25
- **Source retrospective**: ../2026-05-25-4.md
- **PRs covered**: #2

## Context

The Gas City prototype's bead store lives in a Dolt SQL database inside
the container. For durability, we push that database to a regular GitHub
repo (`lago-morph/gascity-proto-beadstore`) using Dolt v1.81.10+'s
git-remote support, which represents the Dolt commit history as a Git ref
inside an ordinary Git repository.

Dolt's default behavior is to write the database to a Git ref under
`refs/dolt/data`. The Anthropic sandbox's local git proxy
(`http://local_proxy@127.0.0.1:<port>/git/<owner>/<repo>`) gates which
refs accept pushes, and rejects anything outside `refs/heads/*` with
HTTP 403. The first `dolt push origin main` from inside the container
failed with `send-pack: unexpected disconnect while reading sideband
packet` until risk-clearance probing revealed the proxy-side rejection
on the non-`refs/heads/` namespace.

Dolt's `--ref` flag (on `dolt remote add` and `dolt clone`) lets the
caller pick which Git ref the Dolt data tree lives at. Setting it to
`refs/heads/dolt-data` puts the data on a regular branch, which the
proxy accepts.

## Decision

Configure the dolt git remote with `--ref refs/heads/dolt-data` instead of
accepting dolt's default `refs/dolt/data`, so the remote works through
git proxies that allow-list only `refs/heads/*`.

## Alternatives considered

- **Use Dolt's default `refs/dolt/data` ref.** Rejected because it
  doesn't work through the sandbox's git proxy (HTTP 403). On a
  laptop with normal egress to `github.com`, either works; pinning
  to `refs/heads/dolt-data` keeps sandbox and laptop behavior
  identical instead of branching the config per environment.
- **Use a DoltHub remote instead of a Git remote.** Rejected
  because the user wants the bead store on GitHub for parity with the
  three other repos in the prototype layout, not on a separate
  DoltHub account.
- **Use `dolt dump` to SQL files and commit those via plain git.**
  Rejected because the data flow is one-way (data in-container is
  authoritative, GitHub is only a backup) and a SQL dump loses dolt's
  branch / commit history. The git-remote approach keeps the dolt
  history intact for `dolt clone --ref` rehydration.

## Consequences

- Easier: a single configuration works in both sandbox and laptop
  environments, no per-environment branching.
- Easier: `dolt clone --ref refs/heads/dolt-data <url> beadstore` is
  the published rehydration command and it works everywhere.
- Harder: anyone landing on the `gascity-proto-beadstore` GitHub
  repo via the web UI sees a `dolt-data` branch with strange contents
  (the dolt history is opaque to a Git viewer). The repo's README
  explains this.
- Accepted trade-off: surface complexity (one extra flag, one
  custom branch name) in exchange for sandbox/laptop parity and a
  clean separation between the repo's "human-readable" `main` branch
  (just a README) and the `dolt-data` branch.

## References

- [`../2026-05-25-4.md`](../2026-05-25-4.md) — the source retrospective.
- `entrypoint.sh` — uses `DOLT_REF=refs/heads/dolt-data` for clone/push.
- `.env.example` — declares `DOLT_REF=refs/heads/dolt-data` as a default.
- `README.md` — documents the `dolt clone --ref` form.
- `docs/PLAN.md` — risk-verification record for the proxy-side rejection.
- PRs the decision was made in: #2.
