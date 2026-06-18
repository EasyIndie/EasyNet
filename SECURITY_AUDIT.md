# EasyNet 安全审计报告

**审计日期：** 2026-06-18
**审计范围：** 全部 Shell 脚本、配置文件、文档
**审计方法：** 静态代码分析

---

## 严重性分类

| 级别 | 定义 |
|------|------|
| 🔴 CRITICAL | 可导致远程代码执行或完整系统沦陷 |
| 🟠 HIGH | 可导致凭据泄露或权限提升 |
| 🟡 MEDIUM | 有限条件下的信息泄露或配置弱点 |
| 🔵 LOW | 最佳实践缺失或防御纵深不足 |

---

## 🔴 CRITICAL

### C1. sing-box 二进制文件无完整性校验

| 文件 | 行号 |
|------|------|
| `scripts/clients/install_singbox_client.sh` | 120-151 |

```bash
resolve_singbox_url() {
    # 通过 GitHub API 动态解析最新版本
    GITHUB_API="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    # grep browser_download_url → 直接下载执行
}
curl -fL "$SINGBOX_URL" -o "$tarball"   # 无 SHA256 校验
```

**问题：**
- 通过 GitHub API 获取"latest"版本（非固定版本）
- 下载后无任何 SHA256 校验（连可选的机制都没有）
- 二进制以 root 权限安装和执行
- `.env.example` 中没有任何 `EASYNET_SINGBOX_INSTALL_SHA256` 变量

**影响：** 如果 GitHub 仓库被攻陷或发布被篡改，恶意二进制自动部署并以 root 运行。

**建议：** 固定版本号 + 添加 SHA256 校验机制；或在 `.env.example` 提供可配置的校验和变量。

---

## 🟠 HIGH

### H1. 两份协议配置文件无显式权限限制

#### H1a. Shadowsocks config.json

| 文件 | 行号 |
|------|------|
| `scripts/protocols/shadowsocks/deploy.sh` | 98-109 |

```bash
cat > "$CONFIG_DIR/config.json" << EOF
{ "servers": [{ "server_port": $PORT, "password": "$PSK", ... }] }
EOF
# ⚠️ 未调用 chmod，继承 umask（通常 644，即全局可读）
```

**问题：** 包含明文 PSK 的配置文件继承 umask 为 `644`（全局可读）。服务本身以 `nobody` 运行，但系统上任何用户均可读取密码。

#### H1b. Xray config.json

| 文件 | 行号 |
|------|------|
| `scripts/protocols/xray-reality/deploy.sh` | 72-169 |

```bash
cat > "$XRAY_DIR/config.json" << EOF   # 包含 Reality 私钥
EOF
# ⚠️ 未调用 chmod
chmod 644 "$XRAY_DIR/public.key"       # 公钥反而有 chmod（正确但反直觉）
```

**问题：** `config.json` 包含 Reality 私钥，但无 `chmod`。`public.key` 反而有显式 `chmod 644`——开发者优先处理了公钥而非私钥文件。

**建议（H1a+H1b）：** 两种协议写入配置后增加：
```bash
chmod 600 "$CONFIG_DIR/config.json"
```
或在 `deploy.sh` 入口添加 `umask 077` 全局生效。

---

### H2. 所有 systemd 服务缺少安全加固指令

**涉及全部 4 个协议 + sing-box 客户端**

| 服务 | 文件 | 行号 | User= | 加固指令 |
|------|------|------|-------|---------|
| shadowsocks-rust-server | `shadowsocks/deploy.sh` | 122-137 | `nobody` | **无** |
| hysteria-server | 上游 get.hy2.sh 生成 | — | 上游默认 | **无** |
| xray | 上游 install-release.sh 生成 | — | 上游默认 | **无** |
| wg-quick@wg0 | 系统包自带 | — | root | 需 root |
| easynet-singbox | `install_singbox_client.sh` | 306-320 | **无（root）** | **无** |
| easynet-singbox-update | 同上 | 322-329 | **无（root）** | **无** |

