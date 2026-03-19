# Xray+Reality 客户端配置指南

## Reality 简介

Reality 是 Xray 的下一代 TLS 协议，具有以下优势：
- 无需购买域名和证书
- 完全模仿真实网站流量
- 更高的安全性和隐蔽性
- 支持 XTLS Vision 流控，性能优异

## Windows 客户端

### 1. 下载客户端

推荐使用 **NekoBox for Windows**：
- 下载地址：https://github.com/MatsuriDayo/nekoray/releases
- 选择 Windows 版本

或使用 **v2rayN**：
- 下载地址：https://github.com/2dust/v2rayN/releases

### 2. 配置 NekoBox

**方法一：通过链接导入**
1. 打开 NekoBox
2. 点击「服务器」→「从剪贴板导入」
3. 粘贴部署脚本生成的 vless:// 链接

**方法二：手动配置**
1. 点击「服务器」→「新建服务器」→「VLESS」
2. 填写以下信息：
   - 地址：你的服务器 IP
   - 端口：443
   - 用户 ID (UUID)：部署时生成的 UUID
   - 加密：none
   - 流控：xtls-rprx-vision
   - 传输协议：tcp
   - 安全：reality
   - SNI：www.microsoft.com
   - 指纹 (Fingerprint)：chrome
   - 公钥 (PublicKey)：部署时生成的公钥
   - Short ID：部署时生成的 Short ID

### 3. 连接

1. 在服务器列表中右键点击配置
2. 选择「启动」
3. 选择系统代理模式（PAC 或全局）

## macOS 客户端

### 1. 下载客户端

推荐使用 **NekoBox for macOS**：
- 下载地址：https://github.com/MatsuriDayo/nekoray/releases
- 选择 macOS 版本

或使用 **Clash Verge Rev**：
- 下载地址：https://github.com/clash-verge-rev/clash-verge-rev/releases

### 2. 配置 NekoBox

1. 打开 NekoBox
2. 点击「服务器」→「从剪贴板导入」
3. 粘贴 vless:// 链接

或手动配置，填写与 Windows 相同的信息。

### 3. 连接

1. 右键点击服务器配置
2. 选择「启动」
3. 选择代理模式

## Linux 客户端

### 1. 下载客户端

推荐使用 **NekoBox for Linux**：
- 下载地址：https://github.com/MatsuriDayo/nekoray/releases

或使用命令行版本的 Xray：
```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
```

### 2. 配置 Xray (命令行)

创建配置文件 `/usr/local/etc/xray/config.json`：

```json
{
    "inbounds": [
        {
            "port": 1080,
            "listen": "127.0.0.1",
            "protocol": "socks",
            "settings": {
                "udp": true
            }
        },
        {
            "port": 1081,
            "listen": "127.0.0.1",
            "protocol": "http"
        }
    ],
    "outbounds": [
        {
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": "your-server-ip",
                        "port": 443,
                        "users": [
                            {
                                "id": "your-uuid",
                                "flow": "xtls-rprx-vision",
                                "encryption": "none"
                            }
                        ]
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "serverName": "www.microsoft.com",
                    "fingerprint": "chrome",
                    "show": false,
                    "publicKey": "your-public-key",
                    "shortId": "your-short-id",
                    "spiderX": ""
                }
            }
        }
    ]
}
```

### 3. 启动 Xray

```bash
sudo systemctl enable xray
sudo systemctl start xray
```

然后配置浏览器或系统使用 SOCKS5 代理 127.0.0.1:1080。

## Android 客户端

### 1. 下载客户端

推荐使用 **NekoBox for Android**：
- 下载地址：https://github.com/MatsuriDayo/NekoBoxForAndroid/releases

或使用 **v2rayNG**：
- 下载地址：https://github.com/2dust/v2rayNG/releases

### 2. 配置

1. 打开 NekoBox
2. 点击右上角「+」
3. 选择「从剪贴板导入」
4. 粘贴 vless:// 链接

或选择「手动输入」→「VLESS」，填写配置信息。

### 3. 连接

1. 点击配置卡片
2. 点击右下角「启动」按钮
3. 授予 VPN 权限

## iOS 客户端

### 1. 下载客户端

推荐使用 **Shadowrocket**（$2.99）：
- 使用外区 Apple ID 在 App Store 搜索并购买

或使用 **Stash**：
- 外区 App Store 下载

### 2. 配置 Shadowrocket

1. 打开 Shadowrocket
2. 点击右上角「+」
3. 类型选择「VLESS」
4. 填写以下信息：
   - 地址：你的服务器 IP
   - 端口：443
   - 用户 ID：你的 UUID
   - 加密：none
   - 流控：xtls-rprx-vision
   - 传输：tcp
   - TLS：选择「Reality」
   - SNI：www.microsoft.com
   - 指纹：chrome
   - 公钥：你的公钥
   - Short ID：你的 Short ID

### 3. 连接

1. 返回首页
2. 点击配置后面的开关
3. 允许添加 VPN 配置

## 验证连接

### 检查 IP

访问以下网站确认 IP 已变更：
- https://www.whatismyip.com/
- https://ipleak.net/

### 测试 Reality

检查连接是否使用 Reality 协议：
- 访问 https://www.cloudflare.com/cdn-cgi/trace
- 确认可以正常访问

### 性能测试

访问 https://www.speedtest.net/ 测试网速。

Reality + XTLS Vision 应该能提供接近直连的性能。

## 常见问题

### 连接失败

- 检查 Xray 服务状态：`systemctl status xray`
- 确认配置文件中的 UUID、公钥、Short ID 正确
- 检查防火墙是否开放 443 端口
- 查看 Xray 日志：`journalctl -u xray -f`

### TLS 握手失败

- 确认服务器时间正确
- 检查 SNI 设置是否与配置一致
- 尝试更换指纹（chrome、firefox、safari、edge）

### 速度慢

- Reality 性能应该很好，如果慢可能是服务器问题
- 确认使用了 xtls-rprx-vision 流控
- 尝试更换服务器节点位置

### 被检测

- Reality 的设计就是为了对抗检测，通常很安全
- 确保 SNI 是真实存在的网站
- 不要在短时间内大量传输数据

## 安全建议

1. **保护好 UUID**：UUID 是访问凭证
2. **定期更换配置**：建议定期更换 UUID 和密钥
3. **选择合适的 SNI**：使用大公司的网站（如 microsoft、apple、cloudflare）
4. **监控连接**：定期查看服务器日志

## 进阶配置

### 多个用户

在服务器配置中添加多个客户端：

```json
"clients": [
    {
        "id": "uuid-1",
        "flow": "xtls-rprx-vision"
    },
    {
        "id": "uuid-2",
        "flow": "xtls-rprx-vision"
    }
]
```

### 更换 SNI

可以更换为其他网站，如：
- www.apple.com
- www.cloudflare.com
- www.ubuntu.com

确保选择访问量大、证书正常的网站。
