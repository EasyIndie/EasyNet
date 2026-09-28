# SSH 加固 Runbook

> 脚本：`scripts/security/harden_ssh.sh`（`check`/`apply`/`confirm`/`revert`/`status`）
> 原则：危险动作必须**显式且可回滚**——因此**不参与 `deploy.sh`**，只有你主动执行才会改动系统。

## 目标

关闭 root 密码登录这一根本攻击面：

```
PermitRootLogin prohibit-password   # root 仅公钥
PasswordAuthentication no           # 禁密码登录
KbdInteractiveAuthentication no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
PermitEmptyPasswords no
```

## 上线前必查（避免把自己锁死）

```bash
# 1. 确认至少一把可用公钥
grep -cvE '^[[:space:]]*(#|$)' /root/.ssh/authorized_keys   # 应 >= 1

# 2. 确认当前会话是公钥登录
echo "$SSH_CLIENT"   # 有值，且你确实是 ssh key 登录

# 3. 排查近 30 天是否有「外来 IP」的密码登录（判断是否曾被人爆过 / 是否有人依赖密码）
journalctl -u ssh --since "30 days ago" --no-pager | grep "Accepted password"
#    → 若只有你自己的 IP，放心加固；若有陌生 IP，先查清再决定
```

> 实战案例：某次上线前发现「30 天 2 次密码登录成功」，排查后确认都是操作者本人部署
> 初期的登录（同 IP），非入侵。**这一步不能省**——它能区分「你的其他设备还在用密码」
> 和「被爆破成功过」。

## 标准流程（带回滚看门狗）

```bash
# 1. 只读体检
bash scripts/security/harden_ssh.sh check
#    结论应为「✅ 可以安全加固（有公钥，且当前就是公钥登录）」

# 2. 应用（写 drop-in + sshd -t 校验 + 武装 10 分钟自动回滚）
bash scripts/security/harden_ssh.sh apply

# 3. 【另开一个终端】验证新连接仍能登录（apply 后当前会话不受影响）
ssh proxy 'echo OK'

# 4. 验证通过后固化（取消自动回滚）
bash scripts/security/harden_ssh.sh confirm
```

若第 3 步失败或迟迟不 `confirm`，系统会在 10 分钟后**自动回滚**到加固前状态，不会锁死。

## 回滚

```bash
bash scripts/security/harden_ssh.sh revert   # 立即恢复到加固前
bash scripts/security/harden_ssh.sh status   # 查看当前状态
```

## 注意

- drop-in 名为 `10-easynet-hardening.conf`，故意排在 `50-cloud-init.conf` 之前
  （sshd 采用「首个值生效」）。
- **云厂商重装/重置实例会回归 cloud-init 默认**（`passwordauthentication yes`），需重跑一遍。
- 加固后若要从**新设备**登录，先把新设备公钥加入 `/root/.ssh/authorized_keys`，
  否则密码已禁用、无法登录。
- `apply` 是幂等的：已处于目标状态时直接返回，不会重复武装回滚定时器。
