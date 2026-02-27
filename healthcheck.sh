#!/usr/bin/env sh

# Exit codes:
# 0 = healthy / all services up
# 1 = unhealthy / one or more services down

# Subcommands:
#   check  (default) – sourced by start.sh via `. healthcheck.sh` with no args;
#                      runs a one-shot health check at container startup
#   status           – called by supervisor as `/bin/sh /healthcheck.sh status`;
#                      same logic, loggable output; exits 0 or 1 for supervisor
#                      to track via exitcodes=0,1 + autorestart=true

_run_checks() {
  HEALTHY=0

  # Set default ports
  SABLIER_PORT=${SABLIER_PORT:-10000}
  CADDY_PORT=${CADDY_PORT:-2019}
  WEB_PORT=${WEB_PORT:-8006}

  # 1. Check Caddy built-in service health
  if ! curl -sf -o /dev/null "http://localhost:8080/status"; then
    echo "ERROR: Caddy health check failed (port 8080)"
    HEALTHY=1
  else
    echo "✓ Caddy is healthy"
  fi

  # 2. Check Sablier health (usually integrated via Caddy or standalone)
  if ! curl -sf -o /dev/null "http://localhost:${SABLIER_PORT}/"; then
    echo "ERROR: Sablier health check failed (port ${SABLIER_PORT})"
    HEALTHY=1
  else
    echo "✓ Sablier is healthy"
  fi

  # 2.5 Check Nginx health (on WEB_PORT)
  if ! curl -sf -o /dev/null "http://localhost:${WEB_PORT}/"; then
    echo "ERROR: Nginx health check failed (port ${WEB_PORT})"
    HEALTHY=1
  else
    echo "✓ Nginx is healthy"
  fi

  # 3. Check Tailscale network status
  if ! tailscale status --json 2>/dev/null | jq -e '.Self.Online == true' > /dev/null 2>&1; then
    echo "ERROR: Tailscale node is not online"
    HEALTHY=1
  else
    echo "✓ Tailscale is online"
  fi

  # 5. Check QEMU process
  if ! pgrep -f "qemu-system-x86_64" > /dev/null 2>&1; then
    echo "ERROR: QEMU process is not running"
    HEALTHY=1
  else
    echo "✓ QEMU is running"
  fi

  return $HEALTHY
}

case "${1:-check}" in

  # ─────────────────────────────────────────────────────────────────────────────
  # CHECK – sourced by start.sh at startup with no args
  # ─────────────────────────────────────────────────────────────────────────────
  check)
    if _run_checks; then
      echo "All services are healthy"
      exit 0
    else
      echo "One or more services are unhealthy"
      exit 1
    fi
    ;;

  # ─────────────────────────────────────────────────────────────────────────────
  # STATUS – called by supervisor; same checks, supervisor tracks exit code
  # ─────────────────────────────────────────────────────────────────────────────
  status)
    echo "--- healthcheck status $(date -u '+%Y-%m-%dT%H:%M:%SZ') ---"
    if _run_checks; then
      echo "All services are healthy"
      exit 0
    else
      echo "One or more services are unhealthy"
      exit 1
    fi
    ;;

  *)
    echo "Usage: $0 {check|status}"
    exit 1
    ;;

esac