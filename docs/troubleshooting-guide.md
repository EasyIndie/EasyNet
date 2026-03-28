# EasyNet 代理服务器部署与故障排查指南

本文档总结了在部署 EasyNet（包含 Trojan-Go、V2Ray、Shadowsocks、WireGuard、Xray+Reality 五种协议）过程中遇到的常见问题、排查思路及修复方案。旨在帮助新手在遇到连接失败或部署报错时，能够快速定位并解决问题。

---

## 一、 通用排查方法论（新手必读）

当遇到“代理连不上”时，请按照以下标准顺序进行排查：

1. **查服务状态**：`systemctl status <服务名>` (如 `trojan-go`, `wg-quick@wg0`)，看是否显示 `active (running)`。如果有报错，看最后几行提示。
2. **查详细日志**：`journalctl -u <服务名> -n 50 --no-pager`，查看程序内部的具体错误原因（如配置格式错、端口冲突）。
3. **查端口监听**：
   - TCP 协议 (Trojan/SS/V2Ray等)：`netstat -tlnp | grep <端口号>`
   - UDP 协议 (WireGuard)：`netstat -ulnp | grep <端口号>`
   确认服务是否监听在 `0.0.0.0` 或 `::`（如果是 `127.0.0.1` 则外网无法访问）。
4. **查防火墙规则**：`ufw status`，确认对应端口的 TCP/UDP 规则是否已放行。
5. **查网络连通性**：
   - TCP：在本地电脑使用 `telnet <服务器IP> <端口>`。
   - UDP：在服务器运行 `nc -l -u -p <端口>`，本地运行 `nc -u <服务器IP> <端口>` 发送字符测试。

---

## 二、 基础环境与依赖问题

### 1. 申请 SSL 证书失败 (ACME.sh 报错)
* **现象**：提示 `tcp port 80 is already used by nginx` 或 `Please stop it first`。
* **原因**：ACME.sh 使用 Standalone 模式申请证书时需要占用 80 端口，但系统中 Nginx 已在运行并占用了该端口。
* **修复**：在执行 `acme.sh --issue` 前临时停止 Nginx (`systemctl stop nginx`)，申请完成后再启动。

### 2. ACME.sh 提示需要注册 ZeroSSL 邮箱
* **现象**：提示 `Please update your account with an email address first.`
* **原因**：ACME.sh 默认 CA 变成了 ZeroSSL，需要绑定邮箱（EAB）。
* **修复**：强制将默认 CA 切换为 Let's Encrypt：`acme.sh --set-default-ca --server letsencrypt`。

### 3. 多协议部署后部分协议突然失效
* **现象**：先部署了 Trojan-Go，再部署 Shadowsocks 后，Trojan-Go 连不上了。
* **原因**：早期部署脚本中使用了 `ufw --force reset`，导致每次部署新协议都会清空之前放行的端口规则。
* **修复**：移除防火墙重置命令，直接追加 `ufw allow <端口>`。

---

## 三、 协议运行与客户端配置问题

### 1. 客户端扫码后提示 "无效的配置 URL"
* **现象**：Shadowrocket 扫描二维码后无法识别，或解析出的密码带有特殊字符。
* **原因**：旧版本脚本曾使用 Base64 生成密码（包含 `+`, `/`, `=`），在拼接成 `trojan://` 或 `ss://` URI 时会破坏 URL 结构。
* **现状**：当前脚本已统一使用十六进制密码生成（`openssl rand -hex 16`），新部署不再出现该问题。

### 2. 终端生成的二维码过大，无法完整扫描
* **现象**：终端生成的二维码超出屏幕，需要滚动才能看完，手机无法扫描。
* **原因**：`qrencode` 使用 `ansiutf8` 或默认格式时，二维码区块过大。
* **现状**：脚本已统一使用 `qrencode -t utf8` 输出，正常情况下可直接扫描。
* **修复**：如仍过大，请确认没有手动使用 `ansiutf8`，并优先使用订阅二维码导入。

