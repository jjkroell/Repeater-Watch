#!/usr/bin/env bash
# ============================================================================
# RepeaterWatch Full Stack Installer
# Installs: SerialMux → mctomqtt → RepeaterWatch
# ============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

header()   { echo -e "\n${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"; echo -e "${BLUE}${BOLD}  $1${NC}"; echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}\n"; }
ok()       { echo -e "${GREEN}✓${NC}  $1"; }
warn()     { echo -e "${YELLOW}⚠${NC}  $1"; }
err()      { echo -e "${RED}✗${NC}  $1"; }
info()     { echo -e "${CYAN}ℹ${NC}  $1"; }

# ── Root check ───────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    err "Please run as root: sudo bash install.sh"
    exit 1
fi

# ── Banner ───────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}"
echo "  ██████╗ ███████╗██████╗ ███████╗ █████╗ ████████╗███████╗██████╗ "
echo "  ██╔══██╗██╔════╝██╔══██╗██╔════╝██╔══██╗╚══██╔══╝██╔════╝██╔══██╗"
echo "  ██████╔╝█████╗  ██████╔╝█████╗  ███████║   ██║   █████╗  ██████╔╝"
echo "  ██╔══██╗██╔══╝  ██╔═══╝ ██╔══╝  ██╔══██║   ██║   ██╔══╝  ██╔══██╗"
echo "  ██║  ██║███████╗██║     ███████╗██║  ██║   ██║   ███████╗██║  ██║"
echo "  ╚═╝  ╚═╝╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝"
echo -e "${NC}${CYAN}             W A T C H${NC}"
echo ""
echo -e "  Full stack installer: ${BOLD}SerialMux + mctomqtt + RepeaterWatch${NC}"
echo ""

# ── Gather inputs upfront ────────────────────────────────────────────────────
header "Configuration"
echo -e "  Before installing, we need a few details.\n"

# --- Serial port ---
echo -e "  ${BOLD}Step 1/4 — Physical serial port${NC}\n"
USB_DEVICES=$(ls /dev/serial/by-id/ 2>/dev/null || true)
if [[ -n "$USB_DEVICES" ]]; then
    info "Detected USB serial devices:"
    while IFS= read -r d; do echo "      /dev/serial/by-id/$d"; done <<< "$USB_DEVICES"
    echo ""
fi
info "Enter the full /dev/serial/by-id/... path for your MeshCore radio."
info "Or enter a raw path (e.g. /dev/ttyUSB0)."
echo ""
read -rp "$(echo -e "${CYAN}?${NC}  Serial port: ")" SERIAL_PORT
if [[ -z "$SERIAL_PORT" ]]; then
    err "Serial port is required."
    exit 1
fi
ok "Serial port: $SERIAL_PORT"
echo ""

# --- IATA code ---
echo -e "  ${BOLD}Step 2/4 — IATA airport code${NC}\n"
info "3-letter IATA code for your region (e.g. YVR, SEA, LAX)."
info "Used by mctomqtt for MQTT topic naming on LetsMesh.net."
echo ""
read -rp "$(echo -e "${CYAN}?${NC}  IATA code: ")" IATA_RAW
IATA="${IATA_RAW^^}"
if [[ ! "$IATA" =~ ^[A-Z]{3}$ ]]; then
    err "IATA must be exactly 3 letters."
    exit 1
fi
ok "IATA: $IATA"
echo ""

# --- LetsMesh credentials ---
echo -e "  ${BOLD}Step 3/4 — LetsMesh.net credentials${NC}\n"
info "Your MeshCore companion app public key (64 hex chars)."
info "Find it in the MeshCore app: Settings → Device Info → Public Key."
echo ""
read -rp "$(echo -e "${CYAN}?${NC}  Owner public key: ")" LETSMESH_OWNER
if [[ ! "$LETSMESH_OWNER" =~ ^[0-9A-Fa-f]{64}$ ]]; then
    err "Public key must be exactly 64 hex characters."
    exit 1
fi
read -rp "$(echo -e "${CYAN}?${NC}  LetsMesh email: ")" LETSMESH_EMAIL
if [[ -z "$LETSMESH_EMAIL" ]]; then
    err "Email is required for LetsMesh authentication."
    exit 1
fi
ok "LetsMesh credentials set."
echo ""

# --- RepeaterWatch port ---
echo -e "  ${BOLD}Step 4/4 — RepeaterWatch web port${NC}\n"
info "Port the dashboard will listen on (default: 5000)."
read -rp "$(echo -e "${CYAN}?${NC}  Web port [5000]: ")" RW_PORT_RAW
RW_PORT="${RW_PORT_RAW:-5000}"
ok "Web port: $RW_PORT"
echo ""

echo -e "  ${BOLD}Login password will be set interactively during the install.${NC}\n"
echo -e "${YELLOW}  All inputs collected. Starting installation in 3 seconds...${NC}"
sleep 3

# ── Step 1: System dependencies ──────────────────────────────────────────────
header "Step 1/4 — System Dependencies"

