# agent instruction

**Verify high-risk integrations before writing the Dockerfile.** Before authoring a multi-component Dockerfile, list the 2–4 highest-risk integrations (auth tokens through proxies, custom git remotes, sub-process launching) and verify each with a one-shot `docker run --rm` test. Each verification takes 5–10 minutes; each unverified blocker found at build time takes a full rebuild cycle plus diagnostic time.

*Grounded in: the three risk verifications at session start (sandbox proxy reach from container, dolt push through proxy, claude in tmux in container) caught two workarounds (--ref refs/heads/dolt-data, CA bundle bind-mount) that would have presented as opaque build-time failures.*

See also the related skill spec at `./SKILL-SPEC-f24491a177-verify-three-risks-before-dockerizing-a-stack.md`, which codifies the workflow (which 2–4 risks to pick, how to verify each, what to do with the result).

# justification

In this session, the three risk verifications at session start (probe the sandbox git proxy from inside a container, push dolt to a github repo through the proxy, run claude inside tmux inside a container) cost ~30 min total and caught two workarounds that would have presented as opaque build-time failures: `dolt push` 403'd against the proxy's `refs/heads/*` allowlist, and `claude` rejected the proxy's TLS-inspection cert without `NODE_EXTRA_CA_CERTS` + a mounted CA bundle. Both were caught before any Dockerfile existed. The image's first build attempt then succeeded modulo a missing bd binary, which was a class of issue we did NOT risk-verify (a missing required binary, separately from network connectivity). Front-loading the network-related risks saved several hours of build-loop diagnostics; the lesson is "always do this," not "do it only when something feels risky."
