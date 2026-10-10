# Apple Actions 凭据名称盘点

2026-10-10，用户授权查询名称与用途；仅读取 GitHub 元数据，未读取、下载或使用任何密钥值。

## 已观察的仓库范围

- `GET /repos/EasyIndie/EasyNet/actions/organization-secrets` 成功，返回以下 7 个共享组织 Secrets。
- 仓库级 Actions Secrets 列表为空；Actions Environments 列表为空。
- 组织总列表此前返回 403，但仓库继承列表成功。无需为了此次盘点扩大 CLI 权限。
- 随后通过 Chrome 现有登录读取组织 Actions Secrets 设置页：组织列表同样只有这 7 项，
  每项 Visibility 均为 `Public repositories`；未发现额外未共享的 Apple/profile Secret。
  CLI 403 是 token 权限限制，不代表浏览器账号不能读取组织设置。
- 仓库可见性不证明证书有效、API 权限足够、profile 匹配或实际签名/公证成功。

| 已观察名称 | 按名称推断的用途 | 尚需确认 |
|---|---|---|
| `APPLE_ASC_API_KEY` | Apple / App Store Connect API 私钥，候选公证认证路线 | 原始 P8 文本还是 Base64；API 权限和公证适用性未验证 |
| `APPLE_ASC_API_KEY_ID` | API Key 标识 | 与私钥的匹配未验证 |
| `APPLE_ASC_ISSUER_ID` | API issuer 标识 | 与 API Key 的匹配未验证 |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64 编码 P12 签名材料 | 是否 Developer ID Application，以及是否包含对应私钥 |
| `APPLE_CERTIFICATE_P12_PASSWORD` | P12 导入密码 | 密码匹配未验证 |
| `APPLE_ID` | Apple 账号标识 | 本次 API Key 路线未必需要；不据此推定存在账号密码认证材料 |
| `APPLE_TEAM_ID` | Apple Developer 团队标识 | 与证书/profile/entitlements 的匹配未验证 |

## 用户确认

2026-10-10 用户确认：Network Extension provisioning profile 目前没有，其他所列材料都有。
因此签名证书、私钥、导入密码、API 认证材料及团队标识记为用户确认具备；
这不等于已完成证书有效性、材料匹配、API 权限或签名/公证实测。
用户未选择 API 私钥的具体编码格式，后续 adapter 合同仍需明确原始 P8/Base64 的处理方式。
Network Extension profile 记为明确缺失，不能标记系统 VPN 签名条件已满足。

## 推进边界

先冻结独立签名/公证合同与 API 私钥编码处理，再验证现有材料。
profile 等 App/扩展 Bundle ID、entitlements 和分发形式确定后准备；
它不阻塞无密钥 baseline 或不使用该受限能力的普通应用签名准备，
但仍阻塞需要它的 Network Extension 系统 VPN 验收。
本盘点不启动 Actions，不导入 Keychain，不执行公证，不创建正式发布；G0 仍未完成。
无密钥 hosted baseline 静态准备不依赖这些回答。

接口依据：[GitHub 官方 Secrets REST API](https://docs.github.com/en/rest/actions/secrets#list-repository-organization-secrets)。
