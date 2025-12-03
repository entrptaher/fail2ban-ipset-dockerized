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

## Example Output

```
========================================
   Bot Protection Container Starting
========================================
Traefik log found.
Auth log found.

Loading IP blocklists...
[2025-12-03 07:57:11] ========== Starting blocklist update ==========
[2025-12-03 07:57:11] Downloading blocklists...
[2025-12-03 07:57:11]   Downloading: AbuseIPDB (14d, 100% confidence)
[2025-12-03 07:57:11]     ✓ Success
[2025-12-03 07:57:11]   Downloading: Blocklist.de SSH
[2025-12-03 07:57:12]     ✓ Success
[2025-12-03 07:57:12]   Downloading: Blocklist.de All
[2025-12-03 07:57:12]     ✓ Success
[2025-12-03 07:57:12]   Downloading: Emerging Threats
[2025-12-03 07:57:12]     ✓ Success
[2025-12-03 07:57:12]   Downloading: CI Army
[2025-12-03 07:57:13]     ✓ Success
[2025-12-03 07:57:13]   Downloading: GreenSnow
[2025-12-03 07:57:13]     ✓ Success
[2025-12-03 07:57:13]   Downloading: BinaryDefense
[2025-12-03 07:57:14]     ✓ Success
[2025-12-03 07:57:14] Processing downloaded IPs...
[2025-12-03 07:57:14]   Found 105511 unique IPs
[2025-12-03 07:57:14]   Loading into ipset...
[2025-12-03 07:57:14]   Saved to cache
[2025-12-03 07:57:14]   Done loading IPs
[2025-12-03 07:57:14] Configuring iptables rules...
[2025-12-03 07:57:14]   ✓ INPUT chain rule exists
[2025-12-03 07:57:14]   ✓ DOCKER-USER chain rule exists
[2025-12-03 07:57:14] ========== Update Complete ==========
[2025-12-03 07:57:14] Total IPs blocked: 41750

Starting blocklist update loop (every 6 hours)...

Starting fail2ban...
Server ready

========================================
   Bot Protection Active
========================================

Blocklist IPs: 41750

Fail2ban jails:
Status
|- Number of jail:    2
`- Jail list:    sshd, traefik-probe

========================================
2025-12-03 07:57:15 fail2ban.actions: NOTICE  [sshd] Ban 45.xxx.xxx.124
2025-12-03 07:57:15 fail2ban.actions: WARNING [sshd] 92.xxx.xxx.72 already banned
2025-12-03 07:57:15 fail2ban.actions: NOTICE  [sshd] Ban 92.xxx.xxx.62
2025-12-03 07:57:16 fail2ban.filter:  INFO    [sshd] Found 61.xxx.xxx.69 - 2025-12-03 07:57:16
```

### Checking Jail Status

```bash
$ docker exec bot-protection fail2ban-client status traefik-probe
Status for the jail: traefik-probe
|- Filter
|  |- Currently failed:    0
|  |- Total failed:    0
|  `- File list:    /var/log/traefik/access.log
`- Actions
   |- Currently banned:    0
   |- Total banned:    0
   `- Banned IP list:

$ docker exec bot-protection fail2ban-client status sshd
Status for the jail: sshd
|- Filter
|  |- Currently failed:    15
|  |- Total failed:    281
|  `- File list:    /var/log/auth.log
`- Actions
   |- Currently banned:    16
   |- Total banned:    16
   `- Banned IP list:    61.xxx.xxx.69 92.xxx.xxx.76 92.xxx.xxx.72 ...
```
