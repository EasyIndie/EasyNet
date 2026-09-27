# EasyNet 部署说明

## 适用场景

这份文档只保留部署 EasyNet 所需的最核心信息，适合首次搭建和后续快速复用。

## 部署前准备

- **VPS**：1 核、1 GB 内存、20 GB SSD 起步（参考：[RackNerd] $1.5/月～、[CloudCone] $2.5/月、[BandwagonHOST] $3/月 CN2 GIA、[Vultr] $5/月、[Alice Networks] $5/月 台北）
- **系统**：Ubuntu 22.04+ 或 Debian 11+
- **位置**：优先香港、日本、新加坡
- **域名**：Hysteria2 需要域名；订阅链接也需要域名，可与 Hysteria2 共用同一个域名
- **端口**：至少放行以下入站端口：

| 用途 | 端口 | 协议 |
|------|------|------|
| SSH | `22`（或自定义端口） | TCP |
| HTTP（acme 证书挑战 + Nginx 伪装） | `80` | TCP |
| HTTPS（Edge Gateway 订阅） | `443` | TCP |
| Xray+Reality | `8443`（可自定义） | TCP |
| Hysteria2 | `443`（可自定义） | UDP |
| Shadowsocks 2022 | `8388`（可自定义） | TCP+UDP |
| AmneziaWG | `51820`（可自定义） | UDP |
| Hysteria2 Port Hopping（可选） | `20000-30000`（可自定义） | UDP |

> 基础防火墙（SSH + 80/tcp + 443/tcp）始终放行；各协议的默认端口见下表，可通过环境变量自定义。

## 协议选择

| 协议 | 推荐度 | 核心混淆 | 适用场景 |
|------|--------|----------|----------|
| Xray+Reality | 高 | REALITY + XHTTP | 抗封锁优先，TLS 指纹模仿 + 包分片抗 ML |
| Hysteria2 | 高 | Salamander + Port Hopping | UDP/QUIC 场景，端口跳变抗封锁 |
| Shadowsocks 2022 | 中 | BLAKE3-AES-256-GCM | 兼容性场景，2022 Edition 强加密 |
| AmneziaWG | 中 | Jc/Jmin/Jmax/S1/S2/H1-H4 混淆 | 默认混淆，适合中转、低延迟、独立 VPN |

结论：

- **日常优先**：`Xray+Reality`，需要 UDP/QUIC 补充时加 `Hysteria2`（即 `balanced` 策略）
- **订阅承载与协议部署解耦**：配置 `EASYNET_DOMAIN` 或 `EASYNET_SUBSCRIPTION_DOMAIN` 后会自动启用 Edge Gateway 并打印订阅链接和二维码
- `AmneziaWG` 默认启用混淆（Jc/Jmin/Jmax/S1/S2/H1-H4，随机生成并持久化）

### 协议元数据对比（来自各模块 manifest）

| 属性 | Xray+Reality | Hysteria2 | Shadowsocks 2022 | AmneziaWG |
|------|:---:|:---:|:---:|:---:|
| Clash 类型 | `vless` | `hysteria2` | `ss` | `wireguard` |
| sing-box 类型 | `vless` | `hysteria2` | `shadowsocks` | —（sing-box 未支持 AmneziaWG，不在 sing-box 订阅中） |
| 安全等级（越小越安全） | 10 | 20 | 40 | 50 |
| 默认端口 | 8443 | 443 | 8388 | 51820 |
| Edge 模式 | `none` | `shared_tls` | `none` | `none` |
| systemd 服务名 | `xray` | `hysteria-server.service` | `shadowsocks-rust-server` | `awg-quick@wg0` |
| 所属策略 | strict, balanced, compat | balanced, compat | compat | compat |

### 域名要求

**只有 Hysteria2 和 Edge Gateway 需要域名**，其余协议独立运行。下表帮助判断"不设域名能不能用"以及"部署中断是否因域名缺失"。

| 组件 | 必须域名？ | 无域名时的行为 | 原因 |
|------|:----------:|---------------|------|
| **Xray+Reality** | ❌ 不需要 | 正常运行；无域名时自动回退「借用外部站点」模式 | REALITY 是“无证书 TLS”；设置域名可启用「自偷」以对抗 SNI→DNS 一致性检查 |
| **Hysteria2** | ✅ **必填** | **部署中断**，交互式部署会提示输入域名；自动化部署因 `EASYNET_DOMAIN` 未设而报错退出 | `shared_tls` 模式需要 Edge TLS 证书 |
| **Shadowsocks 2022** | ❌ 不需要 | 正常运行，无影响 | AEAD 加密，无 TLS 依赖 |
| **AmneziaWG** | ❌ 不需要 | 正常运行，无影响 | UDP 隧道 + AmneziaWG 混淆，无 TLS 依赖 |
| **Edge Gateway**（订阅分发） | ✅ **必填** | 跳过部署，**不生成外部可访问的订阅链接**；`show_subscription.sh` 仍可打印本地配置 | acme.sh 需要域名签发 Let's Encrypt 证书 |
| **Edge Gateway**（TLS 伪装站） | ✅ **必填** | 跳过部署，**Nginx 反代伪装不生效** | Nginx `server_name` 需要域名 |

> **故障判断**：部署过程中 Hysteria2 提示"请输入 Hysteria2 绑定域名"或报错"未找到 Hysteria2 TLS 证书" → 这是域名未设置导致的预期行为，不是脚本异常。

