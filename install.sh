#!/bin/bash
# FRP Panel Licensed - One-click install script

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

INSTALL_DIR="/opt/frp-panel"
GITHUB_RAW="https://raw.githubusercontent.com/LAGcomcom/frp-panel-release/main"

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Please run as root: sudo bash install.sh"
fi

check_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        info "System: $PRETTY_NAME"
    else
        error "Cannot detect OS"
    fi
    ARCH=$(uname -m)
    if [ "$ARCH" != "x86_64" ]; then
        error "Architecture $ARCH not supported, x86_64 only"
    fi
}

interactive_config() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}    FRP Panel Licensed Setup${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    echo -ne "${YELLOW}Panel port [3333]: ${NC}"
    read PANEL_PORT
    PANEL_PORT=${PANEL_PORT:-3333}

    echo -ne "${YELLOW}FRP bind port [7000]: ${NC}"
    read BIND_PORT
    BIND_PORT=${BIND_PORT:-7000}

    echo -ne "${YELLOW}FRP Dashboard port (optional, press Enter to skip): ${NC}"
    read DASHBOARD_PORT

    echo -ne "${YELLOW}Admin email [admin@example.com]: ${NC}"
    read ADMIN_EMAIL
    ADMIN_EMAIL=${ADMIN_EMAIL:-"admin@example.com"}

    while true; do
        echo -ne "${YELLOW}Admin password (min 6 chars): ${NC}"
        read -s ADMIN_PASS
        echo
        if [ ${#ADMIN_PASS} -ge 6 ]; then
            break
        fi
        echo -e "${RED}Password must be at least 6 characters${NC}"
    done

    echo -ne "${YELLOW}Confirm password: ${NC}"
    read -s ADMIN_PASS_CONFIRM
    echo
    if [ "$ADMIN_PASS" != "$ADMIN_PASS_CONFIRM" ]; then
        error "Passwords do not match"
    fi

    JWT_SECRET=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
    echo -ne "${YELLOW}JWT secret [auto-generate]: ${NC}"
    read JWT_INPUT
    JWT_SECRET=${JWT_INPUT:-$JWT_SECRET}

    SERVER_TOKEN=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
    echo -ne "${YELLOW}FRP Server Token [auto-generate]: ${NC}"
    read TOKEN_INPUT
    SERVER_TOKEN=${TOKEN_INPUT:-$SERVER_TOKEN}

    echo -ne "${YELLOW}GitHub mirror [https://ghfast.top]: ${NC}"
    read GH_MIRROR
    GH_MIRROR=${GH_MIRROR:-"https://ghfast.top"}

    AUTH_SERVER="https://ymsq.movewellpro.fun"

    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}    Confirm Settings${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo "  Panel port:      $PANEL_PORT"
    echo "  FRP bind port:   $BIND_PORT"
    [ -n "$DASHBOARD_PORT" ] && echo "  Dashboard port:  $DASHBOARD_PORT"
    echo "  Admin email:     $ADMIN_EMAIL"
    echo "  JWT secret:      ${JWT_SECRET:0:8}..."
    echo "  Server token:    ${SERVER_TOKEN:0:8}..."
    echo "  GitHub mirror:   $GH_MIRROR"
    echo "  Auth server:     $AUTH_SERVER (default)"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo -ne "${YELLOW}Confirm install? [Y/n]: ${NC}"
    read CONFIRM
    if [ "$CONFIRM" = "n" ] || [ "$CONFIRM" = "N" ]; then
        echo "Install cancelled"
        exit 0
    fi
}

download_files() {
    info "Creating install directory..."
    mkdir -p "$INSTALL_DIR"

    info "Downloading files..."
    echo ""

    info "Downloading panel..."
    curl -# -L -o "$INSTALL_DIR/panel" "${GITHUB_RAW}/panel" || error "Failed to download panel"

    info "Downloading frps..."
    curl -# -L -o "$INSTALL_DIR/frps" "${GITHUB_RAW}/frps" || error "Failed to download frps"

    info "Downloading agent..."
    curl -# -L -o "$INSTALL_DIR/agent" "${GITHUB_RAW}/agent" 2>/dev/null || warn "Failed to download agent (optional)"

    chmod +x "$INSTALL_DIR/panel" "$INSTALL_DIR/frps" "$INSTALL_DIR/agent" 2>/dev/null
    info "Files downloaded"
}

generate_config() {
    info "Generating config files..."

    cat > "$INSTALL_DIR/config.yaml" << EOF
server:
  host: "0.0.0.0"
  port: $PANEL_PORT
  mode: "release"

database:
  driver: "sqlite"
  dsn: "frp-panel.db"

redis:
  addr: "localhost:6379"
  password: ""
  db: 0

jwt:
  secret: "$JWT_SECRET"
  expire_time: 24h
  issuer: "frp-panel"

frp:
  default_version: "0.68.0"
  github_mirror: "$GH_MIRROR"
  download_timeout: 300
  plugin_webhook_url: "http://YOUR_SERVER_IP:$PANEL_PORT/api/plugin/webhook"
  server_token: "$SERVER_TOKEN"

admin:
  email: "$ADMIN_EMAIL"
  password: "$ADMIN_PASS"

license:
  auth_server: "$AUTH_SERVER"
EOF

    DASHBOARD_CONFIG=""
    if [ -n "$DASHBOARD_PORT" ]; then
        DASHBOARD_CONFIG="
webServer.addr = \"0.0.0.0\"
webServer.port = $DASHBOARD_PORT
webServer.user = \"admin\"
webServer.password = \"$SERVER_TOKEN\""
    fi

    cat > "$INSTALL_DIR/frps.toml" << EOF
bindPort = $BIND_PORT
auth.method = "token"
auth.token = "$SERVER_TOKEN"$DASHBOARD_CONFIG
EOF

    cat > "$INSTALL_DIR/install_info.env" << EOF
PANEL_PORT=$PANEL_PORT
BIND_PORT=$BIND_PORT
ADMIN_EMAIL=$ADMIN_EMAIL
INSTALL_DIR=$INSTALL_DIR
INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')
EOF

    info "Config files generated"
}

setup_services() {
    info "Creating systemd services..."

    cat > /etc/systemd/system/frp-panel.service << EOF
[Unit]
Description=FRP Panel Licensed
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/panel -config $INSTALL_DIR/config.yaml
Restart=always
RestartSec=5
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/frps.service << EOF
[Unit]
Description=FRP Server
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/frps -c $INSTALL_DIR/frps.toml
Restart=always
RestartSec=5
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable frp-panel frps
    info "Services created"
}

start_services() {
    info "Starting services..."

    systemctl start frps
    sleep 1
    systemctl start frp-panel
    sleep 2

    if systemctl is-active --quiet frps; then
        info "FRPS running"
    else
        warn "FRPS failed to start, check: journalctl -u frps -f"
    fi

    if systemctl is-active --quiet frp-panel; then
        info "FRP Panel running"
    else
        warn "FRP Panel failed to start, check: journalctl -u frp-panel -f"
    fi
}

print_result() {
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ip.sb 2>/dev/null || echo "YOUR_SERVER_IP")

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}    Install Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "  Panel:     http://$SERVER_IP:$PANEL_PORT"
    echo "  Admin:     $ADMIN_EMAIL"
    echo ""
    echo "  FRPS port: $BIND_PORT"
    [ -n "$DASHBOARD_PORT" ] && echo "  Dashboard: http://$SERVER_IP:$DASHBOARD_PORT"
    echo ""
    echo -e "${YELLOW}Useful commands:${NC}"
    echo "  Panel log:    journalctl -u frp-panel -f"
    echo "  FRPS log:     journalctl -u frps -f"
    echo "  Restart panel: systemctl restart frp-panel"
    echo "  Restart frps:  systemctl restart frps"
    echo "  Stop all:      systemctl stop frp-panel frps"
    echo ""
    echo -e "${YELLOW}Config files:${NC}"
    echo "  Panel:  $INSTALL_DIR/config.yaml"
    echo "  FRPS:   $INSTALL_DIR/frps.toml"
    echo ""
    echo -e "${CYAN}Please change the default password after first login!${NC}"
    echo ""
}

uninstall() {
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}    Uninstall FRP Panel Licensed${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo -ne "${YELLOW}Are you sure? [y/N]: ${NC}"
    read CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "Uninstall cancelled"
        exit 0
    fi

    systemctl stop frp-panel frps 2>/dev/null || true
    systemctl disable frp-panel frps 2>/dev/null || true
    rm -f /etc/systemd/system/frp-panel.service
    rm -f /etc/systemd/system/frps.service
    systemctl daemon-reload
    rm -rf "$INSTALL_DIR"
    info "Uninstall complete"
}

main() {
    case "${1:-}" in
        uninstall|--uninstall|-u)
            uninstall
            ;;
        *)
            check_system
            interactive_config
            download_files
            generate_config
            setup_services
            start_services
            print_result
            ;;
    esac
}

main "$@"
