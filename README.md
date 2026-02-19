<div align="center"><a href="https://github.com/mayas-alas/tailnet"><img src=".github/logo.png" title="Logo" style="max-width:100%;" width="128" /></a>

# Tailnet — The Robust MF DevOps Superguide
### (Tailscale + QEMU + Codespaces + a healthy amount of irony)

</div>

> *A containerized QEMU hypervisor with Tailscale networking, a browser-based VNC UI, process orchestration via Supervisor, and enough shell scripts to make a sysadmin smile nervously. WIP. You were warned.*

---

## 🚀 What Even Is This?

Welcome to **Tailnet** — your all-in-one infra companion that mixes:

- 🔐 **Tailscale VPN** — secure mesh networking so your dev environment stops requiring goat sacrifices
- 🖥️ **QEMU** — full virtual machine *inside* a container, because why not
- 🌐 **Caddy** — built from source with `xcaddy`, reverse proxying everything in sight
- 📊 **noVNC** — browser-based VM access on port `8006`, no client needed
- ⚙️ **Supervisord** — keeps Tailscale and healthcheck running as proper daemons
- 🧩 **Sablier** *(optional)* — scale-to-zero proxy, downloads itself at runtime if you ask

Flexible. Modular. Future-proof. Casually unhinged.

---

## 🧩 Part 1 — CI/CD, DevSecOps & Fancy Acronyms

Before the magic, we acknowledge the buzzwords:

- **CI/CD** — automation so you stop clicking buttons like it's 2009
- **DevSecOps** — because someone (*you*) forgot security last time
- **IaC** — code that yells at servers until they comply

This guide moves through these automatically, intentionally, and sarcastically.

---

## 🗺️ Repo Map

| File / Dir | What It Does | Panic Level |
| :--- | :--- | :---: |
| `Dockerfile` | Multi-stage build: Caddy (xcaddy), Tailscale, QEMU, noVNC, Supervisor | 🔥🔥🔥 |
| `compose.yml` | Local deployment — passes KVM, TUN devices and network caps | 🔥🔥 |
| `kubernetes.yaml` | K8s manifest — has a stray indent on `claimName`, fix before prod | ⚠️ |
| `.env` | Tailscale auth key + tailnet name. Add to `.gitignore`. Seriously. | ☠️ |
| `tailnet.sh` | `tailscaled` → auth → MagicDNS → optional Sablier → Caddy (foreground) | 🔥🔥🔥 |
| `healthcheck.sh` | Probes Sablier, Caddy, and Tailscale. Returns `0` or `1`. | 🔥 |
| `src/entry.sh` | Real entrypoint (launched by tini). Sources every script, ends with QEMU. | 🔥🔥🔥 |
| `src/start.sh` | Hook that sources `tailnet.sh` + `healthcheck.sh`, then launches `supervisord` | 🔥🔥 |
| `src/reset.sh` | ~223 lines of defensive paranoia: validates engine, KVM, RAM, caps, storage | 🔥🔥 |
| `src/network.sh` | VM networking. 25KB. The most cursed file in the repo. Good luck. | 🔥🔥🔥 |
| `src/disk.sh` | Creates and manages QEMU disk images (22KB, respectable) | 🔥🔥 |
| `src/define.sh` | Picks the OS image based on `$BOOT` | 🔥🔥 |
| `src/install.sh` | Downloads the OS if not cached, shows progress | 🔥 |
| `src/boot.sh` | Wires UEFI/BIOS/TPM/CD boot args | 🔥🔥 |
| `src/server.sh` | Starts Nginx + Websocketd for the web UI | 🔥🔥 |
| `src/display.sh` | Configures VNC graphics output | 🔥 |
| `src/proc.sh` | CPU topology and core pinning | 🔥 |
| `src/memory.sh` | Calculates RAM for QEMU | 🔥 |
| `src/config.sh` | Assembles final QEMU argument string | 🔥🔥 |
| `src/utils.sh` | Shared helpers: `info`, `warn`, `error`, `formatBytes` | 🔥🔥 |
| `src/finish.sh` | Pre-boot log. Existential. Short. | 🟢 |
| `src/socket.sh` | Websocket bridge for Websocketd | 🔥 |
| `qemu/supervisord.conf` | Manages `[program:tailnet]` and `[program:healthcheck]` | 🔥🔥 |
| `web/` | Static assets, Nginx config, noVNC UI on `:8006` | 🔥 |
| `init.sh` | Empty. A shebang and a dream. Fill this in. | 🟡 |
| `.devcontainer/` | Codespaces config — boot Linux Mint (or any `$BOOT`) as your dev env | 🟢 |
| `.github/` | CI/CD workflows + logo. The DevSecOps altar. | 🟢 |

---

## 🔐 Part 2 — Tailscale VPN on GitHub Codespaces

### Why Tailscale?

Because remote dev environments shouldn't require sacrificing goats to the networking gods.

### How It's Wired Here

`tailnet.sh` handles the full lifecycle automatically:

```sh
tailscaled --state=/tailscale/tailscaled.state --tun=userspace-networking &
sleep 5
# Sets up MagicDNS via resolv.conf
# Authenticates with $TAILSCALE_AUTHKEY
# Optionally downloads and starts Sablier
# Runs Caddy in the foreground
```

Your node appears in the Tailnet as `$TAILSCALE_HOSTNAME` (default: `tailnet`).

