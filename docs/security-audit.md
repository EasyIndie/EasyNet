# EasyNet 安全审计报告

> **最后更新**: 2026-06-27
> **审计范围**: 全部 Shell 脚本、协议实现、系统配置
> **漏洞报告**: 参见项目根目录 [SECURITY.md](../SECURITY.md)

---

## 一、协议抗DPI能力评估

### 1.1 排名（抗DPI从高到低）

| 排名 | 协议 | Security Rank | 加密 | 传输伪装 | 2026年状态 |
|:--:|------|:--:|------|------|------|
| 1 | Xray+Reality | 10 | REALITY TLS (x25519) | TLS证书窃取 + uTLS指纹 + 主动探测免疫 | ⚠️ 见1.2 |
| 2 | Hysteria2 | 20 | TLS 1.3 + Salamander混淆 | QUIC/HTTP3伪装 + 端口跳跃 | 稳定 |
| 3 | Shadowsocks 2022 | 40 | 2022-blake3-aes-256-gcm | 无传输层伪装 | 降级为备用 |
| 4 | WireGuard | 60 | ChaCha20-Poly1305 + x25519 | AmneziaWG混淆（仅客户端） | 非抗封锁 |

### 1.2 Reality 被运营商拦截 — 已知原因与修复

2026年DPI已能通过以下向量检测配置不当的Reality部署：

| 检测向量 | 根因 | 修复 |
|------|------|------|
| **uTLS CVE-2026-26995/27017** | uTLS < v1.8.1 缺少Padding扩展和ECH/GREASE一致性 | 升级 Xray-core ≥ v26.3.27（捆绑 uTLS v1.8.2+） |
| **缺少PQ密钥共享** | 声称fp=chrome但ClientHello中无X25519MLKEM768 → 被ML分类器标记 | 使用包含PQ profile的uTLS指纹 |
| **IP+SNI ASN不匹配** | 伪装目标域名ASN ≠ VPS IP的ASN | 设置 `EASYNET_REALITY_DEST` 为同机房邻居域名 |
| **伪装目标过度共享** | 大量实例共用 `www.microsoft.com` | 已更换默认值为 `www.bing.com` |
| **端口选择** | 443被深度检测，非标端口触发异常审视 | 高端口（47000+）实测恢复80%吞吐 |
| **未启用Finalmask** | 未使用fragment/noise/Sudoku混淆 | 建议启用（需确认版本兼容性） |

已实施的修复详见 `scripts/protocols/xray-reality/deploy.sh`（新增 `EASYNET_REALITY_FINGERPRINT`、`EASYNET_REALITY_MAX_TIME_DIFF`、伪装域名默认值更换）。

### 1.3 2026年新兴协议

| 协议 | 类型 | 成熟度 | 建议 |
|------|------|:--:|------|
| **Restls** | TLS完美模仿（HMAC双向认证） | 新兴 | 🔍 关注 |
| **MASQUE/HTTP3-Dialer** | IETF标准QUIC隧道 | 成长中 | 🔍 关注 |
| **TUIC v5** | QUIC低延迟 | 成熟 | ✅ 可考虑加入 |
| **Rosenpass** | WireGuard后量子安全 | 活跃开发 | 🔍 关注 |

---

## 二、实现层安全

### 2.1 供应链安全

| 问题 | 严重性 | 状态 |
|------|:--:|:--:|
| sing-box 通过 GitHub API "latest" 下载，无 SHA256 校验 | 🔴 CRITICAL | 已添加 `EASYNET_SINGBOX_INSTALL_SHA256` 可选校验 |
| 所有外部安装脚本 SHA256 默认跳过（`EASYNET_*_INSTALL_SHA256` 为空时） | 🟡 MEDIUM | `deploy.sh` 新增空值警告；推荐用户设置 |
| Xray-install URL 指向 `raw/main/`（非固定版本） | 🟡 MEDIUM | `EASYNET_XRAY_VERSION` 锁定为 `26.3.27` |

### 2.2 凭据保护

| 问题 | 严重性 | 状态 |
|------|:--:|:--:|
| 配置文件权限 `chmod 600` | ✅ | 所有 `config.json` 已设置 |
| metadata.json 权限 `chmod 600` | ✅ | 统一由 `metadata_write()` 执行 |
| 私钥嵌入 WireGuard URI 参数 | 🟠 HIGH | 已知设计妥协，`wg://` 格式约定；部署时显示警告 |
| Hysteria2 密码升级至 256 位 | ✅ | `random_secret()` 已改为 `openssl rand -hex 32` |

### 2.3 服务加固

| 问题 | 状态 |
|------|------|
| Shadowsocks systemd: `User=nobody`, `ProtectSystem=full`, `NoNewPrivileges=yes` | ✅ 已加固 |
| Hysteria2/Xray 服务: 依赖上游安装脚本生成 | ⚠️ 不可控 |
| sing-box 客户端: `mixed` 模式仍以 root 运行 | 🟡 建议添加 `DynamicUser=yes` |
| WireGuard: 需要 `CAP_NET_ADMIN`，以 root 运行 | ⚠️ 协议限制 |

### 2.4 TLS 与 Web 安全

| 问题 | 状态 |
|------|------|
| Nginx 缺少显式 `ssl_ciphers`、HSTS、OCSP Stapling | 🟠 待修复 |
| 订阅文件仅靠 128 位随机路径保护，无第二层认证 | 🟡 建议添加 Basic Auth |
| 公网 IP 检测使用 HTTP（可被MITM注入） | 🔵 建议改用 HTTPS |

### 2.5 输入验证

| 问题 | 状态 |
|------|------|
| 域名输入仅判空，无格式校验 | 🟡 建议添加正则验证 |
| JSON 通过字符串拼接构建（部分旧代码） | 🟡 已迁移至 `jq --arg` |
| 备份文件使用 `/tmp` + `date +%s`（TOCTOU风险） | 🟡 建议改用 `mktemp` + 专用目录 |

---

## 三、综合评分

### 做得好的
- 密钥生成全程使用 `openssl rand`、`wg genkey`、`xray x25519` 等安全随机源
- 所有外部下载使用 HTTPS，无 `curl | bash`（先落地文件再执行）
- manifest 变量白名单机制（`discovery_get_manifest_value` 使用 `case` 拒绝未知变量）
- 协议排序统一调用 `discovery_list_modules_by_security()`（单一真相源）
- deploy/uninstall 编号现已一致（协议按安全等级排序）

### 待改进项（按优先级）

| 优先级 | 问题 | 分类 |
|:--:|------|------|
| 🔴 P0 | Nginx 缺 TLS 密码套件 + HSTS + OCSP Stapling | TLS安全 |
| 🟠 P1 | sing-box mixed 模式以 root 运行 | 权限最小化 |
| 🟠 P2 | WireGuard 私钥嵌入 URI（已知设计妥协） | 凭据泄露 |
| 🟡 P3 | 订阅文件单层路径保护 | 访问控制 |
| 🟡 P4 | 备份文件 TOCTOU 风险 | 文件安全 |
| 🟡 P5 | 域名输入无格式校验 | 输入验证 |
| 🟡 P6 | 公网IP检测使用HTTP | 传输安全 |
