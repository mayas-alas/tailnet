# syntax=docker/dockerfile:1


################################################################################
# Stage 1: Builder
# Builds Caddy with optional plugins using xcaddy
################################################################################

FROM debian:trixie AS builder

ARG BUILD_DATE
ARG REVISION

ARG VERSION="0.0.4-beta"

LABEL org.opencontainers.image.authors="Maya <mayas.alas@email.gnx>"
LABEL org.opencontainers.image.title="Tailnet"
LABEL org.opencontainers.image.description="Tailnet is a containerized environment."
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.licenses="AGPL-3.0"
LABEL org.opencontainers.image.source="https://github.com/mayas-alas/tailnet"
LABEL org.opencontainers.image.url="https://github.com/mayas-alas/tailnet"
LABEL org.opencontainers.image.documentation="https://github.com/mayas-alas/tailnet"
LABEL org.opencontainers.image.vendor="GNX Labs"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${REVISION}"
LABEL org.opencontainers.image.base.name="tailnet:${VERSION}"

# Golang version for building Caddy
ARG GOLANG_VERSION=1.25.5
ARG TARGETARCH

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gnupg \
        debian-keyring \
        debian-archive-keyring \
        apt-transport-https \
        build-essential \
        gcc \
        file \
        procps \
        ruby \
        wget \
    && rm -rf /var/lib/apt/lists/*

# Download and install Golang based on target architecture
RUN wget -q "https://go.dev/dl/go${GOLANG_VERSION}.linux-${TARGETARCH}.tar.gz" -O /tmp/go.tar.gz \
  && tar -C /usr/local -xzf /tmp/go.tar.gz \
  && rm /tmp/go.tar.gz

ENV PATH="/usr/local/go/bin:$PATH"

# Install xcaddy for building Caddy with plugins
RUN curl -1sLf 'https://dl.cloudsmith.io/public/caddy/xcaddy/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-xcaddy-archive-keyring.gpg \
 && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/xcaddy/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-xcaddy.list \
 && apt-get update \
 && apt-get install -y xcaddy \
 && rm -rf /var/lib/apt/lists/*

# Optional space-separated list of Caddy plugins to include
ARG PLUGINS=""

# Build Caddy with or without plugins
RUN if [ -n "$PLUGINS" ]; then \
    echo "Building custom caddy with plugins: $PLUGINS"; \
    PLUGIN_ARGS=""; \
    for plugin in $PLUGINS; do \
      PLUGIN_ARGS="$PLUGIN_ARGS --with $plugin"; \
    done; \
    xcaddy build --with github.com/sablierapp/sablier-caddy-plugin@v1.0.1 $PLUGIN_ARGS; \
  else \
    echo "No plugins specified. Building default caddy with Sablier"; \
    xcaddy build --with github.com/sablierapp/sablier-caddy-plugin@v1.0.1; \
  fi
  

################################################################################
# Stage 2: Runtime
# Slim MVP Variant: Consolidation into Caddy, minimal footprint
################################################################################

FROM debian:trixie-slim

ARG TARGETARCH
ARG VERSION="0.0.4-beta"
ARG VERSION_VNC="1.7.0-beta"
ARG VERSION_PASST="2025_09_19"

ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN="true"

# Curated Package List for Slim MVP
RUN set -eu && \
    apt-get update && \
    apt-get --no-install-recommends -y install \
        tini \
        supervisor \
        ca-certificates \
        curl \
        wget \
        jq \
        xxd \
        procps \
        7zip \
        ovmf \
        swtpm \
        fdisk \
        libc6 \
        iptables \
        iproute2 \
        dnsmasq \
        e2fsprogs \
        qemu-utils \
        openresolv \
        websocketd \
        genisoimage \
        inotify-tools \
        net-tools \
        ethtool \
        util-linux \
        xz-utils \
        nginx \
        qemu-system-x86 && \
    # Remove default nginx configurations to avoid conflicts
    # Install PASST (High-Performance Net) per user request
    wget "https://github.com/qemus/passt/releases/download/v${VERSION_PASST}/passt_${VERSION_PASST}_${TARGETARCH}.deb" -O /tmp/passt.deb -q && \
    dpkg -i /tmp/passt.deb && \
    # Install NoVNC
    mkdir -p /usr/share/novnc && \
    wget "https://github.com/novnc/noVNC/archive/refs/tags/v${VERSION_VNC}.tar.gz" -O /tmp/novnc.tar.gz -q && \
    tar -xf /tmp/novnc.tar.gz -C /usr/share/novnc --strip-components=1 && \
    unlink /etc/nginx/sites-enabled/default && \
    sed -i 's/^worker_processes.*/worker_processes 1;/' /etc/nginx/nginx.conf && \
    echo "$VERSION" > /run/version && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install Tailscale from official repository
RUN curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
 && curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends tailscale \
 && rm -rf /var/lib/apt/lists/*

# Copy Caddy binary from builder stage
COPY --from=builder /caddy /usr/bin/caddy

# Build-time configuration and scripts
COPY tailnet.sh /tailnet.sh
COPY healthcheck.sh /healthcheck.sh
RUN chmod +x /tailnet.sh /healthcheck.sh

COPY --chmod=755 ./src /run/
COPY --chmod=755 ./web /var/www/
COPY --chmod=664 ./web/conf/defaults.json /usr/share/novnc
COPY --chmod=664 ./web/conf/mandatory.json /usr/share/novnc
COPY --chmod=644 ./qemu/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY --chmod=644 ./web/conf/nginx.conf /etc/nginx/nginx.conf
COPY --chmod=644 ./qemu/Caddyfile /etc/caddy/Caddyfile

VOLUME /storage

EXPOSE 8006 22 5900 10000 8080

ENV SUPPORT="https://github.com/mayas-alas/tailnet"
ENV BOOT="proxmox"
ENV VMX="Y"
ENV CPU_CORES="max"
ENV RAM_SIZE="max"
ENV DISK_SIZE="512G"
ENV MACHINE="q35"
ENV KVM="Y"
ENV GPU="Y"
ENV DISK_FMT="qcow2"
ENV DISK_TYPE="scsi"
ENV DISK_IO="io_uring"
ENV DISK_CACHE="writeback"
ENV NETWORK="passt"
ENV MTU="1280"
ENV VM_NET_IP="10.4.20.99"
ENV ENGINE="Docker"
ENV DEBUG="Y"
ENV USER_PORTS="8006"

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["/bin/sh", "/healthcheck.sh", "status"]
ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]
