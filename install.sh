#!/bin/sh
# --- [ HPPC: 系统部署向导 (Installer) v3.6 ] ---
# 职责：环境预检、交互式配置、核心组件拉取、定时任务注册
# 修复：P0级函数未定义崩溃、增强依赖检查、强制下载校验、全面 POSIX 兼容

# ==========================================
# 本地日志系统 (独立于 utils.sh，保障前置安全)
# ==========================================
C_ERR='\033[31m'; C_OK='\033[32m'; C_WARN='\033[33m'; C_INFO='\033[36m'; C_RESET='\033[0m'

log_info()    { printf "${C_INFO}[INFO]${C_RESET} %s\n" "$1"; }
log_success() { printf "${C_OK}[SUCCESS]${C_RESET} %s\n" "$1"; }
log_warn()    { printf "${C_WARN}[WARN]${C_RESET} %s\n" "$1"; }
log_err()     { printf "${C_ERR}[ERROR]${C_RESET} %s\n" "$1"; }

CONF_FILE="/etc/hppc/hppc.conf"

# ⚠️ 仓库配置区
GH_USER="Vonzhen"
GH_REPO="hppc"
GH_BRANCH="master"
GH_BASE_URL="https://raw.githubusercontent.com/$GH_USER/$GH_REPO/$GH_BRANCH"

printf "\n🔧 \033[1;33mHPPC - 高级路由控制编排系统 v3.6 部署向导\033[0m\n\n"

# ==========================================
# 1. 环境依赖预检 (Pre-flight Check)
# ==========================================
log_info "正在执行环境依赖预检..."
PACKAGES=""
! command -v curl >/dev/null && PACKAGES="$PACKAGES curl"
! command -v jq >/dev/null   && PACKAGES="$PACKAGES jq"
! command -v openssl >/dev/null && PACKAGES="$PACKAGES openssl-util"

# 检查根证书依赖，防止 API 请求 SSL 失败
if ! opkg list-installed 2>/dev/null | grep -q "ca-bundle" && ! opkg list-installed 2>/dev/null | grep -q "ca-certificates"; then
    PACKAGES="$PACKAGES ca-bundle"
fi

if [ -n "$PACKAGES" ]; then
    log_warn "发现缺失依赖: $PACKAGES，正在自动安装..."
    opkg update
    if ! opkg install $PACKAGES; then
        # 针对部分老旧 OpenWrt 源的 fallback
        opkg install ca-certificates 2>/dev/null
    fi
    
    if [ $? -ne 0 ]; then
        log_err "依赖安装失败！请检查系统网络连通性或 opkg 软件源配置。"
        exit 1
    fi
else
    log_success "基础环境健康，准予通行。"
fi

# ==========================================
# 2. 目录初始化
# ==========================================
[ -d "/usr/share/hppc" ] && rm -rf /usr/share/hppc
mkdir -p /etc/hppc /tmp/hppc
mkdir -p /usr/share/hppc/core /usr/share/hppc/lib /usr/share/hppc/bin /usr/share/hppc/modules
mkdir -p /usr/share/hppc/templates/models

# ==========================================
# 3. 交互式参数配置
# ==========================================
if [ -f "$CONF_FILE" ]; then
    . "$CONF_FILE"
    log_success "检测到现有配置文件，节点 [${LOCATION:-未命名}] 将保留历史设置..."
else
    echo "------------------------------------------------"
    # 3.1 节点标识
    printf "${C_WARN}1. 节点展示名称 (Location)${C_RESET} [HomeProxy]: "
    read -r LOC_INPUT
    LOCATION="${LOC_INPUT:-HomeProxy}"

    # 3.2 代理 API
    printf "${C_WARN}2. Worker 代理域名 (CF Domain)${C_RESET} [hppc.x.workers.dev]: "
    read -r CF_DOMAIN

    # 3.3 鉴权密钥
    printf "${C_WARN}3. 数据请求验证码 (Token)${C_RESET}: "
    read -r CF_TOKEN

    # 3.4 告警通道
    printf "${C_WARN}4. Telegram Bot Token${C_RESET} [回车跳过]: "
    read -r TG_TOKEN
    printf "${C_WARN}   Telegram Chat ID${C_RESET} [回车跳过]: "
    read -r TG_ID

    # 3.5 规则集源
    printf "${C_WARN}5. 私有规则集加速源 (Private Assets Repo URL)${C_RESET}\n"
    printf "   (示例: https://testingcf.jsdelivr.net/gh/User/rules@master/rules)\n"
    printf "   请输入 [回车跳过]: "
    read -r ASSETS_REPO
    echo "------------------------------------------------"

    # 写入配置 (原子操作保护)
    cat > "$CONF_FILE.tmp" <<EOF
