#!/bin/sh
# --- [ HPPC Core: 集结号 (Fetch) v3.1 ] ---
# 职责：下载节点 JSON 并同步时间戳

source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

JSON_OUTPUT="/tmp/hppc_nodes.json"
TICK_FILE="/etc/hppc/last_tick"
URL="https://$CF_DOMAIN/sub?token=$CF_TOKEN"
INCOMING_TICK="$1" # 接收哨兵传来的 Tick

log_info "正在连接学城..."

# 下载并保存 Header
if curl -skL --connect-timeout 15 --retry 3 -D /tmp/hp_headers.txt -o "$JSON_OUTPUT" "$URL"; then
    if [ -s "$JSON_OUTPUT" ] && head -n 1 "$JSON_OUTPUT" | grep -q "{"; then
        log_success "节点情报已获取。"
        
        # 更新 Tick
        if [ -n "$INCOMING_TICK" ]; then
            NEW_TICK="$INCOMING_TICK"
        else
            # 手动运行时提取 Header
            NEW_TICK=$(grep -i "Last-Modified:" /tmp/hp_headers.txt | cut -d' ' -f2- | tr -d '\r')
            [ -z "$NEW_TICK" ] && NEW_TICK=$(grep -i "ETag:" /tmp/hp_headers.txt | cut -d' ' -f2- | tr -d '\r"')
            [ -z "$NEW_TICK" ] && NEW_TICK=$(date +"%Y-%m-%d %H:%M:%S")
        fi
        echo "$NEW_TICK" > "$TICK_FILE"
        rm -f /tmp/hp_headers.txt
        exit 0
    fi
fi
rm -f /tmp/hp_headers.txt; exit 1
