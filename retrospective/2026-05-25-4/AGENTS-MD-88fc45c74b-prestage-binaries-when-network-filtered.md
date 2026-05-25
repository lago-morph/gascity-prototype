# agent instruction

**Pre-stage binaries on the host when container builds can't reach release URLs.** Before adding a `RUN curl … releases/download/…` step to a Dockerfile, test the same URL from inside a throwaway `ubuntu:24.04` container against the same network policy that will run the real build. If it fails (TLS inspection, allow-list, 000), download the asset on the host into a `build-context/` directory and `COPY` it into the image instead.

*Grounded in: container-side `curl` to github.com/dolthub/dolt/releases/latest/download failed with self-signed-certificate even though the host could fetch the same URL.*

# justification

The Anthropic sandbox (and many corporate networks) terminates outbound TLS in a proxy that signs with its own CA. The host trusts that CA via `/etc/ssl/certs/ca-certificates.crt`, but a vanilla `ubuntu:24.04` container inside the same network doesn't — so `curl https://github.com/.../releases/download/...` fails with `self-signed certificate` even though the host can fetch the same URL. The first three Dockerfile build attempts in this session all crashed at this step (dolt, then bd, then attempts to npm-install claude-code) before generalizing to "stage on host, COPY into image." Each failed cycle cost ~3 minutes. Probing the network policy in a `docker run --rm ubuntu:24.04` once at the start costs ~30 s and turns the next attempt's hidden failure into an explicit decision.
