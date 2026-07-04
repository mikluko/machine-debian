# OpenJDK 25 (headless) + Maven + Docker overlay on the base machine image.
#
# Build:  container build -t <name>-machine -f jdk25.Dockerfile .
#
# JDK 25 comes from Debian trixie-security; no external apt repo needed.
# Docker Engine is enabled as a systemd service and auto-starts on boot.
# ENTRYPOINT (/sbin/init) and STOPSIGNAL are inherited from the base.

FROM ghcr.io/mikluko/machine-debian

ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update -yq && \
    apt-get install -y \
        openjdk-25-jdk-headless maven \
        docker.io docker-buildx docker-compose iptables && \
    systemctl enable docker
