#!/usr/bin/env bash
set -Eeuo pipefail

: "${VNC_PORT:="5900"}"    # VNC port
: "${MON_PORT:="7100"}"    # Monitor port
: "${WEB_PORT:="8006"}"    # Webserver port
: "${WSD_PORT:="8004"}"    # Websockets port
: "${WSS_PORT:="5700"}"    # Websockets port

if (( VNC_PORT < 5900 )); then
  warn "VNC port cannot be set lower than 5900, ignoring value $VNC_PORT."
  VNC_PORT="5900"
fi

cp -r /var/www/* /run/shm
rm -f /var/run/websocketd.pid

html "Starting $APP for $ENGINE..."

if [[ "${WEB:-}" != [Nn]* ]]; then

  # Start websocket server
  websocketd --address 127.0.0.1 --port="$WSD_PORT" /run/socket.sh >/var/log/websocketd.log &
  echo "$!" > /var/run/websocketd.pid

fi

return 0
