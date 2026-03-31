#!/bin/sh
# --- HPPC: The Raven Scrolls (通用库) v3.5 ---

# 强制声明 PATH，防止 Cron 环境下找不到 jq 或 curl
export PATH='/usr/sbin:/usr/bin:/sbin:/bin'

# 颜色定义：坦格利安红，提利尔绿，史塔克白
C_ERR='\033[31m'; C_OK='\033[32m'; C_WARN='\033[33m'; C_INFO='\033[36m'; C_RESET='\033[0m'

# 日志风格：统一为 [角色] 消息
log_info()    { echo -e "${C_INFO}[渡鸦]${C_RESET} $1"; }
log_success() { echo -e "${C_OK}[捷报]${C_RESET} $1"; }
log_warn()    { echo -e "${C_WARN}[警示]${C_RESET} $1"; }
log_err()     { echo -e "${C_ERR}[噩耗]${C_RESET} $1"; }

# TG 推送：权游风战报
tg_send() {
    [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ] && return
    local msg="$1"
    curl -sk -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TG_CHAT_ID" -d "parse_mode=HTML" -d "text=$msg" > /dev/null 2>&1 &
}

# --- [新增] 智能别名系统 (Alias System) ---

# [正向翻译] 意图(ID) -> 物资名(Filename)
id_to_filename() {
    local id="$1"
    case "$id" in
        # --- [特殊别名录入区] ---
        geositenoncn)    echo "geosite-geolocation-!cn" ;;
        geositeadsall)   echo "geosite-category-ads-all" ;;
        geositehineteca) echo "geosite-hinet-eca" ;;
        # --- [通用规则区] ---
        geosite*)        echo "geosite-${id#geosite}" ;;
        geoip*)          echo "geoip-${id#geoip}" ;;
        *)               echo "$id" ;;
    esac
}

# [反向翻译] 物资名(Filename) -> 意图(ID)
filename_to_id() {
    local fname="$1"
    case "$fname" in
        # --- [特殊别名录入区] ---
        geosite-geolocation-\!cn) echo "geositenoncn" ;;
        geosite-category-ads-all) echo "geositeadsall" ;;
        geosite-hinet-eca)        echo "geositehineteca" ;;
        # --- [通用规则区] ---
        geosite-*)                echo "geosite${fname#geosite-}" ;;
        geoip-*)                  echo "geoip${fname#geoip-}" ;;
        *)                        echo "$fname" ;;
    esac
}
