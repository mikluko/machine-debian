# kind (Kubernetes-in-Docker) + Podman overlay on the base machine image.
#
# Build:  container build -t machine-<name> -f kind.Dockerfile .
#
# Podman is kind's container provider here (KIND_EXPERIMENTAL_PROVIDER=podman),
# so no Docker daemon is required.
# ENTRYPOINT (/sbin/init) and STOPSIGNAL are inherited from the base.

FROM ghcr.io/mikluko/machine-debian

ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update -yq && \
    apt-get install -y \
        podman buildah crun \
        netavark aardvark-dns fuse-overlayfs uidmap slirp4netns

ENV GOBIN=/usr/local/bin
RUN --mount=type=cache,target=/root/.cache \
    go install sigs.k8s.io/kind@v0.32.0 && \
    kind --version

ENV KIND_EXPERIMENTAL_PROVIDER=podman
