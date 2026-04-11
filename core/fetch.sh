#!/bin/sh
# --- [ HPPC Core: 游骑兵营地 (Fetch Nodes) v4.2 完整防抖版 ] ---
# 职能：从学城拉取节点情报 (Endpoint: /fetch-nodes)
# 修复：下载成功后自动同步时间戳，防止 Daemon 哨兵重复触发；加入动态 TLS 与 JSON 防毒。

. /usr/share/hppc/lib/utils.sh

# ==========================================
# Category A: 路径常量与变量
# ==========================================
TEMP_JSON="$DIR_TMP/nodes_download.json.tmp"
FINAL_JSON="$DIR_TMP/hppc_nodes.json"
TICK_FILE="/etc/hppc/last_tick"

log_info "正在派遣渡鸦前往学城 ($CF_DOMAIN) 获取补给..."

# 动态组装军令状 (TLS 降级保护)
CURL_OPTS="-sL --connect-timeout 15"
[ "$SETTING_INSECURE_SKIP_VERIFY" = "1" ] && CURL_OPTS="-k $CURL_OPTS"

# ==========================================
# 1. 战地下载 (Download)
# ==========================================
if ! eval curl $CURL_OPTS "https://$CF_DOMAIN/fetch-nodes?token=$CF_TOKEN" -o "$TEMP_JSON"; then
    log_err "游骑兵未归！(Worker 连接超时或被截杀)"
    exit 1
fi

# ==========================================
# 2. 战利品验货 (Validation & Anti-Poisoning)
# ==========================================
if [ ! -s "$TEMP_JSON" ]; then
    log_err "渡鸦空手而归 (下载为空)，请检查 Token 或学城状态。"
    rm -f "$TEMP_JSON"
    exit 1
fi

if ! jq empty "$TEMP_JSON" >/dev/null 2>&1; then
    log_err "补给包已损坏 (非标准 JSON)，异鬼投毒防范生效，丢弃并熔断。"
    rm -f "$TEMP_JSON"
    exit 1
fi

# ==========================================
# 3. 兵源入库 (Apply)
# ==========================================
mv "$TEMP_JSON" "$FINAL_JSON"
NODE_COUNT=$(jq '. | length' "$FINAL_JSON" 2>/dev/null || echo "0")

# ==========================================
# 4. 同步时间戳 (Sync Tick)
# ==========================================
# 核心逻辑：告诉后台哨兵“我已经手动更新过了，无需重复拉响警报”
CURRENT_TICK=$(eval curl $CURL_OPTS "https://$CF_DOMAIN/tg-sync?token=$CF_TOKEN" 2>/dev/null)
if [ -n "$CURRENT_TICK" ] && [ "$CURRENT_TICK" -gt 0 ] 2>/dev/null; then
    echo "$CURRENT_TICK" > "$TICK_FILE"
    # log_info "号角频率已同步: $CURRENT_TICK"
fi

log_success "节点补给已入库，带回 $NODE_COUNT 名可战之兵，等待熔炼。"
exit 0
