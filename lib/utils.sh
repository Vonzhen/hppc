#!/bin/sh
# --- HPPC: The Raven Scrolls (通用库) ---

# [修复] 强制声明 PATH，防止 Cron 环境下找不到 jq 或 curl
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
    # 在所有消息前加上家族纹章或抬头，这里已经在脚本调用时决定了内容
    curl -sk -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TG_CHAT_ID" -d "parse_mode=HTML" -d "text=$msg" > /dev/null 2>&1 &
}
