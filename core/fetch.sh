#!/bin/sh
# --- [ HPPC Core: 军需官 (Fetch) v2.2 Fixed ] ---
# 职责：从学城拉取节点情报 (Endpoint: /fetch-nodes)
# 修复：下载成功后自动同步时间戳，防止 Daemon 重复触发

source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

TEMP_JSON="/tmp/nodes_download.json"
FINAL_JSON="/tmp/hppc_nodes.json"
TICK_FILE="/etc/hppc/last_tick"

log_info "正在派遣渡鸦前往学城 ($CF_DOMAIN) 获取补给..."

# 1. 下载 (Download)
curl -skL --connect-timeout 15 "https://$CF_DOMAIN/fetch-nodes?token=$CF_TOKEN" -o "$TEMP_JSON"

# 2. 验货 (Validation)
if [ ! -s "$TEMP_JSON" ]; then
    log_err "渡鸦空手而归 (下载为空)，请检查 Token 或学城状态。"
    exit 1
fi

if ! jq empty "$TEMP_JSON" 2>/dev/null; then
    log_err "补给包已损坏 (JSON 格式错误)，丢弃。"
    rm -f "$TEMP_JSON"
    exit 1
fi

# 3. 入库 (Apply)
mv "$TEMP_JSON" "$FINAL_JSON"

# [新增] 4. 同步时间戳 (Sync Tick)
# 这一步是为了告诉后台哨兵：“我已经手动更新过了，你别再叫了”
CURRENT_TICK=$(curl -skL --connect-timeout 5 "https://$CF_DOMAIN/tg-sync?token=$CF_TOKEN")
if [ -n "$CURRENT_TICK" ] && [ "$CURRENT_TICK" -gt 0 ] 2>/dev/null; then
    echo "$CURRENT_TICK" > "$TICK_FILE"
    # log_info "版本号已同步: $CURRENT_TICK"
fi

log_success "节点补给已入库，等待熔炼。"
