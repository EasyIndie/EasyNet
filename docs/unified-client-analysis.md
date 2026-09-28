# 统一跨平台客户端方案调研

> **归档日期**: 2026-09-29
> **状态**: 仅方案（不改代码）。触发背景见 issue #5 与 `docs/unified-backend-analysis.md`。
> **结论**: 可行的统一方案是 **Flutter UI + 内嵌 sing-box 核心 + 两个薄原生 VPN 壳**；
> 先例是 hiddify-next（32.9k★）。唯一跨不过的协议缺口是 **AmneziaWG**（sing-box 不支持）。

## 一、需求

| 维度 | 要求 |
|---|---|
| PC | macOS / Linux / Windows，x86_64 + arm64 |
| 移动 | iOS / iPadOS / Android / AndroidTV |
| UI | 各端**一致**的界面与交互 |
| 协议 | 尽量覆盖 EasyNet 服务端（Reality / Hysteria2 / SS2022 / AmneziaWG） |

## 二、核心结论（先说重点）

1. **代理内核本身已经是跨平台的**：sing-box（Go）用 gomobile 就能产出 iOS/macOS 的
   `.xcframework` 和 Android 的 `.aar`，桌面端是原生二进制。所以「统一内核」不是难点，
   **难点只有两处：UI 一致性 + 系统 VPN 集成**。
2. **UI 一致性**：用 Flutter 一套 Dart 代码即可覆盖全部 7 个平台（AndroidTV 就是同一个
   APK 加一个 TV 布局）。
3. **系统 VPN 集成躲不掉原生**：iOS 强制 `NetworkExtension`（Swift/ObjC）、Android 强制
   `VpnService`（Kotlin）。这层必须写，但可以写得很薄（起隧道 + 转发日志，不承担 UI）。
4. **协议缺口**：sing-box 不支持 AmneziaWG，所以「统一客户端」天然少 AWG 一个协议。
   生产 `balanced` profile（Reality+Hysteria2）不受影响；测试 `compat` 的 AWG 覆盖不到。

## 三、技术选型对比（UI 框架）

| 方案 | 7 平台覆盖 | UI 一致性 | VPN 集成难度 | 先例 |
|---|---|---|---|---|
| **Flutter + sing-box** | ✅ 全部 | ✅ 一套 Dart | 需 2 个原生薄壳（iOS NE + Android VpnService） | **hiddify-next 32.9k★**（就是这套架构） |
| Compose Multiplatform | Android/iOS/桌面 | ✅ 高 | iOS 仍需 Swift NE；桌面需 JVM↔sing-box 桥 | 年轻，无同类先例 |
| React Native | iOS/Android/桌面 | ✅ 高 | 同 Flutter | 无同类 VPN 先例 |
| Tauri (Rust) | 仅桌面 | ✅ 桌面 | 移动端基本不可行 | 移动端出局 |
| 各平台原生（sing-box 官方做法） | ✅ 全部 | ❌ N 套 UI | 各平台最顺 | 官方 sing-box-for-apple(Swift) / -android(Kotlin)，UI 不统一 |

**推荐：Flutter + sing-box。** 理由：一套 UI 跑满 7 平台、内核 gomobile 官方支持、且已被
hiddify-next 用真机验证过这条路可维护。

## 四、系统 VPN 集成的分平台硬约束

| 平台 | 强制约束 | 内核跑在哪 | 备注 |
|---|---|---|---|
| iOS / iPadOS | `NEPacketTunnelProvider`（Swift/ObjC，独立进程） | sing-box 作为库跑在 NE 进程内 | 需开发者账号 + NE entitlement |
| Android / AndroidTV | `VpnService`（Kotlin），把 tun fd 交给 sing-box | app 进程内 | Google Play 对 VPN 类审核严 |
| macOS | 可走 NE（与 iOS 同构）或直接跑 TUN | 进程内 | 最自由 |
| Linux / Windows | **无系统 VPN 强制要求** | sing-box 自带 TUN（gvisor）进程内跑 | 无需特权 UI |

## 五、推荐架构

