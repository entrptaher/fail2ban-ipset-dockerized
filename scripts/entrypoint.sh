#!/bin/bash
set -e

echo "========================================"
echo "   Bot Protection Container Starting"
echo "========================================"

# Check if traefik log exists
if [ -f "/var/log/traefik/access.log" ]; then
    echo "Traefik log found."
else
    echo "WARNING: Traefik access log not mounted at /var/log/traefik/access.log"
    echo "Fail2ban traefik-probe jail will be disabled."
    sed -i 's/enabled = true/enabled = false/' /etc/fail2ban/jail.d/traefik.conf
fi

# Run initial blocklist update
echo ""
echo "Loading IP blocklists..."
/usr/local/bin/update-blocklist.sh

# Set up blocklist update loop (every 6 hours)
# Using loop instead of cron - simpler and guaranteed to work in Docker
echo ""
echo "Starting blocklist update loop (every 6 hours)..."
(
    while true; do
        sleep 21600  # 6 hours
        /usr/local/bin/update-blocklist.sh >> /var/log/blocklist-update.log 2>&1
    done
) &

# Start fail2ban
echo ""
echo "Starting fail2ban..."
fail2ban-client start

# Wait for fail2ban to fully start
sleep 2

# Show status
echo ""
echo "========================================"
echo "   Bot Protection Active"
echo "========================================"
echo ""
echo "Blocklist IPs: $(ipset list global-blocklist 2>/dev/null | grep -c '^[0-9]' || echo 0)"
echo ""
echo "Fail2ban jails:"
fail2ban-client status 2>/dev/null || echo "  (starting...)"
echo ""
echo "========================================"

# Keep container running - follow fail2ban log
exec tail -f /var/log/fail2ban.log
