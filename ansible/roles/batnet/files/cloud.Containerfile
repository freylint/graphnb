FROM fedora:44

# Install service packages and runtime dependencies.
RUN dnf install -y \
	caddy \
	iproute \
	openssh-server \
	wireguard-tools \
	&& dnf clean all

# Prepare runtime directories and SSH host keys.
RUN mkdir -p /etc/wireguard /etc/caddy /var/run/sshd /var/lib/caddy /var/log && \
	ssh-keygen -A

# Provide a default Caddy configuration.
RUN cat <<'EOF' > /etc/caddy/Caddyfile
:80 {
	respond "fedora44 service container (caddy + ssh + wireguard)" 200
}
EOF

# Provide a WireGuard configuration template. Override with a mounted file in production.
RUN cat <<'EOF' > /etc/wireguard/wg0.conf
[Interface]
# Replace these values before use.
Address = 10.20.0.1/24
ListenPort = 51820
PrivateKey = REPLACE_ME_BASE64_PRIVATE_KEY
SaveConfig = true

# Example peer
#[Peer]
#PublicKey = REPLACE_ME_BASE64_PUBLIC_KEY
#AllowedIPs = 10.20.0.2/32
EOF

# Start SSH, Caddy, and WireGuard if config is populated.
RUN cat <<'EOF' > /usr/local/bin/start-services.sh
#!/usr/bin/env bash
set -euo pipefail

# Start OpenSSH in the background.
/usr/sbin/sshd -D &

# Start WireGuard only if the config looks valid.
if grep -q "REPLACE_ME_BASE64_PRIVATE_KEY" /etc/wireguard/wg0.conf; then
	echo "Skipping WireGuard startup: /etc/wireguard/wg0.conf still has placeholder keys."
else
	wg-quick up wg0 || {
		echo "Failed to start WireGuard interface wg0" >&2
		exit 1
	}
fi

# Keep container in foreground with Caddy.
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
EOF

RUN chmod +x /usr/local/bin/start-services.sh

EXPOSE 22 80 443 51820/udp

CMD ["/usr/local/bin/start-services.sh"]