**问题：** 没有任何服务使用 `ProtectSystem=`、`ProtectHome=`、`PrivateTmp=`、`NoNewPrivileges=`、`CapabilityBoundingSet=` 等标准加固指令。sing-box 的客户端服务和更新服务甚至没有设置 `User=`，以 root 运行。

**建议：** 至少为 shadowsocks 和 sing-box（mixed 模式）添加：
```ini
ProtectSystem=full
PrivateTmp=yes
NoNewPrivileges=yes
CapabilityBoundingSet=~ (空)
```
sing-box TUN 模式需要 `CAP_NET_ADMIN`，应使用 `AmbientCapabilities=` 而非整个进程跑 root。

---

### H3. Nginx 缺少 TLS 密码套件配置和安全响应头

| 文件 | 行号 |
|------|------|
| `scripts/exposure/edge/deploy.sh` | 120-140（HTTPS server block） |

**缺失的配置：**

```nginx
# ❌ 缺失：ssl_ciphers
# ❌ 缺失：ssl_prefer_server_ciphers on
# ❌ 缺失：add_header Strict-Transport-Security
# ❌ 缺失：add_header X-Content-Type-Options
# ❌ 缺失：add_header X-Frame-Options
# ❌ 缺失：add_header Referrer-Policy
# ❌ 缺失：ssl_stapling / ssl_stapling_verify
```

**影响：**
- 依赖 nginx 内置默认密码套件，可能包含弱密码
- 无 HSTS，首次 HTTP 访问可被 SSL stripping
- 无 OCSP Stapling，证书吊销信息延迟传递

**建议：** 添加显式配置：
```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "DENY" always;
ssl_stapling on;
ssl_stapling_verify on;
```

---

### H4. WireGuard 私钥泄露到终端和 URI

| 文件 | 行号 |
|------|------|
| `scripts/protocols/wireguard/deploy.sh` | 163-179 |
| `scripts/protocols/wireguard/export.sh` | 63 |

```bash
# deploy.sh
cat "$wg_conf"                                            # 私钥 + PSK 明文输出到终端
wg_uri="...privateKey=${enc_priv}&presharedKey=${enc_psk}" # 私钥嵌入 URI 参数
echo "$wg_uri"                                             # 输出到终端
qrencode -t utf8 "$wg_uri"                                 # QR 码包含私钥

# export.sh — 同上模式，私钥进入 metadata.json
```

**影响：** 私钥和预共享密钥被输出到终端（可能被日志记录）、嵌入 URI（可能被分享）、进入 QR 码。

**建议：** 私钥不应嵌入 URI 查询参数。WireGuard URI 格式（`wg://`）标准做法是在客户端单独导入私钥。部署脚本提供 `--quiet` 模式。

---

## 🟡 MEDIUM

### M1. 外部安装脚本 SHA256 校验默认关闭

| 下载项 | 文件 | 行号 | 默认校验 |
|--------|------|------|---------|
| Xray-install | `xray-reality/deploy.sh` | 23 | ❌ 空 |
| get.hy2.sh | `hysteria2/deploy.sh` | 31 | ❌ 空 |
| get.acme.sh | `edge/deploy.sh` | 146 | ❌ 空 |
| shadowsocks-rust | `shadowsocks/deploy.sh` | 65 | ❌ 空 |

所有调用均使用 `"${EASYNET_XXX_INSTALL_SHA256:-}"`，默认值为空。`download_file()` 中 `[ -n "$sha256" ]` 条件使空值跳过校验。

且 Xray-install 指向 `raw/main/install-release.sh`（非固定版本），属移动目标。

**建议：**
- 至少在一个主版本上固定 Xray-install URL（当前稳定版本 `v26.3.27`）
- 在 `.env.example` 中填入已知正确的 SHA256 值，而非留空

---

### M2. Backup 使用可预测临时文件路径

| 文件 | 行号 |
|------|------|
| `scripts/deploy.sh` | 274 |

```bash
BACKUP_FILE="/tmp/easynet_backup_$(date +%s).tar.gz"
```

**问题：** `/tmp` 世界可写。使用 `date +%s`（秒级精度）生成文件名，存在 TOCTOU / symlink race。备份以 root 执行，内含所有协议凭据。

