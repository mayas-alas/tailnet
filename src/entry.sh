#!/usr/bin/env bash
set -Eeuo pipefail

: "${APP:="Tailnet"}"
: "${PLATFORM:="x64"}"
: "${SUPPORT:="https://github.com/mayas-alas/tailnet"}"

cd /run

. utils.sh      # Load functions
. reset.sh      # Initialize system
. server.sh     # Start webserver
. define.sh     # Define images
. install.sh    # Download image
. disk.sh       # Initialize disks
. display.sh    # Initialize graphics
. network.sh    # Initialize network
. boot.sh       # Configure boot
. proc.sh       # Initialize processor
. memory.sh     # Check available memory
. config.sh     # Configure arguments
. finish.sh     # Finish initialization
. start.sh      # Startup hook as hook

trap - ERR

version=$(qemu-system-x86_64 --version | head -n 1 | cut -d '(' -f 1 | awk '{ print $NF }')
info "Booting image${BOOT_DESC} using QEMU v$version..."

exec qemu-system-x86_64 ${ARGS:+ $ARGS}
