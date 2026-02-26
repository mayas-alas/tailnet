#!/usr/bin/env bash
set -Eeuo pipefail

# You can override this hook to execute a script before QEMU starts
# Move to root to ensure a clean context for both background processes and the final QEMU boot
cd /

# Launch Supervisor in the background to manage Tailscale and healthchecks
/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf &
