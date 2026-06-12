# 变更日志

项目所有重要变更都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
本项目遵循 [语义化版本](https://semver.org/spec/v2.0.0.html)。

## [0.0.4] - 2026-06-12

### 新增
- Manifest 版本化：所有协议 manifest 声明 `MANIFEST_VERSION=1`，discovery 层增加版本校验以保护插件契约
- 部署前配置预检（`scripts/core/validate.sh`）：检查必需工具、端口冲突、域名解析和操作系统兼容性

### 变更
- 将 sing-box outbound 的 jq 逻辑提取为独立文件 `scripts/core/singbox_outbound.jq`，便于独立维护和测试

## [0.0.3] - 2026-06-12

### 新增
- CI 自动测试工作流（GitHub Actions）
- VPS 提供商列表文档
- sing-box 客户端 Tun 模式支持

### 修复
- sing-box 客户端安装脚本：DNS 解析器、订阅地址、二维码生成
- GitHub Actions 工作流警告
- sing-box 客户端订阅解析

### 变更
- 全面更新 README，增加协议对比、项目结构和部署文档
- 改进 sing-box 客户端安装流程

## [0.0.2] - 2026-05-05

### 新增
- Hysteria2 协议支持，含 strict/balanced/compat 部署策略
- VPS 提供商文档

### 变更
- 多文件文档改进

## [0.0.1] - 2026-05-04

### 新增
- 初始发布
- 支持 6 种代理协议：Xray+Reality、Hysteria2、Trojan-Go、V2Ray、Shadowsocks、WireGuard
- 通过 deploy.sh 自动化部署
- 按协议模块卸载
- 基于 Nginx 的 Edge Gateway 暴露层
- 订阅系统：URI / Clash / sing-box 三种格式及二维码生成
- 基于环境变量的配置（.env 文件支持）
- 部署后快速检查脚本
- BBR 拥塞控制和系统加固
- SSL 证书自动续期 hook
- logrotate 和 journald 日志限额
- 单元测试框架（13 个测试套件）

[0.0.4]: https://github.com/EasyIndie/EasyNet/compare/0.0.3...0.0.4
[0.0.3]: https://github.com/EasyIndie/EasyNet/compare/0.0.2...0.0.3
[0.0.2]: https://github.com/EasyIndie/EasyNet/compare/0.0.1...0.0.2
[0.0.1]: https://github.com/EasyIndie/EasyNet/releases/tag/0.0.1
