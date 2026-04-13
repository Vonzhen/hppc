#!/bin/sh
# --- [ HPPC Core: 配置合成 (Synthesize) v3.6.8 完美排版版 ] ---
# 职责：解析路由策略 -> 生成规则申领单 -> 验证可用性熔断 -> 影子合并与自检 -> 状态通报
# 修复：解决各节点之间空行排版不一致的问题，保持配置文件绝对整洁

. /etc/hppc/hppc.conf
. /usr/share/hppc/lib/utils.sh

TMP_BASE="/tmp/hp_base.uci"
TMP_NODES="/tmp/hp_nodes.uci"
TMP_GROUPS="/tmp/hp_groups.uci"
TMP_RULES="/tmp/hp_rules.uci"
REQ_LIST="/tmp/hp_assets.req"
SUCCESS_LIST="/tmp/hp_assets.success" 
FINAL_CONF="/etc/config/homeproxy"
TEMPLATE_DIR="/usr/share/hppc/templates/models"
COUNT_FILE="/tmp/hp_counts"
MODULE_ASSETS="/usr/share/hppc/modules/assets.sh"

# ==========================================
# 1. 核心算法：节点负载映射
# ==========================================
map_logic() {
    local val=$(echo "$1" | tr -d "' \t\r\n")
    [ "$val" = "direct-out" ] || [ "$val" = "blackhole-out" ] || [ "$val" = "default-out" ] && echo "$val" && return
    
    local reg=$(echo "$val" | grep -oE "hk|tw|sg|jp|us" | head -1)
    [ -z "$reg" ] && echo "$val" && return
    
    local num_str=$(echo "$val" | grep -oE "[0-9]+" | sed 's/^0//')
    [ -z "$num_str" ] && local num=1 || local num=$num_str
    
    local N=$(grep "^${reg}=" "$COUNT_FILE" | cut -d'=' -f2)
    [ -z "$N" ] || [ "$N" -eq 0 ] && echo "${reg}01" && return

    local seed=$(hexdump -n 2 -e '/2 "%u"' /dev/urandom)
    
    if [ "$num" -le 3 ]; then
        local limit=$(( (N + 1) / 2 ))
        local rand_idx=$(( (seed % (limit > 0 ? limit : 1)) + 1 ))
        printf "%s%02d" "$reg" "$rand_idx"
    else
        local start=$(( N / 2 + 1 ))
        local range=$(( N - start + 1 ))
        local rand_idx=$(( (seed % (range > 0 ? range : 1)) + start ))
        [ "$rand_idx" -gt "$N" ] && rand_idx=$N
        printf "%s%02d" "$reg" "$rand_idx"
    fi
}

# ==========================================
# 主流程
# ==========================================
: > "$TMP_NODES"
: > "$TMP_GROUPS"
: > "$TMP_RULES"

log_info "正在统计各区域可用节点数量..."
if ! command -v jq >/dev/null 2>&1; then
    log_err "缺少 JSON 解析器 (jq)，请执行 opkg install jq"
    exit 1
fi

JSON_FILE="/tmp/hppc_nodes.json"
if [ ! -f "$JSON_FILE" ]; then
    log_err "未找到节点数据 ($JSON_FILE)，请先执行 Fetch 拉取更新。"
    exit 1
fi

JSON_DATA=$(cat "$JSON_FILE" | jq -c '.outbounds')
AIRPORTS=$(echo "$JSON_DATA" | jq -r '.[] | .tag' | grep -iE -e '-(HK|SG|TW|JP|US)' | sed -E 's/-(HK|SG|TW|JP|US|hk|sg|tw|jp|us).*//' | awk '{ if(!x[$NF]++) print $NF }')

: > "$COUNT_FILE"
REGIONS="HK SG TW JP US"