#### 无域名部署方案

如果手头没有域名，推荐以下方式：

**方案 A — 仅部署 Xray+Reality（最简）**
```bash
EASYNET_PROFILE=strict ./scripts/deploy.sh
```
Xray+Reality 是抗 DPI 能力最强的协议，无域名时首选。

**方案 B — 部署多个协议，跳过 Hysteria2**
```bash
# 从交互菜单中选择 xray-reality、shadowsocks、wireguard（跳过 hysteria2）
./scripts/deploy.sh
```
或通过环境变量单模块部署：
```bash
EASYNET_MODULE=xray-reality ./scripts/deploy.sh
EASYNET_MODULE=shadowsocks ./scripts/deploy.sh
EASYNET_MODULE=wireguard ./scripts/deploy.sh
```

**方案 C — 先无域名部署，后续补充域名**
```bash
# 第一次：无域名部署
EASYNET_PROFILE=strict ./scripts/deploy.sh

# 后续有了域名：补充部署 Edge Gateway + Hysteria2
EASYNET_DOMAIN=world.example.com EASYNET_MODULE=hysteria2 ./scripts/deploy.sh
```
注意：补充部署时需确保域名已 A 记录解析到服务器，且防火墙放行 `80/tcp`（acme 证书挑战用）和 `443/tcp+udp`。

### 协议混淆能力速览

| 能力 | Xray+Reality | Hysteria2 | Shadowsocks | AmneziaWG |
|------|:---:|:---:|:---:|:---:|
| TLS 指纹模仿 (REALITY) | ✅ | — | — | — |
| REALITY 自偷（抗 SNI→DNS 检查） | ✅ | — | — | — |
| HTTP/3 伪装 (XHTTP) | ✅ | ✅ (QUIC) | — | — |
| XMUX 多路复用 | ✅ | — | — | — |
| QUIC 混淆 (Salamander) | — | ✅ | — | — |
| 端口跳变 (Port Hopping) | — | ✅ | — | — |
| AmneziaWG 混淆 (Jc/Jmin/Jmax/S1/S2/H1-H4) | — | — | — | ✅ |
| 2022 Edition 板载加密 | — | — | ✅ | — |

### 协议混淆增强

协议混淆增强（AmneziaWG 默认已启用）：

```bash
# Xray+Reality: 自偷模式（用自有域名当 SNI，抗 SNI→DNS 一致性检查；默认 auto）
EASYNET_REALITY_MODE=self
# Xray+Reality: XHTTP/HTTP3 传输（仅 Xray 客户端支持，默认 tcp）
EASYNET_REALITY_TRANSPORT=xhttp
# Xray+Reality: XMUX 多路复用并发数（0 = 禁用，默认）
EASYNET_REALITY_XMUX_CONCURRENCY=4

# Hysteria2: 端口跳变（默认禁用，需放行防火墙端口范围）
EASYNET_HYSTERIA2_PORT_HOPPING=20000-30000

# 端口跳跃要求「整个 UDP 范围」都能到达本机：
#   - 本机 UFW 由 EasyNet 自动放行；
#   - 云厂商安全组必须手动放行同一范围（否则客户端跳变到该端口时会断流）。
# 服务端配置为 listen: :443,20000-30000 —— hysteria 监听 443，
# 并把 20000-30000/udp 重定向到 443（nftables 规则由 hysteria 自动创建/回收）；
# 服务进程需要 CAP_NET_ADMIN 与 AF_NETLINK（EasyNet 已配置）。

# AmneziaWG 默认启用（Jc/Jmin/Jmax/S1/S2/H1-H4 随机生成并持久化，无需配置）
```

> **Reality 自偷（`EASYNET_REALITY_MODE=self` / `auto`）**：2026 年审查者开始做「SNI→DNS 一致性检查」——
> 记录 `(SNI, 目的IP)` 后对 SNI 做 DNS 解析，若解析结果不等于目的 IP 即判定可疑（开源 DPI 库 nDPI 已实现）。
> 借用同机房邻居域名因此失效。自偷即把 `SNI` 设为**解析到本机的自有域名**、`dest` 指向本机 Edge 站点，
> 使 SNI 与 DNS 一致。`auto`（默认）会在检测到本机 Edge 证书时自动启用。


## 运维工作目录（~/.easynet）

EasyNet 涉及的路径天然分散（上游安装器与 systemd 单元硬编码）：

| 内容 | 真实位置 |
|---|---|
| Xray+Reality 配置 | `/usr/local/etc/xray` |
| Hysteria2 配置 | `/etc/hysteria` |
| Shadowsocks 配置 | `/etc/shadowsocks-rust` |
| AmneziaWG 配置 | `/etc/amnezia/amneziawg` |
| Edge Nginx 站点 | `/etc/nginx/sites-available/easynet-edge` |
| TLS 证书 | `/etc/ssl/easynet-edge` |
| acme.sh 状态 | `/root/.acme.sh` |
| 运行状态 / 订阅 | `/var/lib/easynet` |
| 静态根目录 / 规则集 | `/var/www/html` |
| 部署配置 | `/opt/easynet/.env` |

**物理搬迁这些目录会破坏上游升级与重装幂等**，因此 EasyNet 不搬文件，而是生成一个
**统一工作目录** `~/.easynet`，用符号链接把上面全部收敛到一处，并生成索引
`~/.easynet/README.md`（每一条都标注真实路径）：