**建议：** 使用 `mktemp` 或写入专用目录 `/var/lib/easynet/backups/`。

---

### M3. 域名输入无校验

| 文件 | 行号 |
|------|------|
| `scripts/deploy.sh` | 214-219 |
| `scripts/protocols/hysteria2/deploy.sh` | 39-45 |

```bash
read -r -p "请输入 Edge Gateway 绑定域名: " EASYNET_DOMAIN
if [ -z "$EASYNET_DOMAIN" ]; then
    log_error "Edge Gateway 域名不能为空"
    return 1
fi
```

**问题：** 唯一校验是判空。域名随后嵌入 Nginx `server_name`、订阅 URL、TLS SNI 等关键位置。虽然不能直接导致命令注入（heredoc 内变量展开为字面量），但恶意构造的域名可导致 Nginx 配置语法错误。

**建议：** 增加域名格式校验：
```bash
[[ "$EASYNET_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]
```

---

### M4. JSON 通过字符串拼接构建

| 文件 | 行号 |
|------|------|
| `scripts/protocols/xray-reality/deploy.sh` | 58-67 |

```bash
SERVER_NAMES="${EASYNET_REALITY_SERVER_NAME:-www.microsoft.com,cloudflare.com}"
# 逗号分割后手动拼接 JSON 数组字符串
SERVER_NAMES_ARR="[${SERVER_NAMES_ARR%, }]"
```

**问题：** 环境变量中的双引号或反斜杠可破坏 JSON 结构。

**建议：** 使用 `jq --arg` 构建数组。

---

### M5. Subscription 文件包含全量凭据，仅靠路径随机性保护

| 文件 | 行号 |
|------|------|
| `scripts/generate_subscription.sh` | 283, 125 |
| `scripts/core/subscription_clash.sh` | 85 |

**问题：** `/var/www/html/s/<32-hex>/...` 路径下的订阅文件包含所有协议的密码/私钥，但仅靠 `openssl rand -hex 16` 生成的路径不可猜测性保护。如果路径被（Nginx 日志、反向代理错误配置）泄露，攻击者获得所有凭据。

**风险评估：** 128 位熵难以枚举，但**路径一旦泄露，无其他保护层**。

**建议：** 给订阅文件加访问令牌或 Basic Auth，作为第二层保护。

---

### M6. Sing-box 客户端和更新服务以 root 运行

| 文件 | 行号 |
|------|------|
| `scripts/clients/install_singbox_client.sh` | 306-320 |

```ini
[Service]
Type=simple
ExecStart=.../sing-box run -c .../config.json
# 没有 User= → 以 root 运行
```

Mixed 模式（默认）仅需要打开本地 SOCKS/HTTP 端口，完全不需要 root。TUN 模式只需 `CAP_NET_ADMIN`，不应整个进程跑 root。

**建议：** 添加 `DynamicUser=yes` 或创建 `singbox` 系统用户；TUN 模式使用 `AmbientCapabilities=CAP_NET_ADMIN`。

---

## 🔵 LOW

### L1. 通过 eval 插值 NGINX 路由模板

| 文件 | 行号 |
|------|------|
| `scripts/exposure/edge/routes.sh` | 70-73 |

```bash
eval "cat > \"$edge_routes_dir/${module}.conf\" <<ROUTEEOF
${MODULE_NGINX_ROUTE_TEMPLATE}
ROUTEEOF"
```

当前无模块定义 `MODULE_NGINX_ROUTE_TEMPLATE`，代码路径处于休眠状态。但未来任何定义此变量的模块都可能引入命令注入。

---

### L2. 文件权限小问题

- WireGuard `server_public.key` 写入后无 `chmod`（`wireguard/deploy.sh:73`）
- Edge 证书目录默认 `755`，世界可读目录列表（`cert_renew_hook.sh:37`）
- `umask 077` 未在 `deploy.sh` 中全局设置

---

### L3. IP 检测使用 HTTP

| 文件 | 行号 |
|------|------|
| `scripts/protocols/*/deploy.sh` | 多个 |

```bash
curl -s ipinfo.io/ip || curl -s ifconfig.me || curl -s api.ipify.org
```

