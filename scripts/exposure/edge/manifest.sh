#!/bin/bash
# shellcheck disable=SC2034
# EasyNet Edge Gateway Manifest — consumed by discovery.sh

MANIFEST_VERSION=1

MODULE_NAME="edge"
MODULE_DISPLAY_NAME="Edge Gateway (Nginx + TLS + 订阅)"
MODULE_DESCRIPTION="Nginx 反向代理、Let's Encrypt TLS 证书管理、订阅文件分发"
MODULE_DEFAULT_PORT=443

# Edge Gateway 不参与协议安全排序
MODULE_SECURITY_RANK=999

# Edge 不在任何部署策略中自动选择
MODULE_PROFILES=""