```
~/.easynet/
├── README.md            # 路径索引（自动生成）
├── easynet              # 统一运维命令
├── project → /opt/easynet
├── env → /opt/easynet/.env
├── state → /var/lib/easynet
├── logs/                # 部署日志（deploy-<时间戳>.log、latest.log）
├── certs → /etc/ssl/easynet-edge
├── web → /var/www/html
├── nginx-site → /etc/nginx/sites-available/easynet-edge
├── acme → /root/.acme.sh
├── systemd → /etc/systemd/system
├── configs/{xray-reality,hysteria2,shadowsocks,wireguard} → 各自真实配置目录
└── security/{harden-ssh,sshd-hardening.conf,fail2ban.conf}
```

维护人员只需记住一个地方：

```bash
easynet status              # 服务 / 订阅 / 证书 / SSH 总览
easynet where               # 路径总表（~/.easynet 索引）
easynet path hysteria2      # 打印真实路径，配合 cd "$(easynet path hysteria2)"
easynet config              # 列出全部配置文件
easynet edit hysteria2      # 编辑后提示重启命令
easynet logs xray           # 跟踪日志；easynet logs deploy 看部署日志
easynet restart all         # 重启全部服务
easynet sub                 # 订阅链接与二维码
easynet deploy              # 重新部署（日志自动写入 ~/.easynet/logs/）
```

`easynet` 会被自动软链到 `/usr/local/bin/easynet`（可用 `EASYNET_HUB_NO_PATH_LINK=1` 关闭）。
hub 由 `core/hub.sh` 的 `ensure_easynet_hub()` 在每次部署/卸载结束时重建，是纯
`mkdir`/`ln` 操作，删除后不影响任何服务运行。

约定：**新增协议必须在 manifest 里声明 `MODULE_CONFIG_DIR`**，这样 hub 会自动索引它的配置目录。

## 快速部署

> **约定：服务器上一律用 `.env` 文件驱动部署**（不要内联环境变量）。
> `.env` 是配置的唯一来源：改动可 diff、可回滚，反复重部署结果一致。
> 它只接受 `EASYNET_[A-Z0-9_]+`，权限保持 `600`（含订阅路径密钥）。
> 每次部署都是同一条命令 —— `bash scripts/deploy.sh`（自动加载同目录 `.env`）。

### 1. 登录服务器

```bash
ssh root@your-server-ip
```

### 2. 一键安装（推荐，无需 git clone）

```bash
curl -fsSL https://github.com/EasyIndie/EasyNet/releases/latest/download/easynet-install.sh -o install.sh
sudo bash install.sh
```

安装器会自动：下载 release 包 → 校验 SHA256 → 解压到 `/opt/easynet`（可用 `EASYNET_INSTALL_DIR` 覆盖）→ 执行 `scripts/deploy.sh`。
失败即中止，遵循项目「无 `curl | bash`、先落地后校验」规范。

自动化部署（`EASYNET_*` 变量原样透传给 `deploy.sh`）：

```bash
sudo EASYNET_PROFILE=balanced EASYNET_DOMAIN=world.example.com bash install.sh
```

指定版本：`sudo EASYNET_VERSION=<版本 tag> bash install.sh`。

只安装不部署（便于先写好 `.env` 再部署；重装/升级时已存在的 `.env` 会被保留）：

```bash
sudo EASYNET_VERSION=<版本 tag> EASYNET_INSTALL_ONLY=true bash install.sh
sudo install -m 600 /dev/stdin /opt/easynet/.env <<'ENV'
EASYNET_PROFILE=balanced
EASYNET_DOMAIN=world.jokerhub.cn
ENV
cd /opt/easynet && bash scripts/deploy.sh
```

### 3. 从源码部署（开发 / 审计）

```bash
apt update && apt install -y git
git clone https://github.com/EasyIndie/EasyNet.git
cd EasyNet
./scripts/deploy.sh
```

部署菜单中的编号由协议自动发现生成，按 **抗 DPI 能力从高到低**（`MODULE_SECURITY_RANK` 升序）排列：

- `0`=全部部署
- `1`=`xray-reality`（安全等级 10）→ `2`=`hysteria2`（20）→ `3`=`shadowsocks`（40）→ `4`=`wireguard`（60）
- `N+1`=退出

> 新增模块后按安全等级自动插入，编号随之变化。菜单仅在无自动化变量时显示；环境变量自动部署则执行一次后退出。

说明：各协议模块部署后会导出标准 metadata，订阅生成器只读取 metadata。部署入口统一走 `scripts/protocols/*/` 与 `scripts/exposure/edge/`。订阅链接只在存在 Edge Gateway 域名时打印。

### 4. 自动化部署

方式一：使用 `.env`

```bash
cd /opt/easynet          # 一键安装器默认目录；源码部署则在仓库根目录
cp .env.example .env
./scripts/deploy.sh
```

方式二：按编号部署

```bash
EASYNET_SERVICE_CHOICE=0 EASYNET_DOMAIN=world.example.com ./scripts/deploy.sh
```

方式三：按模块部署

```bash
EASYNET_MODULE=xray-reality ./scripts/deploy.sh
EASYNET_MODULE=hysteria2 EASYNET_DOMAIN=world.example.com ./scripts/deploy.sh
EASYNET_MODULE=shadowsocks ./scripts/deploy.sh
EASYNET_MODULE=wireguard ./scripts/deploy.sh
```