这些服务均支持 HTTPS。MITM 可注入错误 IP，导致客户端配置指向错误服务器。

---

### L4. 核心库脚本缺少 `set -e`

14 个 core 库脚本无 `set -e`。虽然调用者设置了错误处理，但库被隔离使用时静默失败可导致部署状态不一致。

---

## 综合评分

### 做得好的

| 方面 | 评价 |
|------|------|
| **密钥生成** | 全程使用 `openssl rand`、`wg genkey`、`xray x25519` 等密码学安全随机源 |
| **下载使用 HTTPS** | 所有外部下载均使用 HTTPS，无 HTTP 明文下载 |
| **临时文件** | 多数使用 `mktemp`（除 M2 备份文件外）|
| **Hysteria2 权限** | 配置文件 `600`、私钥 `600`、证书目录 `750`——各协议中最佳 |
| **元数据文件** | `metadata.json` 统一 `chmod 600`，`metadata.sh:21` |
| **无 curl \| bash** | 所有下载先落地文件再执行，通过 `download_file()` 统一管理 |
| **manifest 白名单** | `discovery_get_manifest_value()` 使用 `case` 白名单读取变量，拒绝未知变量 |

### 关键改进项（按优先级）

| 优先级 | 问题 | 分类 |
|--------|------|------|
| 🔴 P0 | sing-box 二进制无完整性校验 (C1) | 供应链安全 |
| 🟠 P1 | 配置文件缺 `chmod` 导致全局可读 (H1a+H1b) | 凭据泄露 |
| 🟠 P2 | 全部 systemd 服务无加固指令 (H2) | 权限隔离 |
| 🟠 P3 | Nginx 缺 TLS 密码和安全头 (H3) | TLS 安全 |
| 🟠 P4 | WireGuard 私钥嵌入 URI 参数 (H4) | 凭据泄露 |
| 🟡 P5 | SHA256 校验默认关闭 (M1) + sing-box 无机制 | 供应链安全 |
| 🟡 P6 | 备份文件用 `/tmp` + 可预测文件名 (M2) | TOCTOU |
| 🟡 P7 | 域名输入无校验 (M3) | 输入验证 |
| 🟡 P8 | JSON 字符串拼接 (M4) | 配置注入 |
| 🟡 P9 | Subscription 单层路径保护 (M5) | 访问控制 |
| 🟡 P10 | Sing-box root 运行 (M6) | 权限最小化 |

---

## 快速修复建议（可直接执行的）

### 1. 修复两种协议配置文件的权限

```bash
# shadowsocks/deploy.sh，在 EOF 后立即添加
chmod 600 "$CONFIG_DIR/config.json"

# xray-reality/deploy.sh，在 config.json 生成后添加
chmod 600 "$XRAY_DIR/config.json"
```

### 2. 在 deploy.sh 入口设置 umask

```bash
# scripts/deploy.sh main() 顶部
umask 077   # 后续所有文件创建默认仅 root 可读写
```

### 3. 备份使用 mktemp 或专用目录

```bash
# scripts/deploy.sh:274
BACKUP_DIR="/var/lib/easynet/backups"
mkdir -p "$BACKUP_DIR" && chmod 600 "$BACKUP_DIR"
BACKUP_FILE=$(mktemp "$BACKUP_DIR/easynet_backup.XXXXXX.tar.gz")
```

### 4. sing-box 添加 SHA256 校验

在 `install_singbox_client.sh` 中添加 SHA256 校验逻辑（参考 `download.sh` 的模式），并在 `.env.example` 添加 `EASYNET_SINGBOX_INSTALL_SHA256`。

### 5. 固定 Xray-install 版本

将 URL 从 `raw/main/install-release.sh` 改为固定标签。

### 6. 为 shadowsocks 和 sing-box mixed 模式 systemd 添加加固

最低配置：
```ini
ProtectSystem=full
PrivateTmp=yes
NoNewPrivileges=yes
```

### 7. Nginx 添加 TLS 密码和安全头

加到 `scripts/exposure/edge/deploy.sh` 的 HTTPS server block 中。
