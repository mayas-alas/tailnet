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

  # Check Sablier health (via Caddy integration)
  echo "Checking Sablier health on port ${SABLIER_PORT}..."
  if ! curl -sf -o /dev/null http://localhost:${SABLIER_PORT}/; then
    echo "ERROR: Sablier integration health check failed"
    HEALTHY=1
  else
    echo "✓ Sablier integration is healthy"
  fi

  # Check Caddy admin API health
  echo "Checking Caddy health on port ${CADDY_PORT}..."
  if ! curl -sf -o /dev/null http://localhost:${CADDY_PORT}/config; then
    echo "ERROR: Caddy health check failed"
    HEALTHY=1
  else
    echo "✓ Caddy is healthy"
  fi

  # Check Tailscale network health
  echo "Checking Tailscale health..."
  if ! tailscale status --json 2>/dev/null | jq -e '.Self.Online == true' > /dev/null; then
    echo "ERROR: Tailscale is not online"
    HEALTHY=1
  else
    echo "✓ Tailscale is online"
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