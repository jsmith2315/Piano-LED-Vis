#!/bin/bash
# Piano LED Visualizer - Raspberry Pi Installer
# Usage: bash install.sh <github-repo-url> [install-directory]
# Example: bash install.sh https://github.com/yourname/Piano-LED-Visualizer

set -e

# ── Arguments ────────────────────────────────────────────────────────────────
REPO_URL="$1"
INSTALL_DIR="${2:-$HOME/piano-led}"
SERVICE_NAME="piano-led"
PYTHON_VERSION="3.11"

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step()  { echo -e "\n${GREEN}━━ $1 ━━${NC}"; }

# ── Preflight ─────────────────────────────────────────────────────────────────
[ -z "$REPO_URL" ] && error "Usage: $0 <github-repo-url> [install-dir]"

if [ "$EUID" -eq 0 ]; then
    error "Do not run this script as root. It will use sudo where needed."
fi

echo ""
echo "  Piano LED Visualizer Installer"
echo "  Repo:        $REPO_URL"
echo "  Install dir: $INSTALL_DIR"
echo "  Python:      $PYTHON_VERSION"
echo ""
read -p "  Continue? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── 1. System packages ────────────────────────────────────────────────────────
step "Installing system packages"
sudo apt update -qq
sudo apt install -y \
    git \
    curl \
    fonts-freefont-ttf \
    libasound2-dev \
    liblgpio-dev
log "System packages installed"

# ── 2. uv ─────────────────────────────────────────────────────────────────────
step "Installing uv (Python version manager)"
if command -v uv &>/dev/null; then
    log "uv already installed: $(uv --version)"
else
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Add uv to PATH for remainder of this script
    export PATH="$HOME/.local/bin:$PATH"
    source "$HOME/.local/bin/env" 2>/dev/null || true
    log "uv installed: $(uv --version)"
fi
export PATH="$HOME/.local/bin:$PATH"

# ── 3. Python 3.11 ────────────────────────────────────────────────────────────
step "Installing Python $PYTHON_VERSION"
uv python install $PYTHON_VERSION
log "Python $PYTHON_VERSION ready"

# ── 4. Clone repository ───────────────────────────────────────────────────────
step "Setting up repository"
if [ -d "$INSTALL_DIR" ]; then
    warn "Directory $INSTALL_DIR already exists."
    read -p "  Delete and re-clone? [y/N] " reclone
    if [[ "$reclone" =~ ^[Yy]$ ]]; then
        sudo systemctl stop $SERVICE_NAME 2>/dev/null || true
        rm -rf "$INSTALL_DIR"
        git clone "$REPO_URL" "$INSTALL_DIR"
        log "Repository cloned"
    else
        log "Keeping existing directory"
    fi
else
    git clone "$REPO_URL" "$INSTALL_DIR"
    log "Repository cloned to $INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# ── 5. Python virtual environment ─────────────────────────────────────────────
step "Creating Python $PYTHON_VERSION virtual environment"
if [ -d "venv" ]; then
    warn "venv already exists, recreating..."
    rm -rf venv
fi
uv venv --python $PYTHON_VERSION venv
log "venv created"

# ── 6. Python packages ────────────────────────────────────────────────────────
step "Installing Python packages"
VENV_PYTHON="$INSTALL_DIR/venv/bin/python"
uv pip install --python "$VENV_PYTHON" \
    rpi-lgpio \
    webcolors \
    psutil \
    mido \
    Pillow \
    Flask \
    waitress \
    websockets \
    rpi-ws281x \
    python-rtmidi \
    "numpy>=1.26"
log "Python packages installed"

# ── 7. Systemd service ────────────────────────────────────────────────────────
step "Creating systemd service"
VENV_PYTHON="$INSTALL_DIR/venv/bin/python"
LOCAL_IP=$(hostname -I | awk '{print $1}')

sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=Piano LED Visualizer
After=network-online.target sound.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${VENV_PYTHON} ${INSTALL_DIR}/visualizer.py -a app
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
log "Service created and enabled"

# ── 8. Start service ──────────────────────────────────────────────────────────
step "Starting service"
sudo systemctl restart $SERVICE_NAME
sleep 6

if sudo systemctl is-active --quiet $SERVICE_NAME; then
    log "Service is running"
    echo ""
    echo "  ┌─────────────────────────────────────────┐"
    echo "  │   Piano LED Visualizer is ready!        │"
    echo "  │                                         │"
    echo "  │   Web interface:  http://${LOCAL_IP}  │"
    echo "  │   WebSocket:      ws://${LOCAL_IP}:8765│"
    echo "  │                                         │"
    echo "  │   Manage service:                       │"
    echo "  │   sudo systemctl status $SERVICE_NAME   │"
    echo "  │   sudo journalctl -u $SERVICE_NAME -f   │"
    echo "  └─────────────────────────────────────────┘"
    echo ""
else
    error "Service failed to start. Check logs:\n  sudo journalctl -u $SERVICE_NAME -n 50 --no-pager"
fi
