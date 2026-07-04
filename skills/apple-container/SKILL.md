---
name: apple-container
description: Apple `container` CLI (macOS containerization) - running containers and persistent Linux VMs via `container machine`, building images, and the gotchas around home mounts, rootless storage, SSH agent forwarding, and systemd/Docker inside the VM. Use when working with the `container` command, `container machine`, or the `mikluko/machine-debian` base image and project machines.
allowed-tools: [Read, Write, Edit, Bash]
---

# Apple `container` (macOS containerization)

Apple's `container` CLI (v1.0.0) runs each container/machine inside its own
lightweight VM with an Apple-provided kernel. It is NOT Docker: the process
model, storage, and networking differ. Two distinct models:

- `container run` — short-lived app containers (Docker-like).
- `container machine` — long-lived Linux VMs. Use this for a persistent
  systemd sandbox. See the `mikluko/machine-debian` workflow below.

## container machine

Subcommands: `create delete inspect list logs run set set-default stop`.
There is **no `start`** — boot happens via `create`, or `run` (boots if
needed), or `run -- true` to boot without a foreground command.

```
container machine create <image> --name <n> --cpus N --memory 16G
container machine run -n <n> [--root] [-t -i] [-- cmd ...]   # boots if stopped
container machine set -n <n> cpus=6 memory=16G              # applies after restart
container machine stop <n>
container machine delete <n>
container machine inspect <n>    # JSON; state at "status" : "running"
container machine ls
```

- `create <image>` accepts any OCI image (plain `debian:trixie`, `alpine:3.22`,
  or a locally built tag). Apple wraps it with the VM + boot. The image's CMD
  is honored: `CMD ["/sbin/init"]` makes **systemd PID 1** inside the machine
  (verified: `/proc/1/comm` = `systemd`).
- `set` changes only take effect after `stop` + restart.
- Default `--memory` is half of host RAM; always set it explicitly.

### run: user and env

- Default runs as the **host-matched user** with `$HOME` mounted (see below).
- `--root` runs as root. **Required for builds** (see rootless gotcha).
- No command → interactive login shell (add `-t -i`).
- `-e KEY[=VAL]` passes env; host env like `SSH_AUTH_SOCK` propagates.

## Building images

`container build -t <tag> -f Dockerfile <context>` builds via an internal
buildkit container (visible as `buildkit` in `container ls`; leave it running).
`--mount=type=cache,target=/var/lib/apt` and `/var/cache/apt` cache mounts work
and speed apt rebuilds.

## Gotchas (learned the hard way)

- **Home mount leaks to the host.** `--home-mount` defaults to `rw`: the host
  `$HOME` is mounted into the machine at the *same path*, and `machine run`
  defaults CWD into it. A relative write inside the machine hits your real host
  files (it once clobbered a Dockerfile). **Build in machine-local paths**
  (`/root`, `/var/tmp`), never the home mount. `--home-mount ro|none` hardens it.
- **Machines have no `--mount`/`--volume`/`--ssh`.** Only `--home-mount ro|rw|none`.
  Arbitrary bind mounts and explicit socket forwarding are unavailable.
- **Rootless container builds fail on the home mount.** Rootless podman/buildah
  storage lands on the virtiofs home mount, which lacks the ownership ops overlay
  needs: `lchown /etc/gshadow: invalid argument` / "potentially insufficient
  UIDs". Fix: run builds as `--root` so storage uses machine-local
  `/var/lib/docker` (or `/var/lib/containers`).
- **`machine run` prints a spurious first line** `Error: The operation couldn't
  be completed. Operation not supported by device` — harmless; the command still
  runs. Filter with `grep -vE 'Operation not supported'`.
- **`machine create` may print an XPC timeout** (`XPC timeout ... bootMachine`)
  yet the machine boots fine. Re-check with `machine ls` before retrying.
- **`ls -q` lists names** (a named container's ID equals its `--name`).
  `--format '{{.Names}}'` does NOT work: this CLI only formats
  json/table/yaml/toml.

## SSH agent forwarding

Works **transparently for 1Password** because its agent socket lives under
`~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock` — inside the
home mount — and Apple's virtiofs proxies the AF_UNIX connection. `ssh-add -l`
inside the machine lists host keys with no setup.

Caveat: a stock macOS `ssh-agent` socket lives in `/private/tmp/...` (outside
`$HOME`), so it would NOT be visible through the home mount. Transparent
forwarding here is specific to 1Password's socket location.

## systemd and Docker inside the machine

Because systemd is PID 1, system services work normally:

- Install `docker.io docker-buildx iptables` and `systemctl enable docker` in
  the image → `dockerd` auto-starts on boot (`systemctl is-active docker` =
  `active`).
- `docker build` works, including network `RUN` steps (apt over the network) —
  the Apple kernel has bridge/iptables/NAT.
- (Standalone `container run` with systemd-as-PID1 additionally needs
  `--cap-add ALL -e container=docker`, else systemd aborts with "Failed to mount
  API filesystems" when it can't mount the `/run` tmpfs. `container machine`
  handles this itself — no caps needed.)

## mikluko/machine-debian

The workflow is a **base image + per-project overlays**, not a wrapper script
(the old `crucible.sh` was removed). `~/Forge/mikluko/machine-debian` builds a
base published to `ghcr.io/mikluko/machine-debian`: Debian trixie + systemd,
Go, Node, git, and the C toolchain. No container runtime in the base. Anything
beyond that baseline is an overlay Dockerfile in the repo (`kind.Dockerfile` =
kind + Podman, `jdk25.Dockerfile` = JDK 25 + Maven + Docker, ...), built with
`-f`, each `FROM` the base.

Projects add a `Dockerfile` `FROM ghcr.io/mikluko/machine-debian`, build it to a
local tag, and `container machine create <tag> --name <project> --cpus 6
--memory 16G`. Lifecycle playbooks (create/enter/update/delete, base publish)
live in that repo's `README.md`. Machines can't hot-swap their image — rebuild
then re-create to pick up changes.