```
┌─────────────────────────────────────────────────┐
│  Flutter UI（一套 Dart：订阅/节点/日志/设置）       │
├─────────────────────────────────────────────────┤
│  MethodChannel / FFI 桥接层（极薄）               │
├──────────────────┬──────────────┬───────────────┤
│ iOS NE (Swift)    │ Android      │ 桌面 TUN      │
│ 把 sing-box 库     │ VpnService   │ sing-box 原生  │
│ 跑在隧道进程内      │ (Kotlin)     │ 进程内直接跑    │
├──────────────────┴──────────────┴───────────────┤
│  sing-box 核心（gomobile .xcframework / .aar / 原生）│
└─────────────────────────────────────────────────┘
```

- 订阅直接复用现有 `/singbox` 端点（EasyNet 已生成 sing-box 配置，规则集 .srs 也现成）。
- 版本 pin 复用 `scripts/core/pins.sh` 的思路：gomobile 库与桌面二进制同版本同哈希。

## 六、AmneziaWG 缺口的三种取舍

| 选项 | 说明 | 评价 |
|---|---|---|
| **A. 统一客户端明确不支持 AWG** | 与现状一致（singbox 订阅本就不含 AWG）；Hysteria2 已承担 UDP 混淆职责 | ✅ **推荐** |
| B. 换 mihomo 内核 | mihomo 支持 AWG + xhttp，但 iOS 无官方 gomobile 绑定，方言复杂 | 成本高，不推荐 |
| C. 双内核（sing-box + awg） | 复杂度翻倍、包体积翻倍 | ❌ 不推荐 |

## 七、若推进的分阶段路线

- **阶段 0（PoC）**：Flutter 空壳 + sing-box 库接入，跑通三路最小隧道
  （iOS NE / Android VpnService / 桌面 TUN）。
- **阶段 1**：订阅拉取（对接 `/singbox`）+ 节点选择 + 连接管理。
- **阶段 2**：分流规则（复用服务端 .srs）、日志、开机自启、按需代理。
- **阶段 3**：AndroidTV 布局、iPad 适配、发布渠道。

## 八、风险与成本

- **iOS 上架**：NetworkExtension 需开发者账号 + entitlement 审批；App Store 对代理类 app
  审核严格（可能要求地区限制或直接拒）。Android Google Play 同理，大概率需侧载/自建分发。
- **维护成本**：一套 Flutter + 两套原生薄壳 + sing-box 版本跟踪，比现在的 shell 安装器重
  一个数量级；这是「做产品」而非「做脚本」。
- **发布节奏**：iOS 审核周期会成为发版瓶颈。

## 九、参考项目

| 项目 | stars | 架构 | 启示 |
|---|---|---|---|
| [hiddify/hiddify-app](https://github.com/hiddify/hiddify-app) | 32.9k | Flutter + sing-box/xray 内核 | 本题的**最强先例**，覆盖 Android/iOS/macOS/Windows/Linux |
| [SagerNet/sing-box-for-apple](https://github.com/SagerNet/sing-box-for-apple) | 1.0k | SwiftUI（仅 Apple 平台） | 官方各平台独立 UI，反证「统一 UI 要自己做」 |
| [SagerNet/sing-box-for-android](https://github.com/SagerNet/sing-box-for-android) | 1.3k | Kotlin（仅 Android） | 同上 |
| [MetaCubeX/ClashMetaForAndroid](https://github.com/MetaCubeX/ClashMetaForAndroid) | 46.9k | mihomo + Kotlin（仅 Android） | mihomo 路线的移动端现状（无 iOS 官方绑定） |

## 十、一句话结论

要做「一套 UI 跑 7 平台」的 EasyNet 客户端，**Flutter + sing-box 核心 + iOS/Android 两个薄
原生 VPN 壳**是唯一有成熟先例、成本可控的路；代价是放弃 AmneziaWG 节点（生产 profile 不受影响），
并把「脚本级维护」升级为「产品级维护」。建议先做阶段 0 PoC 验证三路隧道，再决定是否立项。
