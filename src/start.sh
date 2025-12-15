#!/usr/bin/env bash
set -Eeuo pipefail

# You can override this hook to execute a script before startup!
cd /

. tailnet.sh      # Startup hook tailnet
. healthcheck.sh      # Load functions healthcheck

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf

return 0