apt-get update -qq
apt-get install -y -qq git python3 python3-venv python3-pip python3-lgpio curl
ok "System packages installed."

# ── Step 2: SerialMux ────────────────────────────────────────────────────────
header "Step 2/4 — SerialMux"

SERIALMUX_DIR="/opt/SerialMux"

if [[ -d "$SERIALMUX_DIR" ]]; then
    warn "SerialMux already found at $SERIALMUX_DIR — skipping clone."
else
    info "Cloning SerialMux..."
    git clone -q https://github.com/MrAlders0n/SerialMux.git "$SERIALMUX_DIR"
    ok "Cloned to $SERIALMUX_DIR"
fi

info "Configuring serial port: $SERIAL_PORT"
sed -i "s|REAL_PORT = '.*'|REAL_PORT = '$SERIAL_PORT'|" "$SERIALMUX_DIR/SerialMux.py"
ok "REAL_PORT configured."

pip3 install -q pyserial
ok "pyserial installed."

cat > /etc/systemd/system/SerialMux.service <<EOF
[Unit]
Description=SerialMux - Python Serial Port Multiplexer
After=local-fs.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $SERIALMUX_DIR/SerialMux.py
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now SerialMux
ok "SerialMux service enabled and started."

info "Waiting for virtual ports (/dev/ttyV0, /dev/ttyV1, /dev/ttyV2)..."
for i in $(seq 15); do [[ -e /dev/ttyV1 ]] && break; sleep 1; done
if [[ -e /dev/ttyV1 ]]; then
    ok "Virtual ports ready."
else
    warn "Virtual ports not yet visible — SerialMux may still be starting."
fi

# ── Step 3: mctomqtt ─────────────────────────────────────────────────────────
header "Step 3/4 — mctomqtt"

if [[ -d /opt/mctomqtt ]]; then
    warn "mctomqtt already found at /opt/mctomqtt — skipping installer."
