FROM debian:trixie-20260623

ARG DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update -yq && \
    apt-get install -y \
        systemd systemd-sysv sudo ca-certificates \
        build-essential git openssh-client \
        golang nodejs npm

STOPSIGNAL SIGRTMIN+3

ENTRYPOINT ["/sbin/init"]