# --- HPPC 系统环境变量 ---
GH_RAW_URL='$GH_BASE_URL'
CF_DOMAIN='$CF_DOMAIN'
CF_TOKEN='$CF_TOKEN'
TG_BOT_TOKEN='$TG_TOKEN'
TG_CHAT_ID='$TG_ID'
LOCATION='$LOCATION'
ASSETS_PRIVATE_REPO='$ASSETS_REPO'
EOF
    mv "$CONF_FILE.tmp" "$CONF_FILE"
    chmod 600 "$CONF_FILE"
fi

# ==========================================
# 4. 核心组件获取 (带严格失败熔断)
# ==========================================
download_asset() {
    local dest="$1"
    local src="$2"
    if curl -sLk --connect-timeout 10 -f "$GH_BASE_URL/$src" -o "$dest"; then
        chmod +x "$dest"
        return 0
    else
        log_err "无法获取组件: $src"
        return 1
    fi
}

log_info "正在拉取核心业务组件..."

download_asset "/usr/share/hppc/core/synthesize.sh" "core/synthesize.sh" || exit 1
download_asset "/usr/share/hppc/core/fetch.sh"      "core/fetch.sh" || exit 1
download_asset "/usr/share/hppc/core/daemon.sh"     "core/daemon.sh" || exit 1
download_asset "/usr/share/hppc/core/rollback.sh"   "core/rollback.sh" || exit 1

download_asset "/usr/share/hppc/lib/utils.sh"       "lib/utils.sh" || exit 1
download_asset "/usr/share/hppc/modules/assets.sh"  "modules/assets.sh" || exit 1

download_asset "/usr/share/hppc/bin/cli.sh"         "bin/cli.sh" || exit 1
download_asset "/usr/share/hppc/templates/hp_base.uci" "templates/hp_base.uci" || exit 1

# --- 智能模板同步 (Smart Sync) ---
log_info "正在同步节点协议模板 (Smart Sync)..."
API_URL="https://api.github.com/repos/$GH_USER/$GH_REPO/contents/templates/models?ref=$GH_BRANCH"

# 解析 GitHub API 获取文件列表
TEMPLATE_LIST=$(curl -skL --connect-timeout 10 "$API_URL" | jq -r '.[].name' 2>/dev/null)

if [ -n "$TEMPLATE_LIST" ] && [ "$TEMPLATE_LIST" != "null" ]; then
    rm -f /usr/share/hppc/templates/models/*.uci
    for uci_file in $TEMPLATE_LIST; do
        if echo "$uci_file" | grep -q "\.uci$"; then
            printf "   - 同步模板: %s\n" "$uci_file"
            download_asset "/usr/share/hppc/templates/models/$uci_file" "templates/models/$uci_file"
        fi
    done
else
    log_warn "GitHub API 响应受限，切换至本地后备清单..."
    for p in vless trojan hysteria2 shadowsocks anytls tuic; do
        download_asset "/usr/share/hppc/templates/models/$p.uci" "templates/models/$p.uci"
    done
fi

# ==========================================
# 5. 系统注册与收尾
# ==========================================
log_info "正在注册全局命令与定时任务..."

# 注册命令符号链接
ln -sf /usr/share/hppc/bin/cli.sh /usr/bin/hppc

# 清理旧定时任务并写入新任务 (1分钟级守护 + 每日 07:30 规则资产更新)
(crontab -l 2>/dev/null | grep -v "hppc" | grep -v "daemon.sh" | grep -v "assets.sh") | crontab -
(crontab -l 2>/dev/null; \
 echo "* * * * * /usr/share/hppc/core/daemon.sh"; \
 echo "30 7 * * * /usr/share/hppc/modules/assets.sh --update auto") | crontab -

printf "\n${C_OK}✅ HPPC 部署完毕！系统已准备就绪。${C_RESET}\n"
printf "🔸 请在终端输入 ${C_WARN}hppc${C_RESET} 唤出系统控制面板。\n"
printf "🔸 建议首次使用时，通过面板菜单执行 ${C_INFO}[6] 部署 WebUI${C_RESET}。\n"

# 阅后即焚
rm -f "$0"