### Quick Manual Setup (Codespaces)

```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
# Authenticate
tailscale up --ssh
# Boom — your Codespace is now inside your Tailnet
```

---

## 🖥️ Part 3 — QEMU VMs Inside the Container

### Why QEMU?

Because sometimes you want a whole OS inside your dev environment, just to feel alive.

### Devcontainer Example (Linux Mint)

```json
{
  "name": "Linux Mint",
  "service": "tailnet",
  "containerEnv": {
    "BOOT": "mint"
  },
  "forwardPorts": [8006],
  "portsAttributes": {
    "8006": { "label": "Web", "onAutoForward": "notify" }
  },
  "otherPortsAttributes": { "onAutoForward": "ignore" }
}
```

### Services & Ports

| Service | Port | Notes |
| :--- | :---: | :--- |
| **noVNC Web UI** | `8006` | Main browser entry point |
| **VNC (raw)** | `5900` | Direct VNC access |
| **SSH** | `22` | If the VM exposes it |
| **Caddy Admin** | `2019` | Polled by `healthcheck.sh` |
| **Sablier** | `10000` | Optional, if `INCLUDE_SABLIER=true` |

---

## 🌐 Part 4 — The Full Stack (Tailscale + QEMU + Codespaces)

Here's where it all clicks together:

```
Your Tailnet / Internet
        │
  Tailscale (userspace-net, MagicDNS)
        │
  Caddy (reverse proxy, optional TLS + Sablier scheduling)
        │
  Container bridge network
        │
  QEMU VM (running $BOOT, accessible via noVNC on :8006)
```

### The Boot Flow

```
tini (PID 1)
  └─► /run/entry.sh
        ├── utils.sh      helpers
        ├── reset.sh      env validation (engine, KVM, RAM, caps, storage)
        ├── server.sh     nginx + websocketd → noVNC :8006
        ├── define.sh     pick OS image based on $BOOT
        ├── install.sh    download OS if not cached
        ├── disk.sh       setup virtual disks
        ├── display.sh    VNC graphics config
        ├── network.sh    VM networking
        ├── boot.sh       UEFI/BIOS/TPM args
        ├── proc.sh       CPU topology
        ├── memory.sh     RAM allocation
        ├── config.sh     assemble final QEMU args
        ├── finish.sh     pre-boot log
        └── start.sh  ──► sources tailnet.sh + healthcheck.sh
                          then execs supervisord
                            ├── [program:tailnet]      → /tailnet.sh
                            └── [program:healthcheck]  → /healthcheck.sh
  └─► exec qemu-system-x86_64 $ARGS
```

---

## ⚙️ Key Environment Variables

| Variable | Default | Description |
| :--- | :---: | :--- |
| `BOOT` | `proxmox` | OS to boot inside QEMU |
| `CPU_CORES` | `max` | vCPUs (`max`, `half`, or a number) |
| `RAM_SIZE` | `max` | VM RAM (`max`, `half`, or e.g. `8G`) |
| `DISK_SIZE` | `174G` | Disk image size |
| `MACHINE` | `q35` | QEMU machine type |
| `KVM` | `Y` | KVM acceleration |
| `DISK_FMT` | `qcow2` | Image format |
| `TAILSCALE_HOSTNAME` | `tailnet` | Node name in the Tailnet |
| `TAILSCALE_AUTHKEY` | *(required)* | From `.env` — rotate it |
| `INCLUDE_SABLIER` | `true` | Download and start Sablier |
| `CADDY_WATCH` | — | Hot-reload Caddyfile if `true` |
| `ENGINE` | `docker` | Auto-detected: Docker / Podman / K8s |
| `DEBUG` | `Y` | Keep container alive on errors |

---

## 🧪 Part 5 — Optional Enhancements

- Add GitHub Actions for automated VM builds
- Add pipeline scanning to satisfy the DevSecOps cult
- Add backup tasks for the day everything breaks *(it will)*
- Flesh out `init.sh` as a pre-boot hook for secrets injection
- Add `sablier.yml` config to the repo (currently referenced but missing)

---

## ⚠️ Known Gotchas

> **`.env` security** — rotate auth keys before pushing. Add `.env` to `.gitignore`. You know this.

> **`kubernetes.yaml` indent bug** — `claim    name: tailnet-pvc` at line 60 will fail `kubectl apply`. Fix the spacing.

> **`init.sh` is empty** — great hook, zero implementation. Opportunity knocks.

> **Engine detection** — `reset.sh` auto-detects Docker vs Podman vs Kubernetes via `/run/.containerenv`. Rootless Podman behaves differently — check around line 34.

---

## 📝 Recap

You now have:

- A Tailscale-connected container that joins your private mesh on boot
- A QEMU VM running inside it, browser-accessible via noVNC on `:8006`
- Caddy as a reverse proxy with optional Sablier scale-to-zero
- Supervisord managing Tailscale and healthcheck as proper daemons
- A DevSecOps-friendly foundation with CI/CD hooks ready to wire up
- And this README, now less embarrassed about itself

---

<div align="center">

*Modular. Sarcastic. Casually robust. Edit it like the MF architect you are.*

[GitHub](https://github.com/mayas-alas/tailnet) · [Issues](https://github.com/mayas-alas/tailnet/issues) · [GNX Labs](https://github.com/mayas-alas)

</div>