方式四：按策略部署

```bash
EASYNET_PROFILE=strict ./scripts/deploy.sh
EASYNET_PROFILE=balanced EASYNET_DOMAIN=world.example.com ./scripts/deploy.sh
EASYNET_PROFILE=compat ./scripts/deploy.sh
```

策略说明：

| 策略 | 包含模块 | 适用场景 |
|------|----------|----------|
| `strict` | 仅 `xray-reality` | 最高反 DPI，最小攻击面 |
| `balanced` | `xray-reality` + `hysteria2` | 强安全 + 良好性能，推荐默认 |
| `compat` | 全部已发现模块 | 最大兼容性，各类客户端 |

> 注意：Shadowsocks 和 AmneziaWG 仅包含于 `compat` 策略，`balanced` 策略不含这两者。如需部署全部 4 种协议请使用 `compat` 或单独指定模块。

订阅承载：

- 配置 `EASYNET_DOMAIN` 或 `EASYNET_SUBSCRIPTION_DOMAIN` 会自动部署 Edge Gateway，不改变协议组合
- Edge Gateway 默认独占公网 `443/tcp`，首次部署时生成稳定随机订阅前缀，并使用 Nginx 在以下路径发布订阅：

| 路径 | 格式 | 适用客户端 |
|------|------|-----------|
| `https://域名/s/\<随机值\>/sub` | Base64 URI 聚合 | Shadowrocket / v2rayN / v2rayNG |
| `https://域名/s/\<随机值\>/clash` | YAML | Clash Verge Rev / Mihomo |
| `https://域名/s/\<随机值\>/singbox` | JSON | sing-box |
| `https://域名/s/\<随机值\>/singbox-client.sh` | Shell 脚本 | 树莓派 / 卡片机安装脚本 |

- 默认**仅**提供随机路径（如 `/s/<32位hex>/sub`）；`/sub`、`/clash`、`/singbox` 这类固定路径可被猜中（域名可从证书透明度日志获知），默认关闭，可用 `EASYNET_SUBSCRIPTION_DIRECT_PATHS=true` 开启
- 可用 `EASYNET_SUBSCRIPTION_PATH_PREFIX` **固定**随机路径：重装服务器后订阅 URL 不变，客户端无需重新导入
- 随机订阅前缀会持久化保存，重启、重部署、证书续期和重新生成订阅都不会改变；可运行 `./scripts/show_subscription.sh` 随时重新显示链接和二维码
- 如怀疑订阅链接泄露，可运行 `./scripts/rotate_subscription.sh` 主动轮换订阅入口；如需给多设备迁移留出时间，可使用 `./scripts/rotate_subscription.sh --grace` 暂时保留旧入口
- `Hysteria2` 使用 Edge 统一证书（`shared_tls` 模式），自身监听 `443/udp` 承载 QUIC 流量
- 如同时配置 `EASYNET_DOMAIN` 与 `EASYNET_SUBSCRIPTION_DOMAIN`，两者都需要解析到当前服务器，Edge 证书会同时覆盖这两个域名
- 如确需调整 Edge 端口，可使用高级变量 `EASYNET_EDGE_HTTPS_PORT`
- Edge Gateway 根路径默认反向代理到 `https://www.bing.com` 以消除指纹，可通过 `EASYNET_EDGE_MASQUERADE_URL` 自定义
- 当前订阅输出保留 **URI、Clash/Mihomo 与 sing-box** 三类入口
- 订阅文件中的节点顺序 **按安全性从高到低**（manifest 中 `MODULE_SECURITY_RANK`）输出：`Xray+Reality`（10）、`Hysteria2`（20）、`Shadowsocks`（40）、`AmneziaWG`（50）

环境变量：

- `.env` 只加载 `EASYNET_*` 前缀变量，非 `EASYNET_*` 变量会被忽略
- 远程安装脚本和发布包支持可选 SHA256 校验，变量见 `.env.example`

## 升级到新版本

已用一键安装器部署（脚本在 `/opt/easynet`）时，可**原地升级**，无需全新安装：

```bash
curl -fsSL https://github.com/EasyIndie/EasyNet/releases/latest/download/easynet-install.sh -o install.sh
EASYNET_VERSION=<版本 tag，如 0.0.11> bash install.sh
```

安装器会替换 `/opt/easynet/scripts` 为新版本、保留 `/opt/easynet/.env`，然后重跑 `deploy.sh`。

升级时各类状态是否保留：

| 项目 | 是否保留 | 说明 |
|------|:--:|------|
| `/opt/easynet/.env` | ✅ | 域名/策略等配置延续 |
| `/var/lib/easynet` 状态 | ✅ | metadata、Edge 状态 |
| 订阅 URL 路径前缀 | ✅ | 随机路径不变，客户端订阅地址不变 |
| Edge 证书 | ✅ | acme.sh 复用/续期 |
| Xray-Reality UUID/密钥 | ✅ | 从现有 `config.json` 保留 |
| Shadowsocks 密码 | ✅ | 从现有 `config.json` 保留 |
| AmneziaWG 服务端密钥/客户端配置/混淆参数 | ✅ | 已存在则跳过生成（含 Jc/S1/S2/H1-H4） |
| Hysteria2 密码/混淆密码 | ✅（0.0.10+） | 复用 `/etc/hysteria/easynet.env`；0.0.9 及更早版本会轮换 |

