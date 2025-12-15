# syntax=docker/dockerfile:1


################################################################################
# Stage 1: Builder
# Builds Caddy with optional plugins using xcaddy
################################################################################

FROM debian:trixie AS builder

LABEL org.opencontainers.image.authors="sudosu201 <mayas.alas@email.gnx>"
LABEL org.opencontainers.image.title="Tailnet"
LABEL org.opencontainers.image.description="Tailnet is a containerized environment."
LABEL org.opencontainers.image.version="0.0.1"
LABEL org.opencontainers.image.licenses="AGPL-3.0"
LABEL org.opencontainers.image.source="https://github.com/sudosu201/tailnet"
LABEL org.opencontainers.image.url="https://github.com/sudosu201/tailnet"
LABEL org.opencontainers.image.documentation="https://github.com/sudosu201/tailnet"
LABEL org.opencontainers.image.vendor="Sudosu201"
LABEL org.opencontainers.image.created="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
LABEL org.opencontainers.image.revision="$(git rev-parse HEAD)"

# Golang version for building Caddy
ARG GOLANG_VERSION=1.25.3

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

# Download and install Golang
RUN wget https://go.dev/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz \
  && tar -C /usr/local -xzf go${GOLANG_VERSION}.linux-amd64.tar.gz \
  && rm go${GOLANG_VERSION}.linux-amd64.tar.gz

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
    xcaddy build $PLUGIN_ARGS; \
  else \
    echo "No plugins specified. Building default caddy"; \
    xcaddy build; \
  fi
  

################################################################################
# Stage 2: Runtime
# Minimal Debian image with Tailscale, Caddy, and optionally Sablier
################################################################################

FROM debian:trixie


ARG TARGETARCH
ARG VERSION_ARG="0.0.1-beta"
ARG VERSION_UTK="1.2.0"
ARG VERSION_VNC="1.7.0-beta"
ARG VERSION_PASST="2025_09_19"

ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN="true"

RUN set -eu && \
    apt-get update && \
    apt-get --no-install-recommends -y install \
        supervisor \
        bc \
        jq \
        xxd \
        tini \
        wget \
        7zip \
        curl \
        ovmf \
        fdisk \
        nginx \
        swtpm \
        procps \
        ethtool \
        iptables \
        iproute2 \
        dnsmasq \
        xz-utils \
        apt-utils \
        net-tools \
        e2fsprogs \
        qemu-utils \
        websocketd \
        iputils-ping \
        genisoimage \
        inotify-tools \
        netcat-openbsd \
        ca-certificates \
        qemu-system-x86 && \
    wget "https://github.com/qemus/passt/releases/download/v${VERSION_PASST}/passt_${VERSION_PASST}_${TARGETARCH}.deb" -O /tmp/passt.deb -q && \
    dpkg -i /tmp/passt.deb && \
    apt-get clean && \
    mkdir -p /etc/qemu && \
    echo "allow br0" > /etc/qemu/bridge.conf && \
    mkdir -p /usr/share/novnc && \
    wget "https://github.com/novnc/noVNC/archive/refs/tags/v${VERSION_VNC}.tar.gz" -O /tmp/novnc.tar.gz -q --timeout=10 && \
    tar -xf /tmp/novnc.tar.gz -C /tmp/ && \
    cd "/tmp/noVNC-${VERSION_VNC}" && \
    mv app core vendor package.json ./*.html /usr/share/novnc && \
    unlink /etc/nginx/sites-enabled/default && \
    sed -i 's/^worker_processes.*/worker_processes 1;/' /etc/nginx/nginx.conf && \
    echo "$VERSION_ARG" > /run/version && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      iptables \
      ca-certificates \
      curl \
      vim \
      libc6 \
      jq \
      iputils-ping \
      dnsutils \
      openresolv \
      file \
      iproute2 \
    && rm -rf /var/lib/apt/lists/*

    
# Install Tailscale from official repository
RUN curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
 && curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends tailscale tailscale-archive-keyring \
 && rm -rf /var/lib/apt/lists/*

 # Sablier version, passed via build-arg
ARG SABLIER_VERSION
ENV SABLIER_VERSION=${SABLIER_VERSION}

# Copy Caddy binary from builder stage
COPY --from=builder /caddy /usr/bin/caddy

# Copy entrypoint and healthcheck scripts
COPY tailnet.sh /tailnet.sh
COPY healthcheck.sh /healthcheck.sh

# Make scripts executable
RUN chmod +x /tailnet.sh /healthcheck.sh

COPY --chmod=755 ./src /run/
COPY --chmod=755 ./web /var/www/
COPY --chmod=664 ./web/conf/defaults.json /usr/share/novnc
COPY --chmod=664 ./web/conf/mandatory.json /usr/share/novnc
COPY --chmod=744 ./web/conf/nginx.conf /etc/nginx/default.conf
COPY --chmod=644 ./qemu/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

ADD --chmod=755 "https://github.com/qemus/fiano/releases/download/v${VERSION_UTK}/utk_${VERSION_UTK}_${TARGETARCH}.bin" /run/utk.bin

VOLUME /storage
EXPOSE 22 5900 8006

ENV SUPPORT="https://github.com/sudosu201/tailnet"
ENV BOOT="proxmox"
ENV CPU_CORES="8G"
ENV RAM_SIZE="8G"
ENV DISK_SIZE="174G"
ENV MACHINE="q35"
ENV KVM="Y"
ENV GPU="Y"
ENV DISK_FMT="qcow2"
ENV DISK_TYPE="scsi"
ENV DISK_IO="threads"
ENV VM_NET_IP="10.4.20.99"
ENV ENGINE="podman"
ENV DEBUG="Y"
ENV TAILSCALE_HOSTNAME="tailnet"

ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]
