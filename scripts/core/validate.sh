#!/bin/bash
# EasyNet Pre-flight Validation Library
# Source this file and call validate_easynet_config to check the
# deployment environment before starting installation.
#
# Usage (inside deploy.sh):
#   source "$PROJECT_ROOT/scripts/core/validate.sh"
#   validate_easynet_config      # uses default modules / env vars
#   validate_easynet_config "xray-reality" "hysteria2"   # explicit modules

EASYNET_VALIDATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$EASYNET_VALIDATE_DIR/discovery.sh"

# Logging (guard against double-definition when sourced from deploy.sh)
if ! declare -F log_info >/dev/null 2>&1; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
    log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
    log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
fi

# Required CLI tools for base deployment
EASYNET_REQUIRED_TOOLS=(
    curl
    jq
    openssl
)

# Optional but recommended
EASYNET_OPTIONAL_TOOLS=(
    qrencode
)

# ============================================================
# Tool checks
# ============================================================

validate_required_tools() {
    local tool missing=0
    for tool in "${EASYNET_REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            log_error "缺失必需工具: $tool"
            missing=1
        fi
    done
    if [ "$missing" -ne 0 ]; then
        log_error "请先安装缺失工具: apt install -y ${EASYNET_REQUIRED_TOOLS[*]}"
        return 1
    fi
    for tool in "${EASYNET_OPTIONAL_TOOLS[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            log_warn "可选工具未安装: $tool (二维码显示将不可用)"
        fi
    done
    return 0
}

# ============================================================
# Port conflict checks
# ============================================================

validate_port_conflicts() {
    local modules=("$@")
    local declared_ports=()
    local mod_a mod_b conflict=0

    if [ "${#modules[@]}" -eq 0 ]; then
        while IFS= read -r mod; do
            modules+=("$mod")
        done < <(discovery_list_modules)
    fi

    for mod in "${modules[@]}"; do
        if ! discovery_load_manifest "$mod" 2>/dev/null; then
            log_error "未知模块: $mod"
            return 1
        fi
        local p="${MODULE_DEFAULT_PORT:-0}"
        local pp="${MODULE_DEFAULT_PUBLIC_PORT:-}"
        declared_ports+=("$mod:$p")
        if [ -n "$pp" ] && [ "$pp" != "$p" ]; then
            declared_ports+=("$mod:$pp")
        fi
    done

    # O(n^2) pairwise check — acceptable for small module count
    local i j entry_i entry_j pi pj
    for ((i = 0; i < ${#declared_ports[@]}; i++)); do
        entry_i="${declared_ports[$i]}"
        pi="${entry_i##*:}"
        for ((j = i + 1; j < ${#declared_ports[@]}; j++)); do
            entry_j="${declared_ports[$j]}"
            pj="${entry_j##*:}"
            if [ "$pi" = "$pj" ]; then
                mod_a="${entry_i%%:*}"
                mod_b="${entry_j%%:*}"
                log_error "端口冲突: $mod_a 和 $mod_b 都使用端口 $pi"
                conflict=1
            fi
        done
    done

    if [ "$conflict" -ne 0 ]; then
        log_error "请修改冲突模块的端口配置后重试"
        return 1
    fi
    return 0
}

# ============================================================
# Domain checks
# ============================================================

validate_domain_resolvable() {
    local domain="$1"
    local label="${2:-$domain}"

    if ! command -v host &>/dev/null && ! command -v nslookup &>/dev/null && ! command -v dig &>/dev/null; then
        log_warn "无 DNS 查询工具，跳过域名解析检查: $label"
        return 0
    fi

    if host "$domain" >/dev/null 2>&1; then
        return 0
    elif nslookup "$domain" >/dev/null 2>&1; then
        return 0
    elif dig +short "$domain" >/dev/null 2>&1; then
        return 0
    fi

    log_error "域名无法解析: $label"
    log_error "请确保 $domain 已配置 A 记录指向当前服务器"
    return 1
}

validate_deployment_domains() {
    local has_error=0

    if [ -n "$EASYNET_DOMAIN" ]; then
        validate_domain_resolvable "$EASYNET_DOMAIN" "EASYNET_DOMAIN" || has_error=1
    fi
    if [ -n "$EASYNET_SUBSCRIPTION_DOMAIN" ] && [ "$EASYNET_SUBSCRIPTION_DOMAIN" != "$EASYNET_DOMAIN" ]; then
        validate_domain_resolvable "$EASYNET_SUBSCRIPTION_DOMAIN" "EASYNET_SUBSCRIPTION_DOMAIN" || has_error=1
    fi

    return "$has_error"
}

# ============================================================
# OS compatibility check
# ============================================================

validate_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "无法检测操作系统 (缺少 /etc/os-release)"
        return 1
    fi
    # Source in a subshell to avoid polluting caller
    local os_id
    os_id=$(. /etc/os-release && echo "$ID")
    case "$os_id" in
        ubuntu|debian) return 0 ;;
        *)
            log_error "不支持的操作系统: $os_id (仅支持 Ubuntu/Debian)"
            return 1
            ;;
    esac
}

# ============================================================
# Aggregate validation entry point
# ============================================================

# Usage: validate_easynet_config [module_name ...]
# If no modules are given, validates all discovered modules.
# Returns 0 if all checks pass, 1 otherwise.
validate_easynet_config() {
    local failures=0

    log_info "=== EasyNet 部署前检查 ==="

    log_info "检查必需工具..."
    validate_required_tools || ((failures++))

    log_info "检查操作系统兼容性..."
    validate_os || ((failures++))

    log_info "检查端口冲突..."
    validate_port_conflicts "$@" || ((failures++))

    if [ -n "${EASYNET_DOMAIN:-}" ] || [ -n "${EASYNET_SUBSCRIPTION_DOMAIN:-}" ]; then
        log_info "检查域名解析..."
        validate_deployment_domains || ((failures++))
    fi

    if [ "$failures" -eq 0 ]; then
        log_info "=== 所有检查通过 ==="
        return 0
    else
        log_error "=== $failures 项检查失败 ==="
        return 1
    fi
}