> 升级后建议在客户端**更新一次订阅**，确保拿到最新配置。仅想更新脚本、不重新部署时，可用 `EASYNET_INSTALL_ONLY=true bash install.sh`。

## 卸载部署

新架构下卸载也按模块边界执行。顶层入口只负责选择和编排，每个模块通过自己的 `scripts/*/<module>/uninstall.sh` 清理私有配置、服务文件和 metadata，公共层根据存活模块更新定时重启任务和防火墙规则。

交互卸载：

```bash
./scripts/uninstall.sh
```

卸载菜单中的编号按模块目录名字母序排列，当前顺序如下（新增模块后顺延）：

- `0`=卸载全部（含 Edge Gateway）
- `1`=`edge` → `2`=`hysteria2` → `3`=`shadowsocks` → `4`=`wireguard` → `5`=`xray-reality`
- `N+1`=退出

自动化卸载：

```bash
# 卸载全部协议与 Edge Gateway
EASYNET_UNINSTALL_CHOICE=0 ./scripts/uninstall.sh

# 按单个模块卸载
EASYNET_UNINSTALL_MODULE=xray-reality ./scripts/uninstall.sh
EASYNET_UNINSTALL_MODULE=hysteria2 ./scripts/uninstall.sh
EASYNET_UNINSTALL_MODULE=shadowsocks ./scripts/uninstall.sh
EASYNET_UNINSTALL_MODULE=wireguard ./scripts/uninstall.sh
EASYNET_UNINSTALL_MODULE=edge ./scripts/uninstall.sh
```

默认行为：

- 删除 EasyNet 生成的配置、systemd unit、metadata、订阅文件和协议私有证书目录
- 停止并禁用 metadata 中声明的 systemd 服务
- 移除仅由被卸载模块使用、且不是基础端口（SSH / `80/tcp` / `443/tcp`）的 UFW 规则
- 重建订阅文件并刷新 EasyNet 管理的定时重启任务
- 不默认卸载 apt 包；确认依赖只被 EasyNet 使用时，可设置 `EASYNET_UNINSTALL_PURGE_PACKAGES=true`
- 如需保留配置用于迁移或排障，可设置 `EASYNET_UNINSTALL_KEEP_CONFIG=true`

## 验证部署

### 服务状态

```bash
systemctl status xray
systemctl status hysteria-server.service
systemctl status shadowsocks-rust-server
systemctl status awg-quick@wg0
```

### 订阅链接

- Shadowrocket / v2rayN / v2rayNG：以部署输出或 `./scripts/show_subscription.sh` 显示的 URI 订阅为准（`sub` 端点）
- Clash Verge Rev / Mihomo：以部署输出或 `./scripts/show_subscription.sh` 显示的 Clash 订阅为准（`clash` 端点）
- Raspberry Pi / 卡片机 / 无界面 Linux：以部署输出或 `./scripts/show_subscription.sh` 显示的 sing-box 配置为准，推荐 `sing-box 1.14+`

### 其他检查

```bash
sysctl net.ipv4.tcp_congestion_control
./scripts/smoke_test.sh
```

若服务都正常但客户端连不上，先用诊断脚本判断是否 VPS 公网 IP 被 GFW/运营商拦截：

```bash
bash scripts/diagnose_reachability.sh
# 确诊回程丢包（先在客户端拿到公网 IP）：
EASYNET_DIAG_CLIENT_IP=<客户端公网IP> bash scripts/diagnose_reachability.sh
```

`smoke_test.sh` 会读取 metadata，快速检查服务状态、关键端口、防火墙规则和当前订阅入口，适合真实 VPS 部署后做第一轮回归验证。

### 长期运行检查

Edge TLS 证书由 `acme.sh` 自动续期。续期完成后会调用 `scripts/exposure/edge/cert_renew_hook.sh`，该 hook 会自动：

1. 修正 Edge 证书目录和文件权限
2. 动态读取所有已部署模块的 systemd 服务，为各服务用户授予证书读取权限
3. 重启 `nginx` 和所有使用 Edge 证书的协议服务（如 `hysteria-server.service`）

日志方面，部署脚本会限制 journald 使用量（默认 500 MB），并为 Nginx 写入 EasyNet 管理的 logrotate 配置（保留 14 天、每天轮转、压缩）。可定期检查：

```bash
journalctl --disk-usage
du -sh /var/log/nginx
~/.acme.sh/acme.sh --list
openssl x509 -in /etc/ssl/easynet-edge/fullchain.crt -noout -enddate
```

## 安装模式与配置项参照表

### 部署选择机制（三层优先级）

部署入口支持 **三层选择机制**，优先级从高到低，任一设置后不再读取下一级：

| 优先级 | 变量 | 说明 | 可选值 | 默认行为 |
|--------|------|------|--------|---------|
| **最高** | `EASYNET_PROFILE` | 按策略选择协议组合 | `strict` / `balanced` / `compat` | 未设置时退至下一级 |
| **中** | `EASYNET_MODULE` | 按名称部署单个模块 | `xray-reality` / `hysteria2` / `shadowsocks` / `wireguard` | 未设置时退至下一级 |
| **最低** | `EASYNET_SERVICE_CHOICE` | 按编号选择（按安全等级排列） | `0`（全部）/ `1`–`N`（单个）/ `N+1`（退出） | 三者均未设置 → 弹出交互式菜单 |

