#!/bin/sh
# --- [ HPPC: The Raven Scrolls (渡鸦与学士通用律法) v4.0 ] ---
# 职能：提供全疆域通用的渡鸦传信（结构化日志）、咒语解析（路径加载）与军械识别（别名翻译）

# 强制声明 PATH，防止 Cron (凛冬暗影) 环境下找不到 jq 或 curl
export PATH='/usr/sbin:/usr/bin:/sbin:/bin'

# 展开守夜人誓言卷轴 (加载配置常量)
[ -f "/etc/hppc/hppc.conf" ] && . "/etc/hppc/hppc.conf"

# 家族纹章色彩：坦格利安红，提利尔绿，兰尼斯特金，史塔克白
C_ERR='\033[31m'; C_OK='\033[32m'; C_WARN='\033[33m'; C_INFO='\033[36m'; C_RESET='\033[0m'

# ==========================================
# 结构化日志引擎 (Structured Logging System)
# ==========================================
# [军规] 必须使用此标准接口输出日志，禁止私自 echo 干扰战报序列
log_info()    { echo -e "${C_INFO}[$(date +'%Y-%m-%d %H:%M:%S')][INFO][渡鸦]${C_RESET} $1"; }
log_success() { echo -e "${C_OK}[$(date +'%Y-%m-%d %H:%M:%S')][OK][捷报]${C_RESET} $1"; }
log_warn()    { echo -e "${C_WARN}[$(date +'%Y-%m-%d %H:%M:%S')][WARN][警示]${C_RESET} $1"; }
log_err()     { echo -e "${C_ERR}[$(date +'%Y-%m-%d %H:%M:%S')][ERR][噩耗]${C_RESET} $1"; }

# 致命错误断言：一旦触发则立即拔剑熔断，停止后续逻辑编排
exit_on_error() {
    local exit_code=$1
    local msg=$2
    if [ "$exit_code" -ne 0 ]; then
        log_err "$msg (Exit Code: $exit_code)"
        exit "$exit_code"
    fi
}

# ==========================================
# 渡鸦网络 (Telegram 战报推送)
# ==========================================
tg_send() {
    [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ] && return
    local msg="$1"
    local curl_opts="-s -X POST"
    
    # 弱校验模式开关判定
    [ "$SETTING_INSECURE_SKIP_VERIFY" = "1" ] && curl_opts="$curl_opts -k"

    curl $curl_opts "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TG_CHAT_ID" -d "parse_mode=HTML" -d "text=$msg" > /dev/null 2>&1 &
}

# ==========================================
# 智能别名系统 (Alias Translation System)
# ==========================================

# [正向翻译] 意图(ID) -> 物资名(Filename)
id_to_filename() {
    local id="$1"
    case "$id" in
        # --- [特殊咒语录入区] ---
        geositenoncn)          echo "geosite-geolocation-!cn" ;;
        geositecategoryadsall) echo "geosite-category-ads-all" ;;
        geositehineteca)       echo "geosite-hinet-eca" ;;
        # --- [通用规则列阵] ---
        geosite*)              echo "geosite-${id#geosite}" ;;
        geoip*)                echo "geoip-${id#geoip}" ;;
        *)                     echo "$id" ;;
    esac
}

# [反向翻译] 物资名(Filename) -> 意图(ID)
filename_to_id() {
    local fname="$1"
    case "$fname" in
        # --- [特殊咒语录入区] ---
        geosite-geolocation-\!cn) echo "geositenoncn" ;;
        geosite-category-ads-all) echo "geositecategoryadsall" ;;
        geosite-hinet-eca)        echo "geositehineteca" ;;
        # --- [通用规则列阵] ---
        geosite-*)                echo "geosite${fname#geosite-}" ;;
        geoip-*)                  echo "geoip${fname#geoip-}" ;;
        *)                        echo "$fname" ;;
    esac
}