for reg in $REGIONS; do
    count=0
    lower_reg=$(echo "$reg" | tr 'A-Z' 'a-z')
    for ap in $AIRPORTS; do
        has_nodes=$(echo "$JSON_DATA" | jq -r '.[] | .tag' | grep -iF -e "${ap}-${reg}" | head -1)
        [ -n "$has_nodes" ] && count=$((count + 1))
    done
    echo "${lower_reg}=${count}" >> "$COUNT_FILE"
done

log_info "正在映射基础路由策略 (Hp_Base)..."
BASE_TEMPLATE="/usr/share/hppc/templates/hp_base.uci"

if [ ! -f "$BASE_TEMPLATE" ]; then
    log_err "路由基础蓝图缺失 ($BASE_TEMPLATE)，请检查模板文件。"
    exit 1
fi

cp "$BASE_TEMPLATE" "$TMP_BASE.raw"
: > "$TMP_BASE"

while IFS= read -r line; do
    if echo "$line" | grep -q "option outbound"; then
        val=$(echo "$line" | awk -F"'" '{print $2}')
        new_val=$(map_logic "$val")
        if [ "$val" != "$new_val" ]; then
            echo "$line" | sed "s/'$val'/'$new_val'/" >> "$TMP_BASE"
        else
            echo "$line" >> "$TMP_BASE"
        fi
    else
        echo "$line" >> "$TMP_BASE"
    fi
done < "$TMP_BASE.raw"
rm "$TMP_BASE.raw"

log_info "正在扫描配置引用，生成规则集更新清单..."
grep "list rule_set" "$TMP_BASE" | awk -F"'" '{print $2}' | awk '!x[$0]++' > "/tmp/hp_assets_id.list"

: > "$REQ_LIST"
while read -r id; do
    [ -n "$id" ] && id_to_filename "$id" >> "$REQ_LIST"
done < "/tmp/hp_assets_id.list"

if [ -f "$MODULE_ASSETS" ]; then
    sh "$MODULE_ASSETS" --fetch-list "$REQ_LIST"
else
    log_err "未找到 Assets 规则处理模块，配置生成中止！"
    exit 1
fi

log_info "正在执行规则集可用性检查与配置生成..."

SUCCESS_IDS=" "
if [ -f "$SUCCESS_LIST" ]; then
    while read -r fname; do
        [ -n "$fname" ] && SUCCESS_IDS="${SUCCESS_IDS}$(filename_to_id "$fname") "
    done < "$SUCCESS_LIST"
fi

mv "$TMP_BASE" "$TMP_BASE.raw2"
: > "$TMP_BASE"
MISSING_COUNT=0

while IFS= read -r line; do
    if echo "$line" | grep -q "list rule_set"; then
        id=$(echo "$line" | awk -F"'" '{print $2}')
        if echo "$SUCCESS_IDS" | grep -q " $id "; then
            echo "$line" >> "$TMP_BASE"
        else
            log_warn "⚠️ 剔除失效引用: 舍弃不可用的规则 [$id] 以保障基础连通性。"
            MISSING_COUNT=$((MISSING_COUNT + 1))
        fi
    else
        echo "$line" >> "$TMP_BASE"
    fi
done < "$TMP_BASE.raw2"
rm "$TMP_BASE.raw2"

for id in $SUCCESS_IDS; do
    [ -z "$id" ] && continue
    fname=$(id_to_filename "$id")
    fpath="/etc/homeproxy/ruleset/$fname.srs"

    {
        echo "config ruleset '$id'"
        echo "    option label '$fname'"
        echo "    option enabled '1'"
        echo "    option type 'local'"
        echo "    option format 'binary'"
        echo "    option path '$fpath'"
        echo ""
    } >> "$TMP_RULES"
done