> 菜单编号由 `scripts/core/discovery.sh` 自动发现协议模块并按 `MODULE_SECURITY_RANK`（安全等级）升序排列。新增模块后编号会按安全等级插入，因此编号不固定。

### 卸载选择机制（独立变量空间）

卸载变量与部署变量完全独立，不会混淆：

| 变量 | 作用 | 可选值 |
|------|------|--------|
| `EASYNET_UNINSTALL_CHOICE` | 按编号选择卸载目标 | `0`（全部）/ `1`–`N`（单个）/ `N+1`（退出）；编号含 Edge Gateway |
| `EASYNET_UNINSTALL_MODULE` | 按名称卸载指定模块 | `xray-reality` / `hysteria2` / `shadowsocks` / `wireguard` / `edge` |
| `EASYNET_UNINSTALL_KEEP_CONFIG` | 保留配置文件（迁移/排障用） | `false`（默认，清理配置） |
| `EASYNET_UNINSTALL_PURGE_PACKAGES` | 同时卸载系统包 | `false`（默认，不卸载系统包） |

### 完整配置项清单

所有配置项通过项目根目录的 `.env` 文件设置，脚本仅加载 `EASYNET_*` 前缀变量。以下按功能分类列出。

#### 自举安装器（`install.sh`）

以下变量仅由 `scripts/install.sh` 读取；未通过安装器部署时可忽略。

| 变量 | 作用 | 默认值 |
|------|------|--------|
| `EASYNET_VERSION` | 指定 release 版本 tag | `latest` |
| `EASYNET_INSTALL_DIR` | 安装目录（解压目标） | `/opt/easynet` |
| `EASYNET_SKIP_SHA256` | 跳过 release 包 SHA256 校验（仅开发，不推荐） | `false` |
| `EASYNET_INSTALL_ONLY` | 只安装不部署（便于先配置 `.env`） | `false` |
| `EASYNET_REPO` | GitHub 仓库名 | `EasyIndie/EasyNet` |
| `EASYNET_RELEASE_BASE_URL` | Releases 基础 URL（镜像/测试用） | `https://github.com/<repo>/releases` |

#### 部署控制

| 变量 | 作用 | 默认值 |
|------|------|--------|
| `EASYNET_SERVICE_CHOICE` | 交互菜单编号选择（`0`=全部 / `1`–`N`=单个 / `N+1`=退出） | 未设置（交互菜单） |
| `EASYNET_MODULE` | 按名称部署单个模块 | 未设置 |
| `EASYNET_PROFILE` | 按策略部署（strict / balanced / compat） | 未设置 |
| `EASYNET_AUTO_ROLLBACK` | 部署前备份 `state/`，失败时自动回滚 | `false` |
| `EASYNET_STRICT_PRECHECK` | 预检失败直接中止，不降级继续 | `false`（预检警告仅提示，不中断） |

#### 域名与 Edge Gateway

| 变量 | 作用 | 默认值 |
|------|------|--------|
| `EASYNET_DOMAIN` | 主域名；Hysteria2 / Edge TLS 要求域名已 A 记录解析到服务器公网 IP | 未设置（不部署 Edge） |
| `EASYNET_SUBSCRIPTION_DOMAIN` | 订阅域名，可与主域名不同 | 同 `EASYNET_DOMAIN` |
| `EASYNET_SUBSCRIPTION_DIRECT_PATHS` | 启用 /sub、/clash、/singbox 直接路径访问订阅（安全性较低） | `false` |
| `EASYNET_SUBSCRIPTION_PATH_PREFIX` | 固定订阅随机路径（重装后订阅 URL 不变，强烈建议设置） | 首次部署随机生成 `/s/<32 位随机十六进制>` |
| `EASYNET_EDGE_HTTP_PORT` | Edge HTTP 端口（acme.sh 证书挑战 + Nginx 伪装站点） | `80` |
| `EASYNET_EDGE_HTTPS_PORT` | Edge HTTPS 端口（订阅 + 协议后端转发） | `443` |
| `EASYNET_EDGE_CERT_DIR` | TLS 证书存放目录 | `/etc/ssl/easynet-edge` |
| `EASYNET_EDGE_CERT_FILE` | TLS 证书文件路径（覆盖 hysteria2 等协议使用的证书路径） | `${EASYNET_EDGE_CERT_DIR}/fullchain.crt` |
| `EASYNET_EDGE_KEY_FILE` | TLS 私钥文件路径 | `${EASYNET_EDGE_CERT_DIR}/private.key` |
| `EASYNET_EDGE_MASQUERADE_URL` | Nginx 根路径反向代理目标（消除 TLS 指纹特征） | `https://www.bing.com` |
| `EASYNET_EDGE_RENEW_HOOK` | 证书续期钩子脚本路径 | `scripts/exposure/edge/cert_renew_hook.sh` |
| `EASYNET_EDGE_STATE_DIR` | Edge Gateway 状态目录（routes、cert 等状态持久化） | `${EASYNET_STATE_DIR}/exposure/edge` |
| `EASYNET_SUBSCRIPTION_SCHEME` | 订阅 URL 协议 | `https` |
| `EASYNET_SUBSCRIPTION_URL_PORT` | 订阅 URL 端口号 | 回退到 Edge 状态文件中的端口（`443`） |
| `EASYNET_SUBSCRIPTION_ROTATION_GRACE` | 订阅轮换时保留旧入口（同 `--grace` 参数） | `false` |
| `EASYNET_SKIP_NGINX_RELOAD` | 订阅轮换或重生成后跳过 Nginx 重载 | `false` |

