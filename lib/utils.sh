#!/bin/sh
# --- [ HPPC: The Raven Scrolls (渡鸦与学士通用律法) v4.1 修复版 ] ---

export PATH='/usr/sbin:/usr/bin:/sbin:/bin'

# ==========================================
# Category A: 系统核心路径 (从 hppc.conf 剥离，强制声明)
# ==========================================
export DIR_BASE="/usr/share/hppc"
export DIR_CORE="${DIR_BASE}/core"
export DIR_MODULES="${DIR_BASE}/modules"
export DIR_TEMPLATES="${DIR_BASE}/templates"
export DIR_TMP="/tmp/hppc"
export FILE_CONF_PROD="/etc/config/homeproxy"
export FILE_LOCK="/var/run/hppc.lock"

# 强制确保隔离工作区在内存中存活
mkdir -p "$DIR_TMP"

# 加载用户誓言卷轴 (仅限 Token/配置开关)
[ -f "/etc/hppc/hppc.conf" ] && . "/etc/hppc/hppc.conf"

# 防御性默认值兜底 (万一用户配置中缺失)
export SETTING_AUTO_RELOAD=${SETTING_AUTO_RELOAD:-0}
export SETTING_INSECURE_SKIP_VERIFY=${SETTING_INSECURE_SKIP_VERIFY:-0}

C_ERR='\033[31m'; C_OK='\033[32m'; C_WARN='\033[33m'; C_INFO='\033[36m'; C_RESET='\033[0m'

# 日志与断言
log_info()    { echo -e "${C_INFO}[$(date +'%Y-%m-%d %H:%M:%S')][INFO][渡鸦]${C_RESET} $1"; }
log_success() { echo -e "${C_OK}[$(date +'%Y-%m-%d %H:%M:%S')][OK][捷报]${C_RESET} $1"; }
log_warn()    { echo -e "${C_WARN}[$(date +'%Y-%m-%d %H:%M:%S')][WARN][警示]${C_RESET} $1"; }
log_err()     { echo -e "${C_ERR}[$(date +'%Y-%m-%d %H:%M:%S')][ERR][噩耗]${C_RESET} $1"; }

exit_on_error() {
    local exit_code=$1
    local msg=$2
    if [ "$exit_code" -ne 0 ]; then
        log_err "$msg (Exit Code: $exit_code)"
        exit "$exit_code"
    fi
}

# TG 战报
tg_send() {
    [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ] && return
    local msg="$1"
    local curl_opts="-s -X POST"
    [ "$SETTING_INSECURE_SKIP_VERIFY" = "1" ] && curl_opts="$curl_opts -k"
    curl $curl_opts "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TG_CHAT_ID" -d "parse_mode=HTML" -d "text=$msg" > /dev/null 2>&1 &
}

# 意图(ID) -> 物资名(Filename)
id_to_filename() {
    local id="$1"
    case "$id" in
        geositenoncn)          echo "geosite-geolocation-!cn" ;;
        geositecategoryadsall) echo "geosite-category-ads-all" ;;
        geositehineteca)       echo "geosite-hinet-eca" ;;
        geosite*)              echo "geosite-${id#geosite}" ;;
        geoip*)                echo "geoip-${id#geoip}" ;;
        *)                     echo "$id" ;;
    esac
}

# 物资名(Filename) -> 意图(ID)
filename_to_id() {
    local fname="$1"
    case "$fname" in
        geosite-geolocation-\!cn) echo "geositenoncn" ;;
        geosite-category-ads-all) echo "geositecategoryadsall" ;;
        geosite-hinet-eca)        echo "geositehineteca" ;;
        geosite-*)                echo "geosite${fname#geosite-}" ;;
        geoip-*)                  echo "geoip${fname#geoip-}" ;;
        *)                        echo "$fname" ;;
    esac
}