log_info "正在组建区域负载均衡组 (Routing Nodes)..."
for reg in $REGIONS; do
    idx=1
    lower_reg=$(echo "$reg" | tr 'A-Z' 'a-z')
    case "$reg" in "HK") flag="🇭🇰" ;; "SG") flag="🇸🇬" ;; "TW") flag="🇹🇼" ;; "JP") flag="🇯🇵" ;; "US") flag="🇺🇸" ;; esac
    
    for ap in $AIRPORTS; do
        node_tags=$(echo "$JSON_DATA" | jq -r '.[] | .tag' | grep -iF -e "${ap}-${reg}")
        if [ -n "$node_tags" ]; then
            group_id="${lower_reg}$(printf "%02d" $idx)"
            {
                echo "config routing_node '$group_id'"
                echo "    option label '$flag $reg-$ap'"
                echo "    option node 'urltest'"
                echo "    option enabled '1'"
                echo "    option urltest_tolerance '150'"
                echo "    option urltest_interrupt_exist_connections '1'"
                echo "$node_tags" | while IFS= read -r tag; do
                    nid=$(echo -n "$tag" | md5sum | awk '{print $1}')
                    echo "    list urltest_nodes '$nid'"
                done
                echo "" 
            } >> "$TMP_GROUPS"
            idx=$((idx + 1))
        fi
    done
done

