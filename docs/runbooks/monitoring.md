# 运行监控告警配置 Runbook

> 模块：`scripts/core/monitor.sh`；命令：`easynet monitor [run|check]`
> 检查项：协议服务 / nginx / fail2ban 存活、订阅端点可达、Edge 证书 7 天到期预警，
> 以及**上游维度**（运行时版本漂移 + 已知 CVE，见第 7 节）。
> 只在失败时推送；渠道 + 凭据齐全时 `deploy.sh` 才安装 cron（`EASYNET_MONITOR_CRON`，默认 `0 9 * * *`）。

## 1. 渠道选择

| 渠道 | 零成本 | 需提供 | 备注 |
|---|:--:|---|---|
| **ntfy** | ✅ | 一个 topic URL | 手机装 ntfy App 订阅同 topic；无需账号 |
| **telegram** | ✅ | Bot Token + Chat ID | 需已能连 Telegram |
| **email** | ✅ | 收件邮箱 + SMTP 凭据 | VPS 需装 `s-nail`；配置最重，见下 |

## 2. email 渠道（s-nail + QQ 邮箱实测）

这是**踩坑最多**的渠道，要点全部记录如下（s-nail v14.9.x）。

### 2.1 安装

```bash
apt install -y s-nail
```

> `s-nail` 提供 `/usr/bin/s-nail`，但**不会**自动注册 `mail`/`mailx` 命令。
> `monitor.sh` 的 `monitor_mail_bin()` 会依次探测 `mail`/`mailx`/`s-nail`，无需手动建软链。

### 2.2 获取 QQ 邮箱 SMTP 授权码

1. 登录 https://mail.qq.com
2. **设置 → 账户 → POP3/SMTP 服务** → 开启
3. 按提示验证，得到 **16 位授权码**（不是 QQ 密码）

### 2.3 配置 `/root/.mailrc`（600）

```
set v15-compat
set mta=smtps://<邮箱>%40qq.com:<授权码>@smtp.qq.com:465
set smtp-auth=login
set from=<邮箱>
set tls-verify=warn
```

```bash
chmod 600 /root/.mailrc
```

### 2.4 关键坑位（血泪教训，勿踩）

| 坑 | 说明 |
|---|---|
| **旧变量名已废弃** | s-nail v14 用 `mta` 取代 `smtp`；`ssl-verify` 取代为 `tls-verify`。旧写法会打印 `variable superseded` 警告且可能不生效 |
| **必须 `set v15-compat`** | 不设则报 `New-style URL used without *v15-compat*`，邮件发不出（`dead.letter`） |
| **邮箱 `@` 必须 `%40` 编码** | 凭据内嵌 URL 时，`user@qq.com` 里的 `@` 会破坏 URL 解析，写成 `user%40qq.com` |
| **端口用 465 隐式 TLS** | `smtps://` 前缀即隐式 TLS，无需 `tls_starttls` |

### 2.5 验证

```bash
echo "测试 $(date)" | s-nail -s "EasyNet 测试 - $(hostname)" <收件邮箱>
echo "s-nail 退出码: $?"   # 0 = 已投递到 QQ SMTP
```

再走一遍 monitor 的真实代码路径：

```bash
source /opt/easynet/scripts/core/monitor.sh
load_easynet_env_file /opt/easynet/.env
monitor_send "[EasyNet] 告警链路端到端验证 $(date)"
```

## 3. ntfy 渠道

```bash
# .env
EASYNET_MONITOR_NOTIFY=ntfy
EASYNET_MONITOR_NTFY_TOPIC_URL=https://ntfy.sh/<你起的随机 topic>
```

手机装 ntfy App 订阅同名 topic 即可。

## 4. telegram 渠道

```bash
# .env
EASYNET_MONITOR_NOTIFY=telegram
EASYNET_MONITOR_TELEGRAM_BOT_TOKEN=<BotFather 给的 token>
EASYNET_MONITOR_TELEGRAM_CHAT_ID=<chat id>
```

> 取 chat_id：给 bot 发一条消息后访问
> `https://api.telegram.org/bot<token>/getUpdates`。

## 5. 写入 `.env` 并安装 cron

```bash
# 追加到 /opt/easynet/.env（示例 email 渠道）
EASYNET_MONITOR_NOTIFY=email
EASYNET_MONITOR_EMAIL_TO=admin@example.com

# 安装 cron（渠道+凭据齐全才装；也可下次 easynet deploy 时自动装）
bash -c '
  source /opt/easynet/scripts/core/monitor.sh
  load_easynet_env_file /opt/easynet/.env
  monitor_install_cron
'

# 验证
crontab -l | grep MONITOR
easynet monitor check          # 只检查不推送，退出码 0 = 全绿
```

## 6. 日常

- 每日自动跑一次（失败才推送，全绿不打扰）。
- 手工体检：`easynet monitor check`；手工跑并推送：`easynet monitor run`。
- 心跳时间戳：`/var/lib/easynet/monitor/last_ok`。
- 换发件邮箱/作废授权码：改 `/root/.mailrc` 后重测 2.5 即可。

## 7. 上游维度：版本漂移 + CVE

每日检查里还有两项**CI 覆盖不到**的上游维度（CI 的 `pins.yml` 只比「repo pin vs 上游稳定版」；
VPS 跑的就是 pin 的 release，所以不做重复的「pin 落后」检查）：

| 检查 | 抓什么 | 原理 |
|---|---|---|
| **版本漂移** | 跑着的二进制版本 ≠ release pin | 发现手工替换二进制 / 升级半途失败（本应是 pin 的版本） |
| **已知 CVE** | 运行版本命中的安全公告 | OSV.dev 查询 Xray / Hysteria2 / Shadowsocks 的运行版本 |

**防刷屏设计（重点）**：

1. **CVE 只报「可修复」的**：OSV 里没有 `fixed` 版本的公告直接跳过——报了也无法处理，
   只会每天刷屏。例如 hysteria 2.12.3 虽命中 2 个公告，但上游还没修（且 2.12.3 就是最新
   release），**不会**被报；等上游发布修复版、OSV 补上 `fixed` 字段后才会报。
2. **上游发现去重**：只在**首次出现**时推送（状态文件 `.../monitor/upstream_state` 记录
   已报过的项），保持不变就不再重复；有新增 CVE / 漂移变化才再报。健康问题（服务/端点/证书）
   不受影响，仍然每次都报。

开关（写入 `.env`）：

```
EASYNET_MONITOR_UPSTREAM=false   # 整段关闭
EASYNET_MONITOR_CVE=false        # 只关 CVE，保留版本漂移
```

- 版本漂移：本地比较（`xray version` / `hysteria version` / `ssserver --version` vs `core/pins.sh`），
  无网络依赖。
- 已知 CVE：调 OSV.dev（best-effort，查询失败静默，不误报）。命中的公告会原样推给你，例如
  `已知漏洞: hysteria2 2.12.3: GO-2026-5807: Hysteria vulnerable to server crash ...`。

手工查一次：

```bash
easynet monitor check                     # 全量检查（含上游维度）
source scripts/core/monitor.sh; monitor_upstream_findings
bash scripts/check_upstream_pins.sh       # 对照：CI 侧的 pin 落后检查
```
