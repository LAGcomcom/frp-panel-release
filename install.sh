#!/bin/bash
# FRP Panel Licensed - 一键安装脚本

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

INSTALL_DIR="/opt/frp-panel"
GITHUB_RAW="https://raw.githubusercontent.com/LAGcomcom/frp-panel-release/main"

info()  { echo -e "${GREEN}[提示]${NC} $1"; }
warn()  { echo -e "${YELLOW}[警告]${NC} $1"; }
error() { echo -e "${RED}[错误]${NC} $1"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "请使用 root 用户运行此脚本: sudo bash install.sh"
fi

check_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        info "检测到系统: $PRETTY_NAME"
    else
        error "无法检测操作系统"
    fi
    ARCH=$(uname -m)
    if [ "$ARCH" != "x86_64" ]; then
        error "当前架构 ($ARCH) 暂不支持，仅支持 x86_64"
    fi
}

interactive_config() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}      FRP Panel 授权版 安装向导${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    echo -ne "${YELLOW}面板端口 [3333]: ${NC}"
    read PANEL_PORT
    PANEL_PORT=${PANEL_PORT:-3333}

    echo -ne "${YELLOW}FRP 服务端绑定端口 [7000]: ${NC}"
    read BIND_PORT
    BIND_PORT=${BIND_PORT:-7000}

    echo -ne "${YELLOW}FRP Dashboard 端口 (可选，回车跳过): ${NC}"
    read DASHBOARD_PORT

    echo -ne "${YELLOW}管理员邮箱 [admin@example.com]: ${NC}"
    read ADMIN_EMAIL
    ADMIN_EMAIL=${ADMIN_EMAIL:-"admin@example.com"}

    while true; do
        echo -ne "${YELLOW}管理员密码 (至少6位): ${NC}"
        read -s ADMIN_PASS
        echo
        if [ ${#ADMIN_PASS} -ge 6 ]; then
            break
        fi
        echo -e "${RED}密码至少需要6位${NC}"
    done

    echo -ne "${YELLOW}确认密码: ${NC}"
    read -s ADMIN_PASS_CONFIRM
    echo
    if [ "$ADMIN_PASS" != "$ADMIN_PASS_CONFIRM" ]; then
        error "两次密码不一致"
    fi

    JWT_SECRET=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
    echo -ne "${YELLOW}JWT 密钥 [自动生成]: ${NC}"
    read JWT_INPUT
    JWT_SECRET=${JWT_INPUT:-$JWT_SECRET}

    SERVER_TOKEN=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
    echo -ne "${YELLOW}FRP Server Token [自动生成]: ${NC}"
    read TOKEN_INPUT
    SERVER_TOKEN=${TOKEN_INPUT:-$SERVER_TOKEN}

    echo -ne "${YELLOW}GitHub 镜像地址 [https://ghfast.top]: ${NC}"
    read GH_MIRROR
    GH_MIRROR=${GH_MIRROR:-"https://ghfast.top"}

    AUTH_SERVER="https://ymsq.movewellpro.fun"

    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}      确认配置信息${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo "  面板端口:      $PANEL_PORT"
    echo "  FRP绑定端口:   $BIND_PORT"
    [ -n "$DASHBOARD_PORT" ] && echo "  Dashboard端口: $DASHBOARD_PORT"
    echo "  管理员邮箱:    $ADMIN_EMAIL"
    echo "  JWT密钥:       ${JWT_SECRET:0:8}..."
    echo "  Server Token:  ${SERVER_TOKEN:0:8}..."
    echo "  GitHub镜像:    $GH_MIRROR"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo -ne "${YELLOW}确认安装? [Y/n]: ${NC}"
    read CONFIRM
    if [ "$CONFIRM" = "n" ] || [ "$CONFIRM" = "N" ]; then
        echo "安装已取消"
        exit 0
    fi
}

download_file() {
    local url="$1"
    local output="$2"

    if command -v aria2c &>/dev/null; then
        aria2c -x 16 -s 16 -k 1M -d "$(dirname "$output")" -o "$(basename "$output")" "$url" 2>&1
    elif command -v axel &>/dev/null; then
        axel -n 16 -o "$output" "$url" 2>&1
    else
        curl -# -L -o "$output" "$url"
    fi
}

download_files() {
    info "创建安装目录..."
    mkdir -p "$INSTALL_DIR"

    # 自动安装 aria2
    if ! command -v aria2c &>/dev/null; then
        info "安装 aria2 多线程下载工具..."
        if command -v apt &>/dev/null; then
            apt update -qq && apt install -y aria2 >/dev/null 2>&1
        elif command -v yum &>/dev/null; then
            yum install -y aria2 >/dev/null 2>&1
        fi
    fi

    if command -v aria2c &>/dev/null; then
        info "使用 aria2c 多线程下载 (16线程)"
    else
        warn "aria2 安装失败，使用 curl 下载"
    fi
    echo ""

    info "下载 panel (加密面板)..."
    download_file "${GITHUB_RAW}/panel" "$INSTALL_DIR/panel" || error "下载 panel 失败"

    info "下载 frps (FRP服务端)..."
    download_file "${GITHUB_RAW}/frps" "$INSTALL_DIR/frps" || error "下载 frps 失败"

    info "下载 agent..."
    download_file "${GITHUB_RAW}/agent" "$INSTALL_DIR/agent" 2>/dev/null || warn "下载 agent 失败 (可选组件)"

    chmod +x "$INSTALL_DIR/panel" "$INSTALL_DIR/frps" "$INSTALL_DIR/agent" 2>/dev/null
    info "文件下载完成"
}

generate_config() {
    info "生成配置文件..."

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

    info "配置文件生成完成"
}

setup_services() {
    info "创建 systemd 服务..."

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
    info "服务创建完成"
}

start_services() {
    info "启动服务..."

    systemctl start frps
    sleep 1
    systemctl start frp-panel
    sleep 2

    if systemctl is-active --quiet frps; then
        info "FRPS 运行正常"
    else
        warn "FRPS 启动失败，请检查: journalctl -u frps -f"
    fi

    if systemctl is-active --quiet frp-panel; then
        info "FRP Panel 运行正常"
    else
        warn "FRP Panel 启动失败，请检查: journalctl -u frp-panel -f"
    fi
}

print_result() {
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ip.sb 2>/dev/null || echo "YOUR_SERVER_IP")

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}         安装完成!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "  面板地址:  http://$SERVER_IP:$PANEL_PORT"
    echo "  管理员:    $ADMIN_EMAIL"
    echo ""
    echo "  FRPS 端口: $BIND_PORT"
    [ -n "$DASHBOARD_PORT" ] && echo "  Dashboard: http://$SERVER_IP:$DASHBOARD_PORT"
    echo ""
    echo -e "${YELLOW}常用命令:${NC}"
    echo "  查看面板日志:  journalctl -u frp-panel -f"
    echo "  查看FRPS日志:  journalctl -u frps -f"
    echo "  重启面板:      systemctl restart frp-panel"
    echo "  重启FRPS:      systemctl restart frps"
    echo "  停止所有:       systemctl stop frp-panel frps"
    echo ""
    echo -e "${YELLOW}配置文件位置:${NC}"
    echo "  面板配置:  $INSTALL_DIR/config.yaml"
    echo "  FRPS配置:  $INSTALL_DIR/frps.toml"
    echo ""
    echo -e "${CYAN}请先登录面板修改默认密码，并在网页中填写授权码!${NC}"
    echo ""
}

uninstall() {
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}      卸载 FRP Panel 授权版${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo -ne "${YELLOW}确定要卸载吗? [y/N]: ${NC}"
    read CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "卸载已取消"
        exit 0
    fi

    systemctl stop frp-panel frps 2>/dev/null || true
    systemctl disable frp-panel frps 2>/dev/null || true
    rm -f /etc/systemd/system/frp-panel.service
    rm -f /etc/systemd/system/frps.service
    systemctl daemon-reload
    rm -rf "$INSTALL_DIR"
    info "卸载完成"
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