log_info "正在注入代理节点配置..."
echo "$JSON_DATA" | jq -c '.[]' | while read -r row; do
    LABEL=$(echo "$row" | jq -r '.tag')
    ID=$(echo -n "$LABEL" | md5sum | awk '{print $1}')
    TYPE=$(echo "$row" | jq -r '.type')
    SNIP="$TEMPLATE_DIR/${TYPE}.uci"
    NODE_TMP="/tmp/hp_node_single.uci"
    
    if [ -f "$SNIP" ]; then
        > "$NODE_TMP"
    
        # [独立提取模块] 彻底切断级联报错
        SERVER=$(echo "$row" | jq -r '.server // empty' 2>/dev/null)
        
        PORT=$(echo "$row" | jq -r '.server_port // empty' 2>/dev/null)
        [ -z "$PORT" ] || [ "$PORT" = "null" ] && PORT=$(echo "$row" | jq -r '.port // empty' 2>/dev/null)
        
        PASSWORD=$(echo "$row" | jq -r '.password // empty' 2>/dev/null)
        UUID=$(echo "$row" | jq -r '.uuid // empty' 2>/dev/null)
        METHOD=$(echo "$row" | jq -r '.method // empty' 2>/dev/null)
        
        TLS="0"
        if echo "$row" | jq -e '.tls == true or .tls.enabled == true' >/dev/null 2>&1; then
            TLS="1"
        fi
        
        INSECURE="0"
        if echo "$row" | jq -e '.tls.insecure == true' >/dev/null 2>&1; then
            INSECURE="1"
        fi
        
        WS_HOST=$(echo "$row" | jq -r '.transport.headers.Host // empty' 2>/dev/null)
        [ -z "$WS_HOST" ] || [ "$WS_HOST" = "null" ] && WS_HOST=$(echo "$row" | jq -r '."ws-opts".headers.Host // empty' 2>/dev/null)
        [ "$WS_HOST" = "null" ] && WS_HOST=""
        
        WS_PATH=$(echo "$row" | jq -r '.transport.path // empty' 2>/dev/null)
        [ -z "$WS_PATH" ] || [ "$WS_PATH" = "null" ] && WS_PATH=$(echo "$row" | jq -r '."ws-opts".path // empty' 2>/dev/null)
        [ "$WS_PATH" = "null" ] && WS_PATH=""
        
        SNI=$(echo "$row" | jq -r '.tls.server_name // empty' 2>/dev/null)
        [ -z "$SNI" ] || [ "$SNI" = "null" ] && SNI=$(echo "$row" | jq -r '.sni // empty' 2>/dev/null)
        [ -z "$SNI" ] || [ "$SNI" = "null" ] && SNI="$WS_HOST"
        [ -z "$SNI" ] || [ "$SNI" = "null" ] && SNI=$(echo "$row" | jq -r '.host // empty' 2>/dev/null)
        [ -z "$SNI" ] || [ "$SNI" = "null" ] && SNI="$SERVER"
        [ "$SNI" = "null" ] && SNI=""
        
        ALPN=$(echo "$row" | jq -r '.tls.alpn[0] // empty' 2>/dev/null)
        [ -z "$ALPN" ] || [ "$ALPN" = "null" ] && ALPN="h3"
        
        RAW_UTLS=$(echo "$row" | jq -r '.tls.utls // empty' 2>/dev/null)
        [ -z "$RAW_UTLS" ] || [ "$RAW_UTLS" = "null" ] && UTLS_VAL="" || UTLS_VAL=$(echo "$RAW_UTLS" | jq -r '.fingerprint // empty' 2>/dev/null)
        [ "$UTLS_VAL" = "null" ] && UTLS_VAL=""

        FLOW=$(echo "$row" | jq -r '.flow // empty' 2>/dev/null)
        CONGESTION=$(echo "$row" | jq -r '.congestion_control // empty' 2>/dev/null)
        [ -z "$CONGESTION" ] || [ "$CONGESTION" = "null" ] && CONGESTION="bbr"
        
        PK=$(echo "$row" | jq -r '.tls.reality.public_key // empty' 2>/dev/null)
        SID=$(echo "$row" | jq -r '.tls.reality.short_id // empty' 2>/dev/null)
        if [ -n "$PK" ] && [ "$PK" != "null" ]; then
             REALITY_ENABLE="1"
        else
             REALITY_ENABLE="0"
             PK=""; SID=""
        fi

        ALTER_ID=$(echo "$row" | jq -r '.alter_id // empty' 2>/dev/null)
        [ -z "$ALTER_ID" ] || [ "$ALTER_ID" = "null" ] && ALTER_ID=$(echo "$row" | jq -r '.alterId // empty' 2>/dev/null)
        [ -z "$ALTER_ID" ] || [ "$ALTER_ID" = "null" ] && ALTER_ID="0"
        
        CIPHER=$(echo "$row" | jq -r '.security // empty' 2>/dev/null)
        [ -z "$CIPHER" ] || [ "$CIPHER" = "null" ] && CIPHER=$(echo "$row" | jq -r '.cipher // empty' 2>/dev/null)
        [ -z "$CIPHER" ] || [ "$CIPHER" = "null" ] && CIPHER="auto"
        
        TRANSPORT=$(echo "$row" | jq -r '.transport.type // empty' 2>/dev/null)
        [ -z "$TRANSPORT" ] || [ "$TRANSPORT" = "null" ] && TRANSPORT=$(echo "$row" | jq -r '.network // empty' 2>/dev/null)
        [ -z "$TRANSPORT" ] || [ "$TRANSPORT" = "null" ] || [ "$TRANSPORT" = "tcp" ] && TRANSPORT=""

        cat "$SNIP" | sed \
            -e "s/{{ID}}/$ID/g" \
            -e "s/{{LABEL}}/$LABEL/g" \
            -e "s/{{SERVER}}/$SERVER/g" \
            -e "s/{{PORT}}/$PORT/g" \
            -e "s/{{PASSWORD}}/$PASSWORD/g" \
            -e "s/{{UUID}}/$UUID/g" \
            -e "s/{{METHOD}}/$METHOD/g" \
            -e "s/{{TLS}}/$TLS/g" \
            -e "s/{{SNI}}/$SNI/g" \
            -e "s/{{INSECURE}}/$INSECURE/g" \
            -e "s/{{ALPN}}/$ALPN/g" \
            -e "s/{{UTLS}}/$UTLS_VAL/g" \
            -e "s/{{FLOW}}/$FLOW/g" \
            -e "s/{{CONGESTION}}/$CONGESTION/g" \
            -e "s/{{REALITY_ENABLE}}/$REALITY_ENABLE/g" \
            -e "s/{{REALITY_PK}}/$PK/g" \
            -e "s/{{REALITY_SID}}/$SID/g" \
            -e "s|{{ALTER_ID}}|$ALTER_ID|g" \
            -e "s|{{CIPHER}}|$CIPHER|g" \
            -e "s|{{TRANSPORT}}|$TRANSPORT|g" \
            -e "s|{{WS_HOST}}|$WS_HOST|g" \
            -e "s|{{WS_PATH}}|$WS_PATH|g" \
            > "$NODE_TMP"

        if [ "$TLS" = "1" ] && ! grep -q "option tls_utls" "$NODE_TMP"; then
            echo "    option tls_utls '$UTLS_VAL'" >> "$NODE_TMP"
        fi
        
        if [ "$TYPE" = "vless" ] || [ "$TYPE" = "trojan" ]; then
            if [ "$REALITY_ENABLE" = "1" ] || grep -q "option tls_reality '1'" "$NODE_TMP"; then
                if ! grep -q "option tls_reality_short_id" "$NODE_TMP"; then
                    echo "    option tls_reality_short_id '$SID'" >> "$NODE_TMP"
                fi
                if ! grep -q "option tls_reality_public_key" "$NODE_TMP"; then
                    echo "    option tls_reality_public_key '$PK'" >> "$NODE_TMP"
                fi
            fi
            if [ "$TYPE" = "vless" ] && ! grep -q "option vless_flow" "$NODE_TMP"; then
                echo "    option vless_flow '$FLOW'" >> "$NODE_TMP"
            fi
        fi

        # [排版优化]：彻底清除临时文件中的多余空行，保证配置纯净
        sed -i '/^[[:space:]]*$/d' "$NODE_TMP"

        # 统一输出：每个纯净的节点块后，严格追加一个空行分割
        cat "$NODE_TMP" >> "$TMP_NODES"
        echo "" >> "$TMP_NODES"
    fi
