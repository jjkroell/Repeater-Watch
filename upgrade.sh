#!/usr/bin/env bash
# ============================================================================
# RepeaterWatch Upgrade Script
# Pulls latest changes from GitHub and restarts the service
# ============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

header() { echo -e "\n${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"; echo -e "${BLUE}${BOLD}  $1${NC}"; echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}\n"; }
ok()     { echo -e "${GREEN}✓${NC}  $1"; }
warn()   { echo -e "${YELLOW}⚠${NC}  $1"; }
err()    { echo -e "${RED}✗${NC}  $1"; }
info()   { echo -e "${CYAN}ℹ${NC}  $1"; }

if [[ $EUID -ne 0 ]]; then
    err "Please run as root: sudo bash upgrade.sh"
    exit 1
fi

RW_DIR="/opt/RepeaterWatch"

if [[ ! -d "$RW_DIR/.git" ]]; then
    err "RepeaterWatch not found at $RW_DIR — run the installer first."
    exit 1
fi

clear
header "RepeaterWatch Upgrade"
echo -e "  Pulling latest changes from GitHub and restarting.\n"

cd "$RW_DIR"

# ── Step 1: Git pull ──────────────────────────────────────────────────────────
header "Step 1/4 — Pulling latest code"

# Warn about local modifications
DIRTY=$(git status --porcelain | grep -v "^??" || true)
if [[ -n "$DIRTY" ]]; then
    warn "Local modifications detected:"
    echo "$DIRTY" | while IFS= read -r line; do echo -e "    ${YELLOW}${line}${NC}"; done
    echo ""
    info "These are your local changes and will be preserved where possible."
    info "If git reports conflicts, resolve them manually and re-run upgrade.sh."
    echo ""
fi

BEFORE=$(git rev-parse HEAD)
git pull --ff-only origin main || {
    warn "Fast-forward pull failed — attempting merge pull."
    git pull origin main
}
AFTER=$(git rev-parse HEAD)

if [[ "$BEFORE" == "$AFTER" ]]; then
    ok "Already up to date ($(git rev-parse --short HEAD))."
else
    ok "Updated: $(git rev-parse --short "$BEFORE") → $(git rev-parse --short "$AFTER")"
    echo ""
    info "Changes in this update:"
    git log --oneline "$BEFORE".."$AFTER" | while IFS= read -r line; do
        echo -e "    ${CYAN}•${NC}  $line"
    done
fi

# ── Step 2: Python dependencies ───────────────────────────────────────────────
header "Step 2/4 — Updating Python dependencies"

sudo -u meshcoremon "$RW_DIR/venv/bin/pip" install -q -r "$RW_DIR/requirements.txt"
ok "Python dependencies up to date."

# Symlink adafruit-nrfutil if available
if [[ -f "$RW_DIR/venv/bin/adafruit-nrfutil" ]]; then
    ln -sf "$RW_DIR/venv/bin/adafruit-nrfutil" /usr/local/bin/adafruit-nrfutil
    ok "adafruit-nrfutil symlink updated."
fi

# Refresh lgpio symlink if needed
PYVER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
LGPIO_PY=$(find /usr/lib/python3 -name "lgpio.py" ! -path "*/gpiozero/*" 2>/dev/null | head -1 || true)
SITE_VENV="$RW_DIR/venv/lib/python${PYVER}/site-packages"
if [[ -n "$LGPIO_PY" ]] && [[ ! -f "$SITE_VENV/lgpio.py" ]]; then
    SITE_SYS=$(dirname "$LGPIO_PY")
    ln -sf "$SITE_SYS/lgpio.py" "$SITE_VENV/lgpio.py"
    LGPIO_SO=$(ls "$SITE_SYS"/_lgpio*.so 2>/dev/null | head -1 || true)
    [[ -n "$LGPIO_SO" ]] && ln -sf "$LGPIO_SO" "$SITE_VENV/$(basename "$LGPIO_SO")"
    ok "lgpio symlink refreshed."
fi

# ── Step 3: .env migration ────────────────────────────────────────────────────
header "Step 3/4 — Checking .env for new settings"

ENV_FILE="$RW_DIR/.env"
MIGRATED=0

env_add_if_missing() {
    local key="$1" default="$2" comment="$3"
    if ! grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        echo "" >> "$ENV_FILE"
        [[ -n "$comment" ]] && echo "# $comment" >> "$ENV_FILE"
        echo "${key}=${default}" >> "$ENV_FILE"
        ok "Added ${key}=${default}"
        MIGRATED=1
    fi
}

env_add_if_missing "MESHCORE_LOGIN_MAX_ATTEMPTS" "5"    "Failed login attempts before lockout"
env_add_if_missing "MESHCORE_LOGIN_LOCKOUT_SECS" "300"  "Lockout duration in seconds"
env_add_if_missing "MESHCORE_TRUSTED_PROXIES"    ""     "Comma-separated IPs of trusted reverse proxies (e.g. 127.0.0.1 for cloudflared)"

if [[ $MIGRATED -eq 0 ]]; then
    ok ".env is already up to date."
fi

# ── Step 4: Restart service ───────────────────────────────────────────────────
header "Step 4/4 — Restarting RepeaterWatch"

systemctl restart RepeaterWatch
sleep 3

if systemctl is-active --quiet RepeaterWatch; then
    ok "RepeaterWatch restarted successfully."
else
    err "RepeaterWatch failed to start — check: sudo journalctl -u RepeaterWatch -n 30"
    exit 1
fi

# ── Done ──────────────────────────────────────────────────────────────────────
header "Upgrade Complete"

IP=$(hostname -I 2>/dev/null | awk '{print $1}')
PORT=$(grep "^MESHCORE_PORT=" "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo "5000")
echo -e "  ${BOLD}Dashboard:${NC}  ${GREEN}http://${IP}:${PORT}${NC}"
echo -e "  ${BOLD}Version:${NC}    $(git rev-parse --short HEAD) — $(git log -1 --format='%s')"
echo ""
ok "All done!"