### 3. Trojan-Go 启动失败 (unknown proxy type)
* **现象**：`systemctl status trojan-go` 显示失败，日志中出现 `unknown proxy type`。
* **原因**：Trojan-Go 无法识别 YAML 格式的配置文件，它严格依赖标准的 JSON 格式。
* **修复**：将配置文件由 `.yaml` 重写为规范的 `config.json`，并确保所有键值对格式正确。

### 4. Shadowsocks 连接超时 (端口绑定错误)
* **现象**：服务运行正常，防火墙已开，但客户端测速超时。`netstat` 显示 8388 端口绑定在 `127.0.0.1`。
* **原因**：Ubuntu 安装 `shadowsocks-libev` 时会启动一个系统默认的后台服务，占用了端口并绑定在本地回环地址，导致我们自己写的 Systemd 服务无法正确监听公网。
* **修复**：停用并禁用系统默认服务 `systemctl disable --now shadowsocks-libev`，并在启动命令中明确指定监听所有网卡 `-s 0.0.0.0`。

### 5. Trojan-Go 开启复用时 V2Ray 等后端服务连通性正常但无法上网
* **现象**：将 V2Ray 作为 Trojan-Go 的后端（路径为随机值），客户端测试连通性通过，但无法访问网页。查看 `journalctl -u trojan-go` 发现日志提示 `not a valid websocket handshake request` 并且回落到了 80 端口（Nginx）。
* **原因**：Trojan-Go 只接受自身的 WebSocket 路径。若请求路径不是当前 Trojan 路径，就会触发回落到 Nginx。此时若 V2Ray 的请求路径与 Nginx 的反代路径不一致，流量无法进入 V2Ray 后端。
* **修复**：以 Nginx 为分发中心：Trojan-Go 将非自身路径的流量回落到 80 端口，Nginx 按实际 V2Ray 路径反向代理到 `127.0.0.1:4443`。确保 V2Ray 路径与 Nginx 配置一致。
* **提示**：路径由脚本随机生成并落盘：
  - Trojan 路径：`/etc/trojan-go/trojan_path.txt`
  - V2Ray 路径：`/etc/trojan-go/v2ray_path.txt`

### 6. Xray/V2Ray 等协议恢复部署后客户端变量为空或服务启动失败
* **现象**：在使用同一台机器重新部署（恢复模式）时，终端输出的客户端配置中 UUID、Short ID 或路径为空，或者服务启动直接报错。
* **原因**：之前的部署脚本使用 `grep` 或 `sed` 基于正则表达式来提取或修改 JSON 文件。由于 JSON 存在格式化（如多行数组）、缺省字段等不确定性，正则匹配极易失效，导致读取到空值并写入配置，进而引发致命的空指针或端口绑定失败（如 `ERROR: Bad port`）。
* **修复**：全面废弃了 `grep/sed` 操作 JSON 的逻辑，引入了专业的 JSON 处理工具 `jq`。现在所有配置的读写都通过 `jq` 进行结构化解析（如 `jq -r '.inbounds[0].port'`）。此外，针对异常的空值或存在安全隐患的默认值（如 `/trojan`），脚本加入了**自我修复机制**，会自动重新生成安全的随机值并覆写配置文件，彻底解决了由于脏数据导致的服务启动崩溃。

### 7. V2Ray 在 Nginx 代理后出现 TLS SNI Mismatch 或无域名
* **现象**：V2Ray 客户端连通性测试通过，但无法访问网站。查看 Trojan-Go 或 Nginx 日志发现请求的 SNI 缺失或变成了 IP 地址，进而被拒绝握手。
* **原因**：由于 Bash 脚本执行过程中的变量作用域丢失，或者之前生成的配置结构缺失，导致 V2Ray 在构建客户端连接 URL (`vmess://`) 时，未正确写入域名（`host` 和 `sni` 字段为空或回退成了 IP）。Trojan-Go 具有严格的防探测机制，遇到未携带正确域名的 SNI 握手会直接拦截。
* **修复**：修改 `v2ray.sh` 脚本，在构建最终配置前加入强制结构化校验：使用 `jq` 重新提取文件中的真实域名。如果发现 `DOMAIN` 为空或无效，将主动阻断部署流程并报错，杜绝生成携带错误 IP 的无效客户端链接。同时我们添加了单元测试套件，用以在后续重构中持续保护这些核心的生成逻辑。