done

# ==========================================
# 最终合并与影子自检
# ==========================================
if [ -s "$TMP_BASE" ] && [ -s "$TMP_NODES" ]; then
    
    SHADOW_DIR="/tmp/hppc_shadow"
    rm -rf "$SHADOW_DIR"
    mkdir -p "$SHADOW_DIR"
    SHADOW_CONF="$SHADOW_DIR/homeproxy"
    
    log_info "正在合成系统配置至内存沙盒..."
    cat "$TMP_BASE" "$TMP_RULES" "$TMP_GROUPS" "$TMP_NODES" > "$SHADOW_CONF"
    
    log_info "正在执行 UCI 语法安全自检..."
    if uci -q -c "$SHADOW_DIR" show homeproxy >/dev/null 2>&1; then
        log_success "✅ 语法自检通过，未发现关键逻辑损坏。"
        
        [ -f "$FINAL_CONF" ] && cp "$FINAL_CONF" "$FINAL_CONF.bak"
        cat "$SHADOW_CONF" > "$FINAL_CONF"
        rm -rf "$SHADOW_DIR"
        log_success "✅ 配置文件已成功原子化替换。"
        
        stats=$(cat $COUNT_FILE | tr '\n' ' ' | sed 's/=$//')
        msg="📊 <b>[${LOCATION}] 系统配置更新报告</b>%0A"
        msg="${msg}--------------------------------%0A"
        msg="${msg}✅ 节点与规则配置已重新生成并挂载。%0A"
        msg="${msg}🌍 区域节点存活情况: $stats"
        
        if [ "$MISSING_COUNT" -gt 0 ]; then
            msg="${msg}%0A%0A⚠️ <b>依赖异常:</b> <i>发现 $MISSING_COUNT 个不可用规则集，触发熔断，已被自动跳过。</i>"
        fi
        
        tg_send "${msg}%0A%0A🔄 <b>状态:</b> <i>自检通过，请择机触发重启使配置生效。</i>"
    else
        log_err "❌ 严重故障：生成的配置文件未通过 UCI 语法检查！"
        log_err "为保护系统网络稳定，已拦截本次覆盖，继续运行原有安全配置。"
        rm -rf "$SHADOW_DIR"
        exit 1
    fi
else
    log_err "❌ 源片段合并失败，核心组件缺失！"
    exit 1
fi
