#!/bin/sh
# --- [ HPPC Core: 节点获取 (Fetch) v3.6 ] ---
# 职责：拉取远端节点 JSON (Endpoint: /fetch-nodes) 并校验格式
# 修复：接入 safe_download 防线；强化 JSON 校验机制。

. /etc/hppc/hppc.conf
. /usr/share/hppc/lib/utils.sh

TEMP_JSON="$HPPC_TMP_DIR/nodes_download.json"
FINAL_JSON="/tmp/hppc_nodes.json"
TICK_FILE="/etc/hppc/last_tick"

mkdir -p "$HPPC_TMP_DIR"

log_info "正在向远端节点库 ($CF_DOMAIN) 请求数据同步..."

# 1. 安全下载
if ! safe_download "https://$CF_DOMAIN/fetch-nodes?token=$CF_TOKEN" "$TEMP_JSON"; then
    log_err "节点数据获取失败，请检查网络连通性或 Token 权限。"
    exit 1
fi

# 2. 严格校验 (防止 HTML 错误页或残缺 JSON 破坏配置)
if ! jq empty "$TEMP_JSON" >/dev/null 2>&1; then
    log_err "节点数据损坏 (JSON 语法错误)，本次拉取作废。"
    rm -f "$TEMP_JSON"
    exit 1
fi

# 3. 入库生效
mv "$TEMP_JSON" "$FINAL_JSON"

# 4. 同步时间戳防重发
CURRENT_TICK=$(curl -skL --connect-timeout 5 "https://$CF_DOMAIN/tg-sync?token=$CF_TOKEN")
if [ -n "$CURRENT_TICK" ] && [ "$CURRENT_TICK" != "Unauthorized" ]; then
    echo "$CURRENT_TICK" > "$TICK_FILE"
fi

log_success "最新节点数据已成功拉取并校验通过。"
