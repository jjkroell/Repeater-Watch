#!/usr/bin/env bash
# ============================================================================
# RepeaterWatch Full Stack Uninstaller
# Removes: RepeaterWatch, mctomqtt, SerialMux
# ============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

header() { echo -e "\n${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"; echo -e "${BLUE}${BOLD}  $1${NC}"; echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}\n"; }
ok()     { echo -e "${GREEN}✓${NC}  $1"; }
warn()   { echo -e "${YELLOW}⚠${NC}  $1"; }
info()   { echo -e "${CYAN}ℹ${NC}  $1"; }

yn() {
    # yn "prompt" [default y|n]
    local default="${2:-n}"
    local prompt="$1"
    [[ "$default" == "y" ]] && prompt+=" [Y/n]: " || prompt+=" [y/N]: "
    read -rp "$(echo -e "${CYAN}?${NC}  $prompt")" resp
    resp="${resp:-$default}"
    [[ "$resp" =~ ^[Yy] ]]
}

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✗${NC}  Please run as root: sudo bash uninstall.sh"
    exit 1
fi

clear
header "RepeaterWatch Uninstaller"

echo -e "  This will remove ${BOLD}RepeaterWatch, mctomqtt, and SerialMux${NC} from this system.\n"

if ! yn "Are you sure you want to continue?" n; then
    info "Uninstallation cancelled."
    exit 0
fi

# ── RepeaterWatch ────────────────────────────────────────────────────────────
header "Removing RepeaterWatch"

if systemctl is-active --quiet RepeaterWatch 2>/dev/null; then
    systemctl stop RepeaterWatch
    ok "Service stopped."
fi
if systemctl is-enabled --quiet RepeaterWatch 2>/dev/null; then
    systemctl disable RepeaterWatch
    ok "Service disabled."
fi
rm -f /etc/systemd/system/RepeaterWatch.service
ok "Service file removed."

rm -f /etc/sudoers.d/meshcoremon
ok "Sudoers entry removed."

if [[ -d /opt/RepeaterWatch ]]; then
    if yn "Keep the RepeaterWatch database (meshcore.db)?" y; then
        DB_BACKUP="/home/${SUDO_USER:-root}/meshcore-db-backup-$(date +%Y%m%d-%H%M%S).db"
        cp /opt/RepeaterWatch/meshcore.db "$DB_BACKUP" 2>/dev/null && ok "Database backed up to: $DB_BACKUP" || warn "No database file found."
    fi
    rm -rf /opt/RepeaterWatch
    ok "/opt/RepeaterWatch removed."
fi

if id meshcoremon &>/dev/null; then
    if yn "Remove service user 'meshcoremon'?" y; then
        userdel meshcoremon
        ok "User 'meshcoremon' removed."
    fi
fi

# ── mctomqtt ─────────────────────────────────────────────────────────────────
header "Removing mctomqtt"

if [[ -f /opt/mctomqtt/uninstall.sh ]]; then
    info "Running mctomqtt's own uninstaller..."
    echo ""
    bash /opt/mctomqtt/uninstall.sh
    echo ""
    ok "mctomqtt uninstaller completed."
else
    # Fallback: manual removal
    if systemctl is-active --quiet mctomqtt 2>/dev/null; then
        systemctl stop mctomqtt
        ok "mctomqtt stopped."
    fi
    if systemctl is-enabled --quiet mctomqtt 2>/dev/null; then
        systemctl disable mctomqtt
        ok "mctomqtt disabled."
    fi
    rm -f /etc/systemd/system/mctomqtt.service
    rm -rf /etc/systemd/system/mctomqtt.service.d
    rm -rf /opt/mctomqtt
    rm -rf /etc/mctomqtt
    ok "mctomqtt removed manually."
fi

# Remove the systemd override even if the uninstaller ran
rm -rf /etc/systemd/system/mctomqtt.service.d
ok "mctomqtt systemd overrides removed."

# ── SerialMux ────────────────────────────────────────────────────────────────
header "Removing SerialMux"

if systemctl is-active --quiet SerialMux 2>/dev/null; then
    systemctl stop SerialMux
    ok "SerialMux stopped."
fi
if systemctl is-enabled --quiet SerialMux 2>/dev/null; then
    systemctl disable SerialMux
    ok "SerialMux disabled."
fi
rm -f /etc/systemd/system/SerialMux.service
ok "Service file removed."

if [[ -d /opt/SerialMux ]]; then
    rm -rf /opt/SerialMux
    ok "/opt/SerialMux removed."
fi

# Clean up virtual ports (symlinks) if still present
for vport in /dev/ttyV0 /dev/ttyV1 /dev/ttyV2; do
    [[ -L "$vport" ]] && rm -f "$vport" && ok "Removed $vport"
done

# ── Reload systemd ────────────────────────────────────────────────────────────
systemctl daemon-reload
ok "systemd reloaded."

# ── Done ─────────────────────────────────────────────────────────────────────
header "Uninstallation Complete"
ok "RepeaterWatch, mctomqtt, and SerialMux have been removed."
echo ""