---

## 四、 WireGuard 专属排查指南（核心难点）

WireGuard (WG) 基于 UDP 且是无状态的，排查难度最高。

### 1. WG 客户端连接超时，服务器无 `latest handshake`
* **现象**：客户端开启代理后无法上网，服务端运行 `wg show` 看不到 `latest handshake`（最新握手时间）。
* **原因（核心踩坑点）**：重新运行部署脚本生成了**新的密钥对**并写入配置文件，但在应用配置时，脚本使用的是 `systemctl start wg-quick@wg0`。由于服务已经在运行，`start` 命令**不会重载配置**。这导致服务端仍在内存中使用**旧公钥**，而客户端拿着**新公钥**来握手，被服务端直接丢弃。
* **修复**：将脚本中的服务启动命令改为 `systemctl restart wg-quick@wg0`，确保每次部署都强制加载最新密钥。

### 2. WG 握手成功，但无法访问互联网 (路由与转发问题)
* **现象**：`wg show` 有 `latest handshake`，但依然上不了网。
* **原因一（网卡名称错误）**：iptables 的 NAT 转发规则中硬编码了 `eth0`，但实际 VPS 的公网网卡可能是 `enp1s0`。
  * **修复**：在脚本中动态获取主网卡：`DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)`。
* **原因二（UFW 拦截转发）**：UFW 默认的路由转发策略是 `DROP`，早期排查时曾修改为 `ACCEPT`，但为了安全性，现已恢复为 `DROP`。如果 iptables 规则优先级不够，依然会被拦截。
  * **修复**：在 `wireguard.sh` 中，我们利用 `PostUp` 钩子，将 iptables 规则从 `-A`（追加到末尾）改为了 `-I`（插入到最前面）：`iptables -I FORWARD -i wg0 -j ACCEPT`。这样就能在不修改 UFW 全局默认策略（保持 DROP）的前提下，精确放行 WireGuard 的流量，兼顾了连通性与安全性。

### 3. Shadowrocket 中 WireGuard 测速不显示延迟 (ms)
* **现象**：可以正常打开网页，但在 Shadowrocket 中点击连通性测试，不显示毫秒数，或者显示超时。
* **原因**：WireGuard 是无状态的 UDP 三层隧道协议。Shadowrocket 的连通性测试默认使用基于 TCP 的 HTTP HEAD 请求，这种探测方式不适用于 WireGuard 的底层特性。
* **结论**：**这是正常现象**。只要浏览器能打开网页，或者服务端 `wg show` 显示 `transfer` 数据在增长，就说明代理运行完美。可以使用 Speedtest 或本地 Ping 工具进行实际延迟测试。

---

### 4. 订阅二维码与单节点二维码混淆
* **现象**：扫描二维码后只导入一个节点，或者订阅没有出现。
* **原因**：终端输出既有单节点二维码（`trojan://`、`vmess://`、`wg://`），也有订阅二维码（`https://your-domain/sub`、`https://your-domain/sub_full`），两者用途不同。
* **修复**：批量导入优先扫描订阅二维码；只需单节点时再扫描协议二维码。

> **总结：**
> 部署代理服务是一个涉及 **进程管理 -> 网络监听 -> 密码学握手 -> 防火墙放行 -> 流量路由转发** 的全链路工程。任何一个环节断裂都会导致“连不上”。掌握 `systemctl status`、`journalctl`、`netstat` 和 `wg show` 这四大法宝，就能精准定位 99% 的问题！
