#!/usr/bin/env bash
# ============================================================
#  RepeaterWatch Stack Installer
#  Installs: SerialMux → mctomqtt → RepeaterWatch
#
#  Usage:
#    chmod +x install.sh
#    sudo ./install.sh
#
#  Tested on: Raspberry Pi OS Bookworm (64-bit)
# ============================================================
set -euo pipefail

# ── Colour helpers ───────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Must run as root ─────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Please run as root: sudo ./install.sh"

# ── Configuration ────────────────────────────────────────────
INSTALL_DIR=/opt
SERVICE_USER=meshcoremon
SERVICE_GROUP=meshcoremon

# Auto-detect physical serial port
SERIAL_PORT=$(ls /dev/serial/by-id/ 2>/dev/null | head -1)
if [[ -z "$SERIAL_PORT" ]]; then
    warn "No USB serial device found. You will need to set SERIAL_PORT manually."
    SERIAL_PORT_FULL=""
else
    SERIAL_PORT_FULL="/dev/serial/by-id/$SERIAL_PORT"
    info "Detected serial port: $SERIAL_PORT_FULL"
fi

# ── 1. System packages ───────────────────────────────────────
info "Installing system packages..."
apt-get update -qq
apt-get install -y --no-install-recommends \
    git python3 python3-pip python3-venv python3-dev \
    i2c-tools socat nginx \
    build-essential libssl-dev libffi-dev

# Enable I2C
if ! grep -q "^dtparam=i2c_arm=on" /boot/firmware/config.txt 2>/dev/null; then
    echo "dtparam=i2c_arm=on" >> /boot/firmware/config.txt
    info "I2C enabled in /boot/firmware/config.txt (reboot required)"
fi

# ── 2. Service user ──────────────────────────────────────────
if ! id "$SERVICE_USER" &>/dev/null; then
    info "Creating service user: $SERVICE_USER"
    useradd --system --no-create-home --shell /usr/sbin/nologin \
        --groups dialout,i2c,gpio "$SERVICE_USER"
else
    info "Service user $SERVICE_USER already exists"
    # Ensure group memberships
    usermod -aG dialout,i2c,gpio "$SERVICE_USER" 2>/dev/null || true
fi

# ── 3. SerialMux ─────────────────────────────────────────────
info "Installing SerialMux..."
SERIALMUX_DIR="$INSTALL_DIR/SerialMux"
if [[ -d "$SERIALMUX_DIR/.git" ]]; then
    git -C "$SERIALMUX_DIR" pull --quiet
else
    rm -rf "$SERIALMUX_DIR"
    git clone --depth 1 https://github.com/MrAlders0n/SerialMux.git "$SERIALMUX_DIR"
fi
chown -R "$SERVICE_USER:$SERVICE_GROUP" "$SERIALMUX_DIR"

# SerialMux systemd unit
cat > /etc/systemd/system/SerialMux.service << EOF
[Unit]
Description=SerialMux — PTY multiplexer for MeshCore radio
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=/usr/bin/python3 $SERIALMUX_DIR/SerialMux.py \\
    --port ${SERIAL_PORT_FULL:-/dev/ttyUSB0} \\
    --baud 115200 \\
    --vports /dev/ttyV0 /dev/ttyV1 /dev/ttyV2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
success "SerialMux service configured"

# ── 4. mctomqtt ──────────────────────────────────────────────
info "Installing mctomqtt..."
MCTOMQTT_DIR="$INSTALL_DIR/mctomqtt"
if [[ -d "$MCTOMQTT_DIR/.git" ]]; then
    git -C "$MCTOMQTT_DIR" pull --quiet
else
    rm -rf "$MCTOMQTT_DIR"
    git clone --depth 1 https://github.com/Cisien/meshcoretomqtt.git "$MCTOMQTT_DIR"
fi

# Install .NET if not present
if ! command -v dotnet &>/dev/null; then
    info "Installing .NET runtime..."
    curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS --runtime aspnetcore
    DOTNET_ROOT="$HOME/.dotnet"
    export PATH="$PATH:$DOTNET_ROOT"
fi

mkdir -p /etc/mctomqtt/config.d
cat > /etc/mctomqtt/config.d/00-user.toml << EOF
[serial]
port = "/dev/ttyV1"
baud_rate = 115200

[mqtt]
# Configure your MQTT broker here
broker = "localhost"
port = 1883
# username = ""
# password = ""
EOF
chown -R "$SERVICE_USER:$SERVICE_GROUP" "$MCTOMQTT_DIR" /etc/mctomqtt

