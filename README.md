# machine-debian

A base image for **Apple `container` machines** — long-lived Debian/systemd
Linux VMs on macOS (Apple Silicon). It ships a general development baseline;
each project overlays only its own non-standard tooling and boots a
project-specific machine from the result.

Published as `ghcr.io/mikluko/machine-debian`.

This repo is also a **Claude Code plugin** (and its own marketplace) shipping the
`apple-container` skill — the working knowledge behind this project (see
[Claude plugin](#claude-plugin)).

## Requirements

- macOS on Apple Silicon.
- Apple's `container` CLI, v1.0+ (`container --version`).
- **arm64 only.** The image is built and published for arm64.

## Tags

The base and each overlay are separate GHCR packages. Every build publishes a
moving `latest` tag and an immutable version `EPOCH.BUILD` per package. `BUILD`
is the CI run number; `EPOCH` starts at `0` and is bumped by hand on a breaking
base change. Pin the version for reproducibility.

- base: `ghcr.io/mikluko/machine-debian` — `latest`, `0.<build>`
- kind: `ghcr.io/mikluko/machine-debian/kind` — `latest`, `0.<build>`
- jdk25: `ghcr.io/mikluko/machine-debian/jdk25` — `latest`, `0.<build>`

## Base pinning

`Dockerfile`'s `FROM` tracks a dated Debian snapshot (`debian:trixie-YYYYMMDD`),
not the floating `trixie`. A daily workflow
([`update.yaml`](.github/workflows/update.yaml)) resolves Debian's newest
`trixie-YYYYMMDD` tag, rewrites the pin, and commits only when it changes. That
commit triggers the build, so rebuilds happen only on a new snapshot, not daily.

Setup: the update commits with a PAT so its push triggers the build workflow (a
push made with the default `GITHUB_TOKEN` cannot). Create a fine-grained PAT
with Contents: read/write on this repo and store it as the `UPDATE_WORKFLOW_PAT`
secret.

## What's in the base

- **Init:** systemd as PID 1 (`ENTRYPOINT /sbin/init`), so services run
  normally inside the machine.
- **Languages:** Go, Node.js + npm.
- **Toolchain:** `build-essential`, Git, OpenSSH client, `sudo`,
  `ca-certificates`.

No container runtime is baked into the base. Everything beyond this baseline,
including Docker or Podman, is a per-project or shared overlay (see
[Overlays](#overlays)).

## How it works

1. This repo builds and publishes the base image to
   `ghcr.io/mikluko/machine-debian`.
2. A project defines its own `Dockerfile` with `FROM
   ghcr.io/mikluko/machine-debian` and adds project-specific packages/tools
   (see [Overlays](#overlays)).
3. The project builds that Dockerfile into a local image and creates a
   `container machine` from it. The machine is a persistent VM you `run`
   commands in, `stop`, and `delete`.

A `container machine` boots from an image snapshot. **Rebuilding the image does
not update a running machine** — to pick up changes you rebuild and re-create
the machine (see [Update](#update-a-project-machine)).

## Playbooks

Sizing used below: `--cpus 6 --memory 16G`. Adjust per project.

### Publish / update the base image

Run from this repo. Builds arm64 and pushes to GHCR.

```bash
container registry login ghcr.io            # once; use a GitHub PAT with write:packages
container build -t ghcr.io/mikluko/machine-debian .
container image push ghcr.io/mikluko/machine-debian
```

### Create a project machine

Run from the project directory (the one with the `FROM
ghcr.io/mikluko/machine-debian` Dockerfile). Replace `myproject`.

```bash
container build -t machine-myproject .
container machine create machine-myproject --name myproject --cpus 6 --memory 16G
```

`create` boots the machine. Confirm:

```bash
container machine ls
```

### Enter / run in a machine

```bash
container machine run -n myproject --root                 # interactive root shell
container machine run -n myproject --root -- <cmd> [args] # one-off command
```

`--root` is required for container builds inside the machine (see
[Gotchas](#gotchas)). `run` boots the machine if it is stopped.

### Update a project machine

Machines cannot hot-swap their image, so re-create:

```bash
container build -t machine-myproject .          # rebuild (pull fresh base first if needed)
container machine stop myproject
container machine delete myproject
container machine create machine-myproject --name myproject --cpus 6 --memory 16G
```

To also pick up a newer base image, pull it before rebuilding:

```bash
container image pull ghcr.io/mikluko/machine-debian
```

### Delete a project machine

```bash
container machine stop myproject
container machine delete myproject
container image delete machine-myproject    # optional: drop the local image too
```

## Gotchas

- **Builds must run as root.** `container machine run --root`. As the
  host-matched user, container storage lands on the virtiofs home mount, which
  cannot do the ownership ops overlay needs (`lchown: invalid argument`). As
  root it uses machine-local storage (`/var/lib/docker` for Docker,
  `/var/lib/containers` for Podman).
- **Your host `$HOME` is mounted read-write** into the machine at the same path,
  and `run` defaults its working directory into it. A relative write inside the
  machine can hit your real host files. Build and scratch in machine-local paths
  (`/root`, `/var/tmp`), not under the mounted home.
- **SSH agent forwarding is transparent for 1Password** — its agent socket lives
  under `~/Library/...` (inside the mounted home), so `ssh-add -l` works in the
  machine with no setup. A stock macOS `ssh-agent` socket lives outside `$HOME`
  and would not forward this way.
- **`container machine run` often prints a spurious first line**
  `Error: The operation couldn't be completed. Operation not supported by
  device`. It is harmless; the command still runs.
- **`container machine create` may print an XPC boot timeout** yet boot fine —
  check `container machine ls` before retrying.

## Overlays

Common tool layers ship as named overlay Dockerfiles here. Each is `FROM
ghcr.io/mikluko/machine-debian`, inherits the base init/entrypoint, and CI
publishes it as its own GHCR sub-package (see [Tags](#tags)).

- [`kind.Dockerfile`](kind.Dockerfile) → `ghcr.io/mikluko/machine-debian/kind` —
  `kind` + Podman as its container provider
  (`KIND_EXPERIMENTAL_PROVIDER=podman`).
- [`jdk25.Dockerfile`](jdk25.Dockerfile) → `ghcr.io/mikluko/machine-debian/jdk25`
  — OpenJDK 25 (headless) + Maven (from Debian trixie-security) + Docker Engine.

Create a machine straight from a published overlay, no local build:

```bash
container machine create ghcr.io/mikluko/machine-debian/kind \
  --name myproject --cpus 6 --memory 16G
```

Or build an overlay Dockerfile locally (e.g. to pin a version or tweak it):

```bash
container build -t machine-myproject -f kind.Dockerfile .
container machine create machine-myproject --name myproject --cpus 6 --memory 16G
```

A project needing several overlays composes them in its own Dockerfile: start
`FROM ghcr.io/mikluko/machine-debian` and copy in the `RUN` blocks it wants
(a single base per image, so overlays are combined by hand, not chained).

## Claude plugin

The repo doubles as a Claude Code plugin (and its own marketplace) that ships
the `apple-container` skill: the accumulated working knowledge of `container
machine` (the gotchas around home mounts, rootless storage, SSH-agent
forwarding, and systemd/Docker inside the VM). Install it:

```
/plugin marketplace add mikluko/machine-debian
/plugin install machine-debian@machine-debian
```

Plugin layout: `.claude-plugin/plugin.json` (manifest),
`.claude-plugin/marketplace.json` (listing), `skills/apple-container/`.
