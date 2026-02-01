#!/bin/sh
# --- [ HPPC Core: 军需官 (Fetch) v2.1] ---
# 职责：从学城拉取节点情报

source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

TEMP_JSON="/tmp/nodes_download.json"
FINAL_JSON="/tmp/hppc_nodes.json"

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
log_success "节点补给已入库，等待熔炼。"