else
    info "Running mctomqtt official installer..."
    echo ""
    bash <(curl -fsSL https://raw.githubusercontent.com/Cisien/meshcoretomqtt/main/install.sh)
    echo ""
    ok "mctomqtt installed."
fi

info "Writing /etc/mctomqtt/config.d/00-user.toml ..."
mkdir -p /etc/mctomqtt/config.d
cat > /etc/mctomqtt/config.d/00-user.toml <<EOF
# Generated by RepeaterWatch install.sh
# To edit: sudo nano /etc/mctomqtt/config.d/00-user.toml
# Then: sudo systemctl restart mctomqtt

[general]
iata = "$IATA"

[serial]
ports = ["/dev/ttyV1"]

[update]
repo = "Cisien/meshcoretomqtt"
branch = "main"

[[broker]]
name = "letsmesh-us"
enabled = true
server = "mqtt-us-v1.letsmesh.net"
port = 443
transport = "websockets"
keepalive = 60
qos = 0
retain = true

[broker.tls]
enabled = true
verify = true

[broker.auth]
method = "token"
audience = "mqtt-us-v1.letsmesh.net"
owner = "$LETSMESH_OWNER"
email = "$LETSMESH_EMAIL"

[[broker]]
name = "letsmesh-eu"
enabled = true
server = "mqtt-eu-v1.letsmesh.net"
port = 443
transport = "websockets"
keepalive = 60
qos = 0
retain = true

[broker.tls]
enabled = true
verify = true

[broker.auth]
method = "token"
audience = "mqtt-eu-v1.letsmesh.net"
owner = "$LETSMESH_OWNER"
email = "$LETSMESH_EMAIL"
EOF
ok "mctomqtt config written."

# Systemd override: wait for SerialMux virtual port before starting
mkdir -p /etc/systemd/system/mctomqtt.service.d
cat > /etc/systemd/system/mctomqtt.service.d/override.conf <<EOF
[Service]
ExecStartPre=
ExecStartPre=/bin/bash -c 'for i in \$(seq 30); do [ -e /dev/ttyV1 ] && exit 0; sleep 1; done; exit 1'
Restart=on-failure
RestartSec=15
RestartForceExitStatus=0
EOF

systemctl daemon-reload
systemctl restart mctomqtt
ok "mctomqtt restarted with updated config."

# ── Step 4: RepeaterWatch ────────────────────────────────────────────────────
header "Step 4/4 — RepeaterWatch"

RW_DIR="/opt/RepeaterWatch"

if ! id meshcoremon &>/dev/null; then
    useradd -r -s /usr/sbin/nologin -d "$RW_DIR" meshcoremon
    ok "Service user 'meshcoremon' created."
else
    ok "Service user 'meshcoremon' already exists."
fi

if [[ -d "$RW_DIR/.git" ]]; then
    warn "RepeaterWatch already installed at $RW_DIR — skipping clone."
else
    info "Cloning RepeaterWatch..."
    git clone -q https://github.com/jjkroell/RepeaterWatch.git "$RW_DIR"
    chown -R meshcoremon:meshcoremon "$RW_DIR"
    ok "Cloned to $RW_DIR"
fi

if [[ ! -d "$RW_DIR/venv" ]]; then
    info "Creating Python virtual environment..."
    sudo -u meshcoremon python3 -m venv "$RW_DIR/venv"
    ok "venv created."
fi

info "Installing Python dependencies..."
sudo -u meshcoremon "$RW_DIR/venv/bin/pip" install -q -r "$RW_DIR/requirements.txt"
ok "Python dependencies installed."

# Symlink lgpio from system packages into venv
PYVER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
SITE_SYS=$(python3 -c "import site; print(site.getsitepackages()[0])")
SITE_VENV="$RW_DIR/venv/lib/python${PYVER}/site-packages"

if [[ -f "$SITE_SYS/lgpio.py" ]] && [[ ! -f "$SITE_VENV/lgpio.py" ]]; then
    ln -sf "$SITE_SYS/lgpio.py" "$SITE_VENV/lgpio.py"
    LGPIO_SO=$(ls "$SITE_SYS"/_lgpio*.so 2>/dev/null | head -1 || true)
    [[ -n "$LGPIO_SO" ]] && ln -sf "$LGPIO_SO" "$SITE_VENV/$(basename "$LGPIO_SO")"
    ok "lgpio symlinked into venv."
elif [[ -f "$SITE_VENV/lgpio.py" ]]; then
    ok "lgpio already symlinked."
else
    warn "lgpio not found in system packages. Run: sudo apt install python3-lgpio"
fi

# Write .env (only if not already present to avoid overwriting existing installs)
if [[ ! -f "$RW_DIR/.env" ]]; then
    SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    cat > "$RW_DIR/.env" <<EOF
# Authentication — set password via setup_auth.py, do not edit hash manually
MESHCORE_PASSWORD_HASH=
MESHCORE_SECRET_KEY=$SECRET_KEY

# Serial (via SerialMux virtual port)
MESHCORE_SERIAL_PORT=/dev/ttyV0
MESHCORE_SERIAL_BAUD=115200
MESHCORE_SERIAL_TIMEOUT=5

# Polling
MESHCORE_POLL_INTERVAL=300

# Database
MESHCORE_DB_PATH=$RW_DIR/meshcore.db
MESHCORE_RETENTION_DAYS=30

# Flask
MESHCORE_HOST=0.0.0.0
MESHCORE_PORT=$RW_PORT
MESHCORE_DEBUG=0

# Firmware flash
MESHCORE_FLASH_SERIAL_PORT=$SERIAL_PORT
MESHCORE_FIRMWARE_UPLOAD_DIR=/tmp/meshcore-fw

# Terminal
MESHCORE_TERMINAL_SERIAL_PORT=/dev/ttyV2
MESHCORE_TERMINAL_SERIAL_BAUD=115200
EOF
    chown meshcoremon:meshcoremon "$RW_DIR/.env"
    chmod 640 "$RW_DIR/.env"
    ok ".env written."
else
    warn ".env already exists — skipping (not overwritten)."
fi

# Set login password interactively
echo ""
echo -e "  ${BOLD}Set a login password for the web dashboard.${NC}"
echo -e "  ${CYAN}Leave blank and press Ctrl+C to skip (disables auth).${NC}"
echo ""
sudo -u meshcoremon "$RW_DIR/venv/bin/python3" "$RW_DIR/setup_auth.py" || true
echo ""

# Install and start systemd service
cp "$RW_DIR/systemd/meshcore-monitor.service" /etc/systemd/system/RepeaterWatch.service
systemctl daemon-reload
systemctl enable --now RepeaterWatch
ok "RepeaterWatch service enabled and started."

# Sudoers for firmware flash feature
cat > /etc/sudoers.d/meshcoremon <<EOF
meshcoremon ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop SerialMux, /usr/bin/systemctl stop mctomqtt, /usr/bin/systemctl start SerialMux, /usr/bin/systemctl start mctomqtt
EOF
chmod 440 /etc/sudoers.d/meshcoremon
ok "Sudoers configured for firmware flash."

# ── Final status ─────────────────────────────────────────────────────────────
header "Installation Complete"

echo -e "  Service status:\n"
for svc in SerialMux mctomqtt RepeaterWatch; do
    if systemctl is-active --quiet "$svc"; then
        ok "$svc is running"
    else
        warn "$svc is NOT running — check: sudo journalctl -u $svc -n 20"
    fi
done

IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo ""
echo -e "  ${BOLD}Dashboard:${NC}  ${GREEN}http://${IP}:${RW_PORT}${NC}"
echo ""
echo -e "  ${BOLD}Useful commands:${NC}"
echo -e "    sudo systemctl status RepeaterWatch"
echo -e "    sudo journalctl -u RepeaterWatch -f"
echo -e "    sudo journalctl -u mctomqtt -f"
echo -e "    sudo journalctl -u SerialMux -f"
echo ""
echo -e "  ${BOLD}Change password:${NC}"
echo -e "    sudo -u meshcoremon $RW_DIR/venv/bin/python3 $RW_DIR/setup_auth.py"
echo -e "    sudo systemctl restart RepeaterWatch"
echo ""
ok "All done!"
