# Podman overlay on the base machine image, serving the Docker-compatible
# Podman API to the host over TCP on port 2375.
#
# Build:  container build -t machine-<name> -f podman.Dockerfile .
#
# A machine publishes no ports and takes a new address on every boot, so a
# host client reaches the API by the machine's name, tcp://<name>.machine:2375,
# which resolves once `container system dns create machine` has run. The home
# mount puts $HOME at the same path inside, so the paths a client bind-mounts
# resolve the same on both sides. The API is unauthenticated and runs as root.
# ENTRYPOINT (/sbin/init) and STOPSIGNAL are inherited from the base.

FROM ghcr.io/mikluko/machine-debian

ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update -yq && \
    apt-get install -y \
        podman crun netavark aardvark-dns fuse-overlayfs

COPY <<EOF /etc/systemd/system/podman-api.service
[Unit]
Description=Podman API over TCP
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/podman system service --time=0 tcp://0.0.0.0:2375
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

RUN systemctl enable podman-api.service

# Podman drops the machine's 127.0.0.1 resolver from a container's
# resolv.conf and substitutes public ones, so containers would resolve around
# unbound. They are pointed at the default network's gateway instead, where
# unbound answers too.
COPY <<'EOF' /etc/unbound/unbound.conf.d/podman.conf
server:
    interface: 0.0.0.0
    interface-automatic: yes
    access-control: 127.0.0.0/8 allow
    access-control: 10.88.0.0/16 allow
EOF

COPY <<'EOF' /etc/containers/containers.conf.d/dns.conf
[containers]
dns_servers = ["10.88.0.1"]
EOF
