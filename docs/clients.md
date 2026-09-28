# EasyNet 客户端说明

## 推荐组合

| 平台 | 推荐客户端 | 说明 |
|------|------------|------|
| Windows / macOS | Clash Verge Rev / Mihomo | 适合日常使用，优先导入订阅 |
| Linux | Clash Verge Rev / Mihomo | 适合桌面 Linux 日常使用，优先导入订阅 |
| Android | Clash Meta for Android | 适合订阅导入和规则分流 |
| iOS | Shadowrocket | 适合订阅导入 |
| Raspberry Pi / 卡片机 | sing-box | 适合作为低资源无界面常驻客户端，直接使用 sing-box 配置 |

## 优先使用订阅导入

部署完成后终端会打印三组订阅链接（URI / Clash / sing-box）。Edge Gateway 使用首次部署时生成的稳定随机路径承载订阅。

忘记链接时，在项目目录运行 `./scripts/show_subscription.sh`；怀疑泄露时运行 `./scripts/rotate_subscription.sh`（`--grace` 可临时保留旧入口供多设备迁移）。

使用建议：
- `Clash Verge Rev` / `Mihomo` 使用 `clash` 端点
- `Shadowrocket` / `v2rayN` / `v2rayNG` 使用 `sub`
- `sing-box` 使用 `singbox`

## 各平台最短导入步骤

### Windows / macOS / Linux

