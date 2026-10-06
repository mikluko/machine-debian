FROM debian:trixie-20261005

ARG DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update -yq && \
    apt-get install -y \
        systemd systemd-sysv sudo ca-certificates \
        build-essential git openssh-client \
        golang nodejs npm

# The machine resolves through a local unbound forwarding over DNS-over-TLS,
# not through the vmnet gateway it is handed at boot: the gateway's DNS proxy
# goes silent on some hosts until the container service restarts.
RUN --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update -yq && \
    apt-get install -y unbound

COPY <<'EOF' /etc/unbound/unbound.conf.d/forward-dot.conf
server:
    interface: 127.0.0.1
    tls-cert-bundle: /etc/ssl/certs/ca-certificates.crt

forward-zone:
    name: "."
    forward-tls-upstream: yes
    forward-addr: 1.1.1.1@853#cloudflare-dns.com
    forward-addr: 9.9.9.10@853#dns10.quad9.net
EOF

# The container service rewrites /etc/resolv.conf on every boot.
COPY <<'EOF' /etc/systemd/system/resolv-unbound.service
[Unit]
Description=Point /etc/resolv.conf at the local unbound
After=unbound.service
Requires=unbound.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo nameserver 127.0.0.1 >/etc/resolv.conf'

[Install]
WantedBy=multi-user.target
EOF

RUN systemctl enable unbound.service resolv-unbound.service

STOPSIGNAL SIGRTMIN+3

ENTRYPOINT ["/sbin/init"]
