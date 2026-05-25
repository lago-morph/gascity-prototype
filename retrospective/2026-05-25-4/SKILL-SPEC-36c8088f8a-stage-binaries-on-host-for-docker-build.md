# Spec: `stage-binaries-on-host-for-docker-build`

- **ID**: SKILL-SPEC-36c8088f8a
- **Source retrospective**: ../2026-05-25-4.md

## Intent

When the build environment (typically a sandbox with a TLS-inspection proxy or
restrictive egress policy) blocks GitHub release downloads and similar HTTPS
fetches from inside containers but allows them from the host, pre-stage
binaries on the host into a build-context directory and have the Dockerfile
COPY them, rather than running `RUN curl …` inside the image build. Saves
multiple rebuild cycles spent diagnosing "self-signed certificate" or
`HTTP 000` errors that look like image-recipe bugs but are network-policy
artifacts.

## Trigger

- Direct: "build a Docker image that needs a tool not on Docker Hub", "the
  Dockerfile build is failing on a curl/wget step", "container can reach
  apt repos but github releases fail".
- Proactive: any time a Dockerfile recipe contains `RUN curl …
  https://github.com/.../releases/download/...` and the build environment
  is the Anthropic sandbox or any environment with documented TLS
  inspection / egress filtering.
- Negative: don't use on a developer laptop with normal outbound network
  unless the team explicitly standardized on pre-staged builds for
  hermetic-build reasons.

## Inputs

- A list of binaries the image needs (URL + filename for each).
- The repo root where the Dockerfile lives.
- Knowledge of which build environment will run `docker build` (host with
  proxy vs developer laptop with open egress).

## Outputs

- A `build-context/` directory at the repo root holding the staged tarballs
  / binaries / on-disk directories.
- A Dockerfile that `COPY`s those artifacts in (no `RUN curl` for them).
- A `.gitignore` entry for `build-context/`.
- A README section documenting where each artifact came from (commands the
  reader can re-run from a host with normal outbound).

## Workflow

1. Identify the binaries the image needs. For each, record canonical URL,
   filename, expected size, and a sha256sum if available.
2. Probe from inside a throwaway container against the target build
   environment's network policy:
   ```bash
   docker run --rm ubuntu:24.04 bash -c \
     'apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null \
      && curl -sSf -L -o /tmp/x https://github.com/.../download.tar.gz \
      && echo OK || echo BLOCKED'
   ```
   - If `OK`: skip this skill; let the Dockerfile fetch at build time.
   - If `BLOCKED`: continue.
3. Confirm the host can reach the same URL: `curl -sI <url> | head -1`.
   If the host is also blocked, the URL is wrong or the user needs to
   provide a different download channel; ask.
4. Create `build-context/` at the repo root if it doesn't exist. Add
   `build-context/` to `.gitignore`.
5. Download each binary into `build-context/`, preserving the original
   filename:
   ```bash
   curl -fsSL -o build-context/dolt-linux-amd64.tar.gz \
     https://github.com/dolthub/dolt/releases/latest/download/dolt-linux-amd64.tar.gz
   ```
6. For binaries that come from elsewhere on the host (e.g., the host's own
   Claude Code installation), `cp -r` the relevant directories into
   `build-context/` (e.g., `cp -r /opt/node22 build-context/`).
7. Write the Dockerfile to `COPY` from the build context. Build the image
   pointing at the build context as the build root:
   ```bash
   docker build -t myimage:latest -f build-context/Dockerfile build-context/
   ```
   (Keeping the Dockerfile copy inside the build-context directory makes
   ad-hoc rebuilds easier; the top-level repo also has the canonical copy.)
8. Add a README section showing the host-side commands to re-stage the
   build context from scratch, so a developer on a normal laptop can
   reproduce.

## Concrete examples

### Example 1: dolt + bd + gc binaries blocked by TLS-inspection proxy

The Gas City prototype needed `dolt`, `bd`, and a custom-built `gc`
binary, none of which are on Docker Hub. Initial attempt put
`RUN curl -fsSL https://github.com/dolthub/dolt/...` in the Dockerfile;
the build failed with:

```
curl failed to verify the legitimacy of the server and therefore could not
establish a secure connection to it.
```

Host curl to the same URL worked. Probing confirmed the sandbox's network
policy intercepts container HTTPS to github.com. Fix: download on the host
into `build-context/`, then `COPY dolt-linux-amd64.tar.gz /tmp/dolt.tar.gz`
in the Dockerfile, then `tar -xzf …`. Resolved the build on the next
iteration.

### Example 2: Claude Code CLI

The image needed a working `claude` binary. claude-code ships from npm,
but `npm install -g @anthropic-ai/claude-code` from inside the container
hit the same TLS-interception block on npm's registry. The host had
`/opt/claude-code/` and `/opt/node22/` directories with the working
install; `cp -r /opt/claude-code build-context/claude-code` and
`cp -r /opt/node22 build-context/node22`, then `COPY claude-code
/opt/claude-code` and `COPY node22 /opt/node22`. Image got 660 MB
fatter but built reliably.

## Anti-patterns

- **Putting a `RUN curl https://github.com/.../releases/...` step in the
  Dockerfile without probing the container-side network first.** The
  failure mode looks like a certificate bug or DNS issue; debugging it
  burns rebuild cycles. The Gas City build hit this on three separate
  binaries (dolt, bd, claude-code) before generalizing the pre-stage
  pattern.
- **Skipping the .gitignore step.** `build-context/` directories often
  hold 100s of MB of binaries; without the gitignore they leak on
  `git add -A`. Add the ignore in the same commit that introduces the
  directory.
- **Pre-staging when the laptop path works fine without it.** A
  Dockerfile that requires `build-context/` to exist makes the laptop
  build harder. Where possible, have the Dockerfile fall back to
  `RUN curl` if the COPY source is absent, or document both flows.
- **Letting the build context get out of date silently.** When the
  upstream binary updates, your staged copy doesn't. Note staged versions
  in a `build-context/VERSIONS.md` or in the README so refreshes are
  obvious.

## Acceptance criteria

- [ ] A fresh clone + the documented host-side staging commands + `docker
      build` produces a working image with no `RUN curl` failing.
- [ ] `git status` after staging shows no large binaries staged for
      commit (only ignored).
- [ ] The README explains both the pre-staged build path (sandbox) and
      a fallback for environments with normal egress (laptop).
- [ ] Each pre-staged artifact's source URL is recoverable from the
      README or a `VERSIONS.md`.

## Files this skill creates / modifies

- `build-context/` — directory holding pre-staged binaries.
- `build-context/<binary>` — each binary at its canonical filename.
- `.gitignore` — adds `build-context/` (or specific subpaths).
- `Dockerfile` — `COPY` statements pointing at `build-context/` paths.
- `README.md` — a "Build from scratch" section with host-side staging commands.