- 客户端：[Clash Verge Rev / Mihomo](https://github.com/clash-verge-rev/clash-verge-rev/releases)
- 步骤：打开客户端 → 导入 Clash 订阅 → 更新配置 → 启用系统代理或 TUN

### Android

- 客户端：[Clash Meta for Android](https://github.com/MetaCubeX/ClashMetaForAndroid/releases)
- 步骤：配置 → 新配置 → URL 导入 → 粘贴 Clash 订阅 → 更新 → 启动

### iOS

- 客户端：Shadowrocket
- 步骤：右上角 `+` → 类型选 `Subscribe` → 粘贴 URI 订阅 → 保存 → 启动

### Raspberry Pi / 卡片机

树莓、软路由、卡片机建议使用 `sing-box`（要求 **1.14+**：订阅使用 1.14 引入的 `http_clients` / `route.default_http_client` 下载远端规则集）。

**安装：** 在服务端运行 `./scripts/show_subscription.sh`，复制输出中的”树莓派快速安装”两行命令，到树莓派上执行：

```bash
curl -fsSL “https://your-domain/s/<random>/singbox-client.sh” -o easynet-singbox-client.sh
sudo bash easynet-singbox-client.sh --config-url “https://your-domain/s/<random>/singbox”
```

默认是 `mixed` 模式（监听 `7890` 代理端口）。如需本机全局代理，安装时加 `--mode tun`：

模式说明：

| 模式 | 行为 | 适用场景 |
|------|------|----------|
| `mixed` | 监听 `7890` HTTP/SOCKS 代理端口 | 其它设备手动配置代理到树莓派 |
| `tun` | 接管树莓派本机流量 | 树莓派自己全局走代理 |

常用命令：`start` / `stop` / `restart` / `status` / `doctor` / `update`

```bash
sudo bash easynet-singbox-client.sh <命令>
```

- `status` — 先打印当前模式，再显示 systemd 状态
- `doctor` — 自动诊断模式、入站配置、服务状态和代理连通性（探测地址 `https://www.gstatic.com/generate_204`，可通过 `EASYNET_SINGBOX_PROBE_URL` 覆盖）

切换模式（`tun` / `mixed`）：

```bash
sudo bash easynet-singbox-client.sh switch-mode tun
sudo bash easynet-singbox-client.sh switch-mode mixed
```

切换时自动按”停止 → 写入新配置 → 启动”顺序执行，失败时恢复原模式。
`tun` 模式只接管本机流量，不透明转发局域网设备。

## 验证连接

优先运行：

```bash
sudo bash easynet-singbox-client.sh doctor
```

如果结论为代理正常，再按需打开网页或访问出口 IP 查询网站确认出口位置。

## 协议客户端兼容性

| 协议特性 | 最低客户端要求 |
|----------|--------------|
| Shadowsocks 2022 (BLAKE3) | Clash Verge Rev ≥1.6, Shadowrocket ≥2.2.38, sing-box ≥1.8 |
| Xray XHTTP 传输 | Clash Verge Rev ≥1.7, sing-box ≥1.11 |
| Hysteria2 Port Hopping | 需客户端支持 `port_hopping` 参数 |
| AmneziaWG | Clash Verge Rev (mihomo ≥1.19，支持 jc/jmin/jmax/s1/s2/h1-h4)、Shadowrocket；**sing-box 未支持 AmneziaWG，故不会出现在 sing-box 订阅中** |

## 常见问题

### 订阅更新超时 / 导入失败

- 先确认客户端**没有用代理去更新订阅**（Shadowrocket 先断开 VPN，或把“全局路由”设为直连，再更新）
- 用浏览器直接打开 `https://<域名>/sub` 验证；若同样超时，多半是服务器 IP 被墙，见[故障排查指南](./troubleshooting-guide.md)中的《服务器 IP 被 GFW/运营商拦截》
- 域名刚换过 IP 时，刷新客户端 DNS（切飞行模式/重开 App）

### Clash Verge Rev 导入失败

- 你可能导入了 URI 订阅 `sub`，Clash/Mihomo 应使用 `clash`
- 检查协议兼容性：XHTTP 传输需 Clash Verge Rev ≥1.7

### sing-box 启动失败

- 先运行 `/usr/local/bin/sing-box check -c /etc/sing-box/config.json`
- 确认使用的是 `singbox` 配置链接；要求 sing-box **≥1.14**（订阅使用 `http_clients`）
- Shadowsocks 2022 节点需 sing-box ≥1.8
- 如报 `initial rule-set: ... unexpected status: 404`，说明服务端还没发布规则集：在服务器运行 `./scripts/generate_singbox_rules.sh`（远端规则集拉不到会让 sing-box 直接启动失败）
- 如看到 `legacy inbound fields are deprecated`，先在服务端重新运行 `./scripts/generate_subscription.sh`，再在树莓派执行 `/usr/local/bin/easynet-singbox-update`

### mixed 模式无法连接 7890

- 先运行自动诊断：`sudo bash easynet-singbox-client.sh doctor`
- 如果当前是 `tun`，切回 mixed：`sudo bash easynet-singbox-client.sh switch-mode mixed`
- 如果诊断结论显示服务未运行或端口未监听，按输出中的服务状态和日志继续处理
- 修复后再测试：`curl -x socks5h://127.0.0.1:7890 https://www.google.com -I`

### tun 模式无法访问域名

- 先确认 mixed 模式可用：`curl -x socks5h://127.0.0.1:7890 https://www.google.com -I`
- 切换到 tun 并重新生成配置：`sudo bash easynet-singbox-client.sh switch-mode tun`
- 运行自动诊断：`sudo bash easynet-singbox-client.sh doctor`
- 如果诊断结论显示连通性失败，确认配置中存在 `tun-in`、`hijack-dns`、`dns.servers` 和 `route.default_domain_resolver`
- 如看到 `missing route.default_domain_resolver`，先在服务端重新运行 `./scripts/generate_subscription.sh` 并重新下载客户端脚本
- 再测试：`curl https://www.google.com -I`

### 完整节点没有出现

- 确认使用的是当前部署输出或 `./scripts/show_subscription.sh` 显示的订阅入口
- 确认服务器已成功运行 `./scripts/generate_subscription.sh`

### AmneziaWG 节点无法连接

- 服务端固定使用 AmneziaWG（`awg-quick@wg0`），混淆参数（Jc/Jmin/Jmax/S1/S2/H1-H4）在部署时随机生成并写入订阅
- 客户端需支持 AmneziaWG：Clash Verge Rev (mihomo ≥1.19) 或 Shadowrocket；**sing-box 未支持 AmneziaWG**（其 WireGuard endpoint 不认 `jc/jmin/...`），因此该节点**不会出现在 `singbox` 订阅里**（selector/urltest 也不包含）
- 确订订阅已更新（参数必须与服务端一致）并重新导入节点；手动配置时需与服务端 `/etc/amnezia/amneziawg/wg0.conf` 对齐
- 如客户端不支持 AmneziaWG，请改用其他节点（Reality / Hysteria2 / Shadowsocks）

### Hysteria2 端口跳变后无法连接

- 确认客户端支持 port hopping 参数

## 端口跳跃的客户端方言（易错点）

`PORT_HOPPING` 相关字段在三个客户端是**三种不同写法**，元数据里存中立方言，渲染时各自转换：

| 客户端 | 范围字段 | 间隔字段 | 间隔值的类型 |
|--------|----------|----------|--------------|
| sing-box | `server_ports: ["20000:30000"]` | `hop_interval` | **时长字符串** `"30s"` |
| mihomo / Clash Verge / Clash Meta | `ports: "20000-30000"` | `hop-interval` | **整数秒** `30` |
| Shadowrocket（URI） | URI 查询参数 `porthopping=20000-30000` | `porthopping-interval` | 未验证（无真机） |

> ⚠️ **把 `"30s"` 写给 mihomo 会让整份订阅导入失败**：mihomo 的 `hop-interval` 是整数秒字段，
> 它会把 `30s` 拿去当**端口范围**解析，报出极易误判的
> `proxy 1: invalid range: 30s`（Clash Verge 真实报错）。
> `scripts/protocols/hysteria2/render_clash.sh` 会用 `mihomo_hop_interval_seconds()`
> 把 `30s→30`、`1m→60`，无法识别的值直接省略该字段（用客户端默认值），绝不写非法值。
>
> 新增/修改任何客户端渲染字段时，请用真二进制校验（`mihomo -t -f <config>`、
> `sing-box check -c <config>`），不要只做字符串断言：本仓库的验收脚本
> （`~/Desktop/easynet-acceptance/reset-acceptance.sh`）已内置这两条检查。

- 确认云厂商安全组和服务器防火墙已放行跳变端口范围（如 20000-30000/udp）

### 分流规则没生效

1. 看配置里有没有规则：

   ```bash
   jq '.route.rule_set, (.route.rules | length)' /etc/sing-box/config.json
   ```

   期望：`rule_set` 是若干 `{"type":"local", ... "path":"/etc/sing-box/rules/<tag>.srs"}`，
   `route.rules` 里有 sniff、`ip_is_private` 直连以及引用规则集的几条。

2. 看规则集文件与新不新：

   ```bash
   ls -l /etc/sing-box/rules/
   jq '.generated_at, (.files[] | {tag, size})' /etc/sing-box/rules/.manifest.json
   ```

3. 看服务是不是在更新后重启过（**老版本只在文件层面更新、不重启，规则不会生效**）：

   ```bash
   systemctl status easynet-singbox.service
   sudo bash /etc/easynet/easynet-singbox-client.sh update   # 手动触发一次"更新+重启"
   ```

4. 验证分流是否真的生效（出口 IP 对比）：
   - 经代理访问国内站点，出口应等于本机直连出口；
   - 经代理访问国外站点，出口应等于代理服务器 IP。

## 客户端配置的发布前校验（真二进制）

我们生成的订阅是**文本**，字段名/类型/单位写错时字符串断言看不出来 —— 必须由真实客户端判定。
`scripts/client_check.sh` 负责这件事（CI 与验收都用它）：

```bash
scripts/client_check.sh platform                 # 当前平台与 pin 可用性
scripts/client_check.sh fetch mihomo             # 按 pin 下载 + SHA256 校验（缓存到 ~/.cache/easynet/client-bin）
scripts/client_check.sh check-clash  /path/clash.yaml
scripts/client_check.sh check-singbox /path/singbox.json
```

- 版本固定在 `scripts/core/pins.sh` 的 `EASYNET_PIN_MIHOMO_*` / `EASYNET_PIN_SINGBOX_*`
  （Linux/amd64、Linux/arm64、Darwin/amd64 三个平台；缓存里的资产每次使用前都会重新校验 SHA256）。
- CI 有独立 job `client-config-validation`，并作为 **release 的前置依赖**：真客户端拒收就发不出 release。
  该 job 设 `EASYNET_REQUIRE_CLIENT_CHECK=1`，拉不到二进制即失败（不允许静默通过）。
- 测试自带"校验器有效性"哨兵：故意写出 `hop-interval: "30s"`（0.0.13 事故形态）必须被 mihomo 拒绝，
  否则说明校验形同虚设。

### 客户端安装器的版本固定

`scripts/clients/install_singbox_client.sh`（端点设备上执行）也按 pin 安装 sing-box：

| 变量 | 作用 |
|------|------|
| `EASYNET_SINGBOX_VERSION` | 覆盖版本（**必须**同时给 `EASYNET_SINGBOX_INSTALL_SHA256`） |
| `EASYNET_SINGBOX_INSTALL_SHA256` | 覆盖版本时的校验和 |
| `EASYNET_SINGBOX_SKIP_SHA256=true` | 显式跳过校验（自行承担风险） |

内联常量与 `core/pins.sh` 的一致性由 `tests/test_singbox_client_installer.bats` 断言（防漂移）。

## 设备恢复手册（代理失效时怎么救回来）

设备（树莓派、软路由、旧机）最常见的失效场景是：**服务端换了凭据/地址，而设备拉不到新配置**。
此时设备往往还在"旧配置能启动、但连不通"的状态，而它又**无法直连 GitHub 下载 sing-box 自救**
（实测国内访问 GitHub release 会卡死：90 秒 0 字节后 `curl: (18)`）。

我们的做法：**服务端把 pinned 的 sing-box 也发布到订阅站**，设备只依赖"域名可达"即可自愈。

### 服务端：发布镜像

```bash
easynet clients            # 发布/刷新（每日部署时也会自动做一次，best-effort）
easynet clients status     # 查看各平台是否就绪
```

发布内容（`/var/www/html/bin/`，通过随机前缀暴露）：

```
bin/sing-box-<版本>-linux-arm64.tar.gz        + .sha256
bin/sing-box-<版本>-linux-amd64.tar.gz        + .sha256
bin/manifest.json                             （版本 + 各平台 SHA256/大小）
```

设备侧地址即 `${订阅前缀}/bin/<asset>`，例如
`https://<域名>/s/<前缀>/bin/sing-box-1.14.2-linux-arm64.tar.gz`。

### 设备端：正常恢复（推荐）

```bash
# 1) 取最新安装器（它优先从订阅站下载 sing-box，GitHub 兜底）
curl -fsSL "https://<域名>/s/<前缀>/singbox-client.sh" -o /tmp/isb.sh
# 2) 重装：会自动校验 SHA256、写新订阅地址、修好 systemd unit
sudo bash /tmp/isb.sh --config-url "https://<域名>/s/<前缀>/singbox"
```

每日更新服务（`easynet-singbox-update.timer`）现在也会顺带**对齐 sing-box 版本**：
以订阅站的 `bin/manifest.json` 为准（安装时写入 env 的 pin 作为回落），版本不一致时从订阅站取包、
用 manifest 里的 SHA256 校验后替换并重启 —— 所以服务端升级 pin 后，设备会在一天内自动跟上。

### 设备端：手工兜底（订阅站也拿不到时）

```bash
# 在能上网的机器上下载官方包，核对 pin 哈希后 scp 到设备
sha256sum sing-box-1.14.2-linux-arm64.tar.gz     # 见 scripts/core/pins.sh 的 EASYNET_PIN_SINGBOX_*
sudo EASYNET_SINGBOX_DOWNLOAD_URL=file:///tmp/sing-box-1.14.2-linux-arm64.tar.gz \
     EASYNET_SINGBOX_INSTALL_SHA256=<pin 哈希> \
  bash /tmp/isb.sh --config-url "https://<域名>/s/<前缀>/singbox"
```

> 相关开关：`EASYNET_PUBLISH_CLIENT_BINARIES=false`（服务端不发布镜像）、
> `EASYNET_SINGBOX_MIRROR=false`（设备端只用 GitHub）。