#### 状态与输出目录

| 变量 | 作用 | 默认值 |
|------|------|--------|
| `EASYNET_STATE_DIR` | 所有 EasyNet 状态数据根目录 | `/var/lib/easynet` |
| `EASYNET_WEB_ROOT` | 订阅文件 Web 根目录 | `/var/www/html` |

#### 通用

| 变量 | 作用 | 默认值 |
|------|------|--------|
| `EASYNET_PUBLIC_IP` | 手动指定公网 IP（覆盖自动检测） | 自动检测 |
| `EASYNET_FLAG` | 节点国家旗帜（ISO 3166-1 alpha-2，Shadowrocket 等显示） | 自动通过 ipinfo.io 推断 |

#### Xray + Reality

| 变量 | 作用 | 默认值 |
|------|------|--------|
| `EASYNET_REALITY_PORT` | Xray 监听端口 | `8443` |
| `EASYNET_REALITY_MODE` | 伪装模式：`auto` / `self`（自偷）/ `borrow`（借用外部站点） | `auto` |
| `EASYNET_REALITY_DEST` | REALITY 目标/伪装服务器地址（仅 `borrow` 模式） | `www.bing.com:443` |
| `EASYNET_REALITY_SERVER_NAME` | 逗号分隔的 SNI 名称列表（仅 `borrow` 模式） | `www.bing.com,www.cloudflare.com` |
| `EASYNET_REALITY_TRANSPORT` | 传输层协议：`tcp` 或 `xhttp`（HTTP/3 伪装，仅 Xray 客户端） | `tcp` |
| `EASYNET_REALITY_XHTTP_MODE` | XHTTP 多路复用模式：`stream-one` / `auto` / `stream-up` / `packet-up` | `stream-one` |
| `EASYNET_REALITY_XMUX_CONCURRENCY` | XMUX 多路复用并发数（`0` = 禁用） | `0` |
| `EASYNET_REALITY_XMUX_CONN_IDLE` | XMUX 空闲连接超时（秒） | `60` |
| `EASYNET_REALITY_LIMIT_FALLBACK_UPLOAD` | 回退上传限速 `afterBytes:bytesPerSec:burstBytesPerSec` | 未设置（禁用） |
| `EASYNET_REALITY_LIMIT_FALLBACK_DOWNLOAD` | 回退下载限速（同上） | 未设置（禁用） |
| `EASYNET_XRAY_VERSION` | 覆盖 Xray 版本（**须同时提供 `EASYNET_XRAY_SHA256`**） | pin 见 `scripts/core/pins.sh`：`26.3.27` |
| `EASYNET_XRAY_SHA256` | 覆盖版本时的发布包 SHA256 | pin 内置，默认自动校验 |
| `EASYNET_ALLOW_UNPINNED` | 设为 `1` 时允许无校验安装未 pin 的版本（不建议） | 未设置（拒绝） |

#### Hysteria2

| 变量 | 作用 | 默认值 |
|------|------|--------|
| `EASYNET_HYSTERIA2_PORT` | Hysteria2 监听端口 | `443` |
| `EASYNET_HYSTERIA2_PASSWORD` | 认证密码 | 随机生成（16 字节 Hex） |
| `EASYNET_HYSTERIA2_OBFS_PASSWORD` | Salamander 混淆密码 | 随机生成（16 字节 Hex） |
| `EASYNET_HYSTERIA2_MASQUERADE_URL` | QUIC 伪装目标 | `https://www.bing.com/` |
| `EASYNET_HYSTERIA2_PORT_HOPPING` | 端口跳变范围（如 `20000-30000`，空则禁用）。服务端改成 `listen: :<基础端口>,<范围>`，由 hysteria 自己建立并回收 nftables 重定向（范围 → 基础端口） | 未设置（禁用） |
| `EASYNET_HYSTERIA2_PORT_HOP_INTERVAL` | 端口跳变间隔 | `30s` |
| `EASYNET_HYSTERIA2_CERT_FILE` | TLS 证书文件路径 | `${EASYNET_EDGE_CERT_DIR}/fullchain.crt` |
| `EASYNET_HYSTERIA2_KEY_FILE` | TLS 私钥文件路径 | `${EASYNET_EDGE_CERT_DIR}/private.key` |
| `EASYNET_HYSTERIA2_VERSION` | 覆盖 Hysteria2 版本（**须同时提供 `EASYNET_HYSTERIA2_SHA256`**） | pin：`2.12.3` |
| `EASYNET_HYSTERIA2_SHA256` | 覆盖版本时的发布物 SHA256 | pin 内置，默认自动校验 |

#### Shadowsocks 2022

| 变量 | 作用 | 默认值 |
|------|------|--------|
| `EASYNET_SHADOWSOCKS_PORT` | ss-server 监听端口 | `8388` |
| `EASYNET_SHADOWSOCKS_VERSION` | 覆盖 shadowsocks-rust 版本（**须同时提供 `EASYNET_SHADOWSOCKS_SHA256`**） | pin：`1.25.0` |
| `EASYNET_SHADOWSOCKS_SHA256` | 覆盖版本时的发布包 SHA256 | pin 内置，默认自动校验 |

