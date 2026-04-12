#!/bin/sh
# --- [ HPPC Core: 基础核心库 (Utils) v3.6 ] ---
# 职责: 提供全局路径常量、标准化日志、安全 IO 与别名翻译

# 强制声明 PATH，防止 Cron 环境下找不到 jq 或 curl
export PATH='/usr/sbin:/usr/bin:/sbin:/bin'

# ==========================================
# 全局路径常量 (Centralized Paths)
# ==========================================
export HP_CONF_DIR="/etc/config"
export HP_CONF_FILE="${HP_CONF_DIR}/homeproxy"
export HP_RULE_DIR="/etc/homeproxy/ruleset"
export HPPC_TMP_DIR="/tmp/hppc"
export HPPC_BACKUP_DIR="/etc/hppc/backup"
export HPPC_MAIN_LOCK="/var/run/hppc_main.lock"

# ==========================================
# 颜色与日志系统 (Standard Logging)
# ==========================================
C_ERR='\033[31m'; C_OK='\033[32m'; C_WARN='\033[33m'; C_INFO='\033[36m'; C_RESET='\033[0m'

log_info()    { printf "${C_INFO}[INFO]${C_RESET} %s\n" "$1"; }
log_success() { printf "${C_OK}[SUCCESS]${C_RESET} %s\n" "$1"; }
log_warn()    { printf "${C_WARN}[WARN]${C_RESET} %s\n" "$1"; }
log_err()     { printf "${C_ERR}[ERROR]${C_RESET} %s\n" "$1"; }

# ==========================================
# 消息通知 (Notifications)
# ==========================================
tg_send() {
    [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ] && return 0
    local msg="$1"
    # 异步推送通知，防止阻塞主进程
    curl -sk -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TG_CHAT_ID" -d "parse_mode=HTML" -d "text=$msg" > /dev/null 2>&1 &
}

# ==========================================
# 核心 IO: 安全下载防线 (Safe Download)
# ==========================================
# 参数: $1=URL, $2=目标路径
# 返回: 0=成功, 1=失败
safe_download() {
    local url="$1"
    local dest="$2"
    local insecure_flag="-k"
    
    # TLS 严格模式校验 (从环境变量读取，默认为非严格以适配国内网络)
    if [ "$INSECURE_CURL" = "0" ]; then
        insecure_flag=""
    fi

    # 设置 15 秒连接超时，30 秒最大传输时间，最多重试 2 次
    if curl $insecure_flag -sL --connect-timeout 15 --max-time 30 --retry 2 -f "$url" -o "$dest"; then
        # 检查文件是否存在且非空，并拦截 GitHub 报错返回的 HTML 页面
        if [ -s "$dest" ] && ! head -n 1 "$dest" | grep -qiE "<!DOCTYPE|<html"; then
            return 0
        fi
    fi
    
    # 下载失败或内容被污染，清理残次品
    rm -f "$dest"
    return 1
}

# ==========================================
# 智能别名系统 (Alias System)
# ==========================================

# [正向翻译] 意图(ID) -> 物理文件名(Filename)
id_to_filename() {
    local id="$1"
    case "$id" in
        # --- [特殊别名映射] ---
        geositenoncn)          echo "geosite-geolocation-!cn" ;;
        geositecategoryadsall) echo "geosite-category-ads-all" ;;
        geositehineteca)       echo "geosite-hinet-eca" ;;
        # --- [通用前缀映射] ---
        geosite*)              echo "geosite-${id#geosite}" ;;
        geoip*)                echo "geoip-${id#geoip}" ;;
        *)                     echo "$id" ;;
    esac
}

# [反向翻译] 物理文件名(Filename) -> 意图(ID)
filename_to_id() {
    local fname="$1"
    case "$fname" in
        # --- [特殊别名映射] ---
        geosite-geolocation-\!cn) echo "geositenoncn" ;;
        geosite-category-ads-all) echo "geositecategoryadsall" ;;
        geosite-hinet-eca)        echo "geositehineteca" ;;
        # --- [通用前缀映射] ---
        geosite-*)                echo "geosite${fname#geosite-}" ;;
        geoip-*)                  echo "geoip${fname#geoip-}" ;;
        *)                        echo "$fname" ;;
    esac
}
