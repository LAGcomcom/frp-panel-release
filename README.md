# FRP Panel Licensed

FRP Panel 授权加密版本 - 一键安装部署

## 快速安装

SSH 登录服务器后执行：

```bash
bash <(curl -sSL https://raw.githubusercontent.com/comco/frp-panel-release/main/install.sh)
```

或者：

```bash
curl -sSL https://raw.githubusercontent.com/comco/frp-panel-release/main/install.sh -o install.sh
bash install.sh
```

## 安装向导

运行脚本后会交互式提示输入以下信息：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| 面板端口 | 3333 | Web 管理界面端口 |
| FRP 绑定端口 | 7000 | FRP 服务端端口 |
| Dashboard 端口 | (可选) | FRP Dashboard 端口 |
| 管理员邮箱 | admin@example.com | 登录账号 |
| 管理员密码 | (必填) | 至少6位 |
| JWT 密钥 | 自动生成 | Token 加密密钥 |
| Server Token | 自动生成 | FRP 认证令牌 |
| GitHub 镜像 | ghfast.top | 下载 FRP 客户端用 |
| 授权服务器 | ymsq.movewellpro.fun | 授权验证地址 |
| 授权码 | (必填) | AUTH-XXXX-XXXX-XXXX-XXXX |

## 卸载

```bash
bash /opt/frp-panel/install.sh uninstall
```

## 常用命令

```bash
# 查看日志
journalctl -u frp-panel -f
journalctl -u frps -f

# 重启服务
systemctl restart frp-panel
systemctl restart frps

# 查看状态
systemctl status frp-panel
systemctl status frps
```

## 文件说明

- `panel` - 加密面板二进制
- `frps` - FRP 服务端二进制
- `agent` - Agent 二进制
- `install.sh` - 一键安装脚本

## 系统要求

- Linux x86_64
- root 权限
- curl, openssl