#### AmneziaWG

| 变量 | 作用 | 默认值 |
|------|------|--------|
| `EASYNET_WIREGUARD_PORT` | AmneziaWG 监听端口 | `51820` |
| `EASYNET_WIREGUARD_JC` | 垃圾包数量 Jc（1–128） | 随机（4–12） |
| `EASYNET_WIREGUARD_JMIN` | 最小垃圾包大小 Jmin（字节） | `8` |
| `EASYNET_WIREGUARD_JMAX` | 最大垃圾包大小 Jmax（字节） | `80` |
| `EASYNET_WIREGUARD_S1` / `_S2` | 填充大小 S1/S2（15–150） | 随机 |
| `EASYNET_WIREGUARD_H1`–`_H4` | 魔数头（唯一，5–2147483647） | 随机 |
| `EASYNET_WIREGUARD_SERVER_IP` | 服务器 AmneziaWG 子网 | `10.0.0.1/24` |
| `EASYNET_WIREGUARD_CLIENT` | 客户端配置名称 | `client1` |

> AmneziaWG 参数默认随机生成并持久化在 `/etc/amnezia/amneziawg/wg0.conf`；
> Jc/Jmin/Jmax 可两端不同，S1/S2/H1-H4 必须两端一致（订阅会自动携带）。

#### 安全校验

| 变量 | 作用 | 默认值 |
|------|------|--------|
| `EASYNET_ACME_VERSION` | 覆盖 acme.sh 版本（**须同时提供 `EASYNET_ACME_SHA256`**） | pin：`3.1.6` |
| `EASYNET_ACME_SHA256` | 覆盖版本时 `get.acme.sh` 的 SHA256 | pin 内置，默认自动校验 |

#### 系统维护

| 变量 | 作用 | 默认值 |
|------|------|--------|
| `EASYNET_JOURNALD_MAX_USE` | systemd journald 磁盘使用上限 | `500M` |
| `EASYNET_NGINX_LOGROTATE_FILE` | Nginx logrotate 配置文件路径 | `/etc/logrotate.d/easynet-nginx` |

### 默认部署行为

当 **不设置任何环境变量** 直接运行 `./scripts/deploy.sh` 时，系统按以下默认逻辑执行：

1. **交互菜单** — 显示协议列表（按安全等级 `MODULE_SECURITY_RANK` 升序排列），等待用户手动选择
2. **Edge 网关不部署** — `EASYNET_DOMAIN` 未设，Edge（Nginx + acme.sh TLS + 订阅托管）跳过
3. **基础环境初始化** — 系统更新 → 安装基础依赖（curl、wget、git、unzip、jq 等）→ 启用 BBR → 配置 UFW（自动开放 `22/tcp`、`80/tcp`、`443/tcp` + 各已部署协议 metadata 中声明的端口）→ 配置 `unattended-upgrades` 自动安全更新 → 写入 cron（日志维护 + 每日 4:00 各已部署协议服务重启）
4. **预检温和模式** — 工具缺失、端口冲突、DNS 未解析等问题仅告警，不中止部署；设 `EASYNET_STRICT_PRECHECK=true` 可转为中止
5. **无回滚保护** — `EASYNET_AUTO_ROLLBACK` 默认关闭，失败不会自动恢复
6. **随机安全凭证** — Hysteria2 密码、混淆密码、订阅路径前缀均由系统自动随机生成，无需手动指定
7. **订阅仅限本地** — 未配置域名时不生成外部可访问的订阅链接；配置域名后自动全量输出 URI、Clash/Mihomo、sing-box 三类订阅
8. **多轮部署** — 部署完选择的模块后不直接退出，而是回到菜单等待下一步操作；使用环境变量自动化部署则执行一次后自动退出

## 需要时再看

- 客户端导入与平台差异：[客户端说明](./clients.md)
- 出现故障时：[故障排查指南](./troubleshooting-guide.md)

## sing-box 分流规则集

`/singbox` 订阅默认自带分流规则（私有网段直连、CN 域名/IP 直连、广告拒绝，其余仍走代理）。
规则集是 edge 上的静态文件，由下面的脚本从官方数据库生成：

```bash
./scripts/generate_singbox_rules.sh              # 生成并发布到 ${EASYNET_WEB_ROOT}/rules/
./scripts/generate_singbox_rules.sh --dry-run    # 只打印不写文件
```

> ⚠️ **未发布规则集时 `/singbox` 订阅无法启动**：订阅里 `route.rule_set` 用 `remote` 指向这些
> `.srs` 文件，拉不到（404）会让 sing-box 直接启动失败。部署后至少跑一次上面的脚本。

- 类别清单：`scripts/core/singbox-rules.conf`（`tag|source|category|action`，加类别只改一行）；
- 生成物：`rules/<tag>.srs` 与 `rules/manifest.json`（含每个文件的 sha256）——属构建产物，**不进版本库**；
- 订阅里 `route.rule_set` 用 `remote` 指向这些文件；**客户端安装器会下载到本地并改写为 `local`**
  （远程规则集启动时拉不到会让 sing-box 起不来），因此客户端启动不依赖网络；
- 建议每周跑一次（官方 geosite 每天更新）。客户端每天更新时会按 `manifest.json` 的 sha256
  判断是否需要重新下载，只有真的变化才重启 sing-box。

