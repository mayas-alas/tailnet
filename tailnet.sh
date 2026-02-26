#!/usr/bin/env sh

# Subcommands:
#   start  (default) – called via `. tailnet.sh` from start.sh; runs full startup
#   status           – called by supervisor as `/bin/sh /tailnet.sh status`; reports service liveness

case "${1:-start}" in

  # ─────────────────────────────────────────────────────────────────────────────
  # START – sourced by start.sh with no args; runs the full initialisation flow
  # ─────────────────────────────────────────────────────────────────────────────
  start)
    set -e

    # Start tailscaled and wait for it to come up
    mkdir -p /storage/tailscale
    tailscaled \
      --state=/storage/tailscale/tailscaled.state \
      --socket=/var/run/tailscale/tailscaled.sock \
      --tun=userspace-networking \
      &
    sleep 5

    # Set up MagicDNS
    cat <<EOF > /etc/resolv.conf
nameserver 100.100.100.100
nameserver 127.0.0.11
search ${TAILNET_NAME} local
options ndots:0
EOF

    # Set default hostname if not provided
    if [ -z "${TAILSCALE_HOSTNAME:-}" ]; then
      TAILSCALE_HOSTNAME="tailnet"
    fi

    # Log in to Tailscale if not already logged in
    if tailscale status 2>/dev/null | grep -q '100\.'; then
      echo "Tailscale is already logged in. Skipping 'tailscale up'."
    else
      echo "Tailscale not logged in. Using auth key..."
      if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
        tailscale up --authkey="${TAILSCALE_AUTHKEY}" \
                     --hostname="${TAILSCALE_HOSTNAME}"
      else
        echo "WARNING: No auth key provided; skipping tailscale up."
      fi
    fi


    # Run Caddy (in foreground with exec)
    if [ -f /etc/caddy/Caddyfile ]; then
      if [ "${CADDY_WATCH:-}" = "true" ]; then
        exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile --watch
      else
        exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
      fi
    else
      exec caddy run
    fi
    ;;

  # ─────────────────────────────────────────────────────────────────────────────
  # STATUS – called by supervisor as a long-running poll; exits 0 (all up) or 1
  # ─────────────────────────────────────────────────────────────────────────────
  status)
    HEALTHY=0

    # tailscaled process
    if ! pgrep -x tailscaled > /dev/null 2>&1; then
      echo "ERROR: tailscaled is not running"
      HEALTHY=1
    else
      echo "✓ tailscaled is running"
    fi

    # Tailscale network status
    if ! tailscale status --json 2>/dev/null | jq -e '.Self.Online == true' > /dev/null 2>&1; then
      echo "ERROR: Tailscale node is not online"
      HEALTHY=1
    else
      echo "✓ Tailscale node is online"
    fi

    # Caddy process
    if ! pgrep -x caddy > /dev/null 2>&1; then
      echo "ERROR: caddy is not running"
      HEALTHY=1
    else
      echo "✓ caddy is running"
    fi

    # Sablier process
    if [ -f /usr/bin/sablier ]; then
      if ! pgrep -x sablier > /dev/null 2>&1; then
        echo "ERROR: sablier is not running"
        HEALTHY=1
      else
        echo "✓ sablier is running"
      fi
    fi

    if [ $HEALTHY -eq 0 ]; then
      echo "All tailnet services are running"
      exit 0
    else
      echo "One or more tailnet services are down"
      exit 1
    fi
    ;;

  *)
    echo "Usage: $0 {start|status}"
    exit 1
    ;;

esac