cat > /etc/systemd/system/mctomqtt.service << EOF
[Unit]
Description=mctomqtt — MeshCore to MQTT bridge
After=network.target SerialMux.service
Requires=SerialMux.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStartPre=/bin/sleep 10
WorkingDirectory=$MCTOMQTT_DIR
ExecStart=/usr/bin/dotnet run --project $MCTOMQTT_DIR
EnvironmentFile=/etc/mctomqtt/config.d/00-user.toml
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
success "mctomqtt service configured"

# ── 5. RepeaterWatch ─────────────────────────────────────────
info "Installing RepeaterWatch..."
RW_DIR="$INSTALL_DIR/RepeaterWatch"
if [[ -d "$RW_DIR/.git" ]]; then
    git -C "$RW_DIR" pull --quiet
else
    rm -rf "$RW_DIR"
    git clone --depth 1 https://github.com/MrAlders0n/RepeaterWatch.git "$RW_DIR"
fi

info "Creating Python virtualenv..."
python3 -m venv "$RW_DIR/venv"
"$RW_DIR/venv/bin/pip" install --quiet --upgrade pip
"$RW_DIR/venv/bin/pip" install --quiet -r "$RW_DIR/requirements.txt"
"$RW_DIR/venv/bin/pip" install --quiet bcrypt

# .env
if [[ ! -f "$RW_DIR/.env" ]]; then
    info "Creating .env from example..."
    cp "$RW_DIR/.env.example" "$RW_DIR/.env" 2>/dev/null || \
        cp "$(dirname "$0")/.env.example" "$RW_DIR/.env" 2>/dev/null || \
        touch "$RW_DIR/.env"

    SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    sed -i "s|^MESHCORE_SECRET_KEY=.*|MESHCORE_SECRET_KEY=$SECRET_KEY|" "$RW_DIR/.env"

    if [[ -n "$SERIAL_PORT_FULL" ]]; then
        sed -i "s|^MESHCORE_FLASH_SERIAL_PORT=.*|MESHCORE_FLASH_SERIAL_PORT=$SERIAL_PORT_FULL|" "$RW_DIR/.env"
    fi
fi

chown -R "$SERVICE_USER:$SERVICE_GROUP" "$RW_DIR"
chmod 640 "$RW_DIR/.env"

# sudoers for service control
cat > /etc/sudoers.d/meshcoremon << 'EOF'
meshcoremon ALL=(ALL) NOPASSWD: \
    /usr/bin/systemctl stop SerialMux, \
    /usr/bin/systemctl start SerialMux, \
    /usr/bin/systemctl stop mctomqtt, \
    /usr/bin/systemctl start mctomqtt, \
    /usr/bin/systemctl restart SerialMux, \
    /usr/bin/systemctl restart mctomqtt, \
    /usr/bin/systemctl restart RepeaterWatch, \
    /usr/bin/systemctl reboot
EOF
chmod 440 /etc/sudoers.d/meshcoremon
success "sudoers configured"

# RepeaterWatch systemd unit
cat > /etc/systemd/system/RepeaterWatch.service << EOF
[Unit]
Description=RepeaterWatch — MeshCore dashboard
After=network.target SerialMux.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$RW_DIR
EnvironmentFile=$RW_DIR/.env
ExecStart=$RW_DIR/venv/bin/python3 $RW_DIR/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
success "RepeaterWatch service configured"

# ── 6. Enable & start services ───────────────────────────────
info "Enabling and starting services..."
systemctl daemon-reload
systemctl enable SerialMux mctomqtt RepeaterWatch
systemctl restart SerialMux
sleep 3
systemctl restart mctomqtt || true
sleep 3
systemctl restart RepeaterWatch

# ── 7. Status summary ────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════${NC}"
echo -e "${BOLD}  Installation complete!${NC}"
echo -e "${BOLD}═══════════════════════════════════════${NC}"
for svc in SerialMux mctomqtt RepeaterWatch; do
    STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
    if [[ "$STATUS" == "active" ]]; then
        echo -e "  ${GREEN}●${NC} $svc — active"
    else
        echo -e "  ${RED}●${NC} $svc — $STATUS"
    fi
done
echo ""
echo -e "  Dashboard: ${CYAN}http://$(hostname -I | awk '{print $1}'):5000${NC}"
echo ""
echo -e "  Set a password:"
echo -e "  ${YELLOW}sudo -u $SERVICE_USER $RW_DIR/venv/bin/python3 $RW_DIR/setup_auth.py${NC}"
echo ""
