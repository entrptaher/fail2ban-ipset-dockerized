# Bot Protection (Docker)

Two-layer defense system:
1. **Global IP Blocklist** - Blocks ~50,000 known malicious IPs from threat intelligence feeds
2. **Fail2ban** - Bans IPs in real-time when they probe for vulnerabilities

## Quick Start

```bash
# 1. Edit docker-compose.yml to set your traefik log path
#    Default: /etc/dokploy/traefik/dynamic/access.log

# 2. Start
docker compose up -d --build

# 3. Check logs
docker logs -f bot-protection
```

## Requirements

- Docker with `privileged: true` support
- Traefik access log in JSON format

## Configuration

Edit `docker-compose.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `BORESTAD_PERIOD` | `14d` | Blocklist age: 1d, 3d, 7d, 14d, 30d, 60d, 90d, 120d |
| `TRAEFIK_ACCESS_LOG` | `/etc/dokploy/traefik/dynamic/access.log` | Path to traefik access.log |

## Commands

```bash
# Check status
docker exec bot-protection fail2ban-client status traefik-probe

# Check blocklist count
docker exec bot-protection ipset list global-blocklist | grep -c "^[0-9]"

# Force blocklist update
docker exec bot-protection /usr/local/bin/update-blocklist.sh

# Unban an IP
docker exec bot-protection fail2ban-client set traefik-probe unbanip 1.2.3.4

# View banned IPs
docker exec bot-protection fail2ban-client status traefik-probe
```

## What Gets Blocked

### Blocklist (proactive)
- IPs with 100% abuse confidence from AbuseIPDB
- SSH attackers from Blocklist.de
- Compromised IPs from Emerging Threats
- Known bad actors from CI Army, GreenSnow, BinaryDefense

### Fail2ban (reactive)
Bans IPs on first probe for:
- `.env`, `.git`, `.htaccess` files
- Admin panels: phpMyAdmin, wp-admin, adminer
- Backup files: `.sql`, `.bak`, `.backup`
- CMS exploits: xmlrpc.php, wp-content

## How It Works

1. Container starts with `privileged: true` to access host iptables
2. Downloads blocklists and adds IPs to `ipset` (host-level)
3. Creates iptables rules in INPUT and DOCKER-USER chains
4. Fail2ban monitors traefik logs and adds bans to iptables
5. Background loop updates blocklists every 6 hours

**Important**: The iptables rules persist on the host even if the container stops.

## Logs

All logs viewable via `docker logs -f bot-protection`
