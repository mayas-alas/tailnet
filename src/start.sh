#!/usr/bin/env bash
set -Eeuo pipefail

# You can override this hook to execute a script not before startup! just as hooks
cd /

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
