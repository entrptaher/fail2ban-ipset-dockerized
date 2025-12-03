#!/bin/bash
#
# Global IP Blocklist Updater
# Downloads malicious IPs from trusted threat intelligence feeds
# and blocks them using ipset + iptables
#
# Sources:
#   - AbuseIPDB (100% confidence score IPs)
#   - Blocklist.de (attack reports from honeypots)
#   - Emerging Threats (compromised IPs)
#   - CI Army (malicious traffic detection)
#   - GreenSnow (real-time attack data)
#   - BinaryDefense (threat intelligence)

set -euo pipefail

IPSET_NAME="global-blocklist"
TEMP_FILE="/tmp/blocklist-$$.txt"
LOG_FILE="/var/log/blocklist-update.log"

# borestad list period: 1d, 3d, 7d, 14d, 30d, 60d, 90d, 120d
# Shorter = fewer IPs but more recent attacks
# Longer = more IPs but includes older threats
BORESTAD_PERIOD="${BORESTAD_PERIOD:-14d}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

cleanup() {
    rm -f "$TEMP_FILE" "/tmp/blocklist-restore-$$.txt"
}
trap cleanup EXIT

log "========== Starting blocklist update =========="

# Create ipset if it doesn't exist
if ! ipset list "$IPSET_NAME" &>/dev/null; then
    log "Creating ipset '$IPSET_NAME'..."
    ipset create "$IPSET_NAME" hash:ip maxelem 250000
else
    log "ipset '$IPSET_NAME' exists, flushing..."
    ipset flush "$IPSET_NAME"
fi

> "$TEMP_FILE"

download_list() {
    local name="$1"
    local url="$2"
    log "  Downloading: $name"
    if curl -sfL --max-time 30 "$url" >> "$TEMP_FILE" 2>/dev/null; then
        log "    ✓ Success"
        return 0
    else
        log "    ✗ Failed (non-fatal, continuing)"
        return 1
    fi
}

log "Downloading blocklists..."

# 1. borestad/AbuseIPDB - THE BEST SOURCE
download_list "AbuseIPDB (${BORESTAD_PERIOD}, 100% confidence)" \
    "https://raw.githubusercontent.com/borestad/blocklist-abuseipdb/main/abuseipdb-s100-${BORESTAD_PERIOD}.ipv4"

# 2. Blocklist.de - SSH attacks
download_list "Blocklist.de SSH" \
    "https://lists.blocklist.de/lists/ssh.txt"

# 3. Blocklist.de - All attack types
download_list "Blocklist.de All" \
    "https://lists.blocklist.de/lists/all.txt"

# 4. Emerging Threats - Compromised IPs
download_list "Emerging Threats" \
    "https://rules.emergingthreats.net/blockrules/compromised-ips.txt"

# 5. CI Army - Bad actors list
download_list "CI Army" \
    "http://cinsscore.com/list/ci-badguys.txt"

# 6. GreenSnow - Real-time attack IPs
download_list "GreenSnow" \
    "https://blocklist.greensnow.co/greensnow.txt"

# 7. BinaryDefense - Threat intelligence
download_list "BinaryDefense" \
    "https://www.binarydefense.com/banlist.txt"

log "Processing downloaded IPs..."

# Extract unique valid IPs and format for ipset restore
RESTORE_FILE="/tmp/blocklist-restore-$$.txt"
grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' "$TEMP_FILE" 2>/dev/null | sort -u | sed "s/^/add $IPSET_NAME /" > "$RESTORE_FILE"
TOTAL=$(wc -l < "$RESTORE_FILE")
log "  Found $TOTAL unique IPs"

# Batch load all IPs at once (fastest method)
log "  Loading into ipset..."
ipset restore -exist < "$RESTORE_FILE" 2>/dev/null || true

rm -f "$RESTORE_FILE"
log "  Done loading IPs"

log "Configuring iptables rules..."

# INPUT chain - blocks traffic to the host itself
if ! iptables -C INPUT -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null; then
    iptables -I INPUT 1 -m set --match-set "$IPSET_NAME" src -j DROP
    log "  ✓ Added INPUT chain rule"
else
    log "  ✓ INPUT chain rule exists"
fi

# DOCKER-USER chain - blocks traffic to Docker containers
if iptables -L DOCKER-USER &>/dev/null; then
    if ! iptables -C DOCKER-USER -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null; then
        iptables -I DOCKER-USER 1 -m set --match-set "$IPSET_NAME" src -j DROP
        log "  ✓ Added DOCKER-USER chain rule"
    else
        log "  ✓ DOCKER-USER chain rule exists"
    fi
else
    log "  ⚠ DOCKER-USER chain not found (Docker not installed?)"
fi

FINAL_COUNT=$(ipset list "$IPSET_NAME" 2>/dev/null | grep -c "^[0-9]" || echo "0")
log "========== Update Complete =========="
log "Total IPs blocked: $FINAL_COUNT"
log "====================================="

logger -t blocklist-update "Updated: $FINAL_COUNT IPs blocked" 2>/dev/null || true
