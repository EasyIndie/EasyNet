# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.3] - 2026-06-12

### Added
- CI workflow for automated testing (GitHub Actions)
- VPS provider list documentation
- Tun mode support for sing-box client

### Fixed
- sing-box client install script: DNS resolver, subscription URL, QR code generation
- GitHub Actions workflow warnings
- sing-box client subscription parsing

### Changed
- Comprehensive README update with protocol comparison, project structure, and deployment docs
- Refined sing-box client installation process

## [0.0.2] - 2026-05-05

### Added
- Hysteria2 protocol support with strict/balanced/compat deployment modes
- VPS provider documentation

### Changed
- Documentation improvements across multiple files

## [0.0.1] - 2026-05-04

### Added
- Initial release
- Support for 6 proxy protocols: Xray+Reality, Hysteria2, Trojan-Go, V2Ray, Shadowsocks, WireGuard
- Automated deployment via deploy.sh
- Modular uninstall with per-protocol support
- Edge Gateway with Nginx exposure layer
- Subscription system with URI / Clash / sing-box formats and QR code generation
- Environment-based configuration (.env file support)
- Smoke test script for post-deployment verification
- BBR congestion control and system hardening
- Automated SSL certificate renewal hook
- logrotate and journald log limits
- Unit test framework with 13 test suites

[0.0.3]: https://github.com/EasyIndie/EasyNet/compare/0.0.2...0.0.3
[0.0.2]: https://github.com/EasyIndie/EasyNet/compare/0.0.1...0.0.2
[0.0.1]: https://github.com/EasyIndie/EasyNet/releases/tag/0.0.1
