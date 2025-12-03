FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ipset \
    iptables \
    fail2ban \
    curl \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Copy scripts and configs
COPY scripts/update-blocklist.sh /usr/local/bin/update-blocklist.sh
COPY fail2ban/filter.d/traefik-probe.conf /etc/fail2ban/filter.d/traefik-probe.conf
COPY fail2ban/jail.d/defaults.conf /etc/fail2ban/jail.d/defaults.conf
COPY fail2ban/jail.d/traefik.conf /etc/fail2ban/jail.d/traefik.conf
COPY scripts/entrypoint.sh /entrypoint.sh

RUN chmod +x /usr/local/bin/update-blocklist.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
