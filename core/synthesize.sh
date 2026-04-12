#!/bin/sh
# --- [ HPPC Core: 炼金术士 (Synthesize) v3.5 智能按需版 ] ---
# 职责：解析意图 -> 批量申领 -> 安全熔断 -> 动态铸造 -> 战报通报

source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

# 资源路径
TMP_BASE="/tmp/hp_base.uci"
TMP_NODES="/tmp/hp_nodes.uci"
TMP_GROUPS="/tmp/hp_groups.uci"
TMP_RULES="/tmp/hp_rules.uci"     # 新增：动态生成的规则集配置
REQ_LIST="/tmp/hp_assets.req"     # 新增：申领清单
SUCCESS_LIST="/tmp/hp_assets.success" 
FINAL_CONF="/etc/config/homeproxy"
TEMPLATE_DIR="/usr/share/hppc/templates/models"
COUNT_FILE="/tmp/hp_counts"
MODULE_ASSETS="/usr/share/hppc/modules/assets.sh"

# ==========================================
# 1. 核心算法：意图平移 (The Strategy Shift)
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
# 主流程 (The Grand Process)
# ==========================================

echo -n > "$TMP_NODES"
echo -n > "$TMP_GROUPS"
echo -n > "$TMP_RULES"

# --- 检阅兵力 (Counting) ---
log_info "正在检阅各家族兵力..."
if ! command -v jq >/dev/null 2>&1; then
    log_err "缺少翻译官 (jq)，请执行 opkg install jq"
    exit 1
fi

JSON_FILE="/tmp/hppc_nodes.json"
if [ ! -f "$JSON_FILE" ]; then
    log_err "没有找到节点情报 ($JSON_FILE)，请先执行 '集结' (Fetch)。"
    exit 1
fi

JSON_DATA=$(cat "$JSON_FILE" | jq -c '.outbounds')
AIRPORTS=$(echo "$JSON_DATA" | jq -r '.[] | .tag' | grep -iE -e '-(HK|SG|TW|JP|US)' | sed -E 's/-(HK|SG|TW|JP|US|hk|sg|tw|jp|us).*//' | awk '{ if(!x[$NF]++) print $NF }')

echo -n > "$COUNT_FILE"
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

# --- 重塑战术意图 (Mapping) ---
log_info "正在重塑战术意图 (Hp_Base)..."
BASE_TEMPLATE="/usr/share/hppc/templates/hp_base.uci"

if [ ! -f "$BASE_TEMPLATE" ]; then
    log_err "战术蓝图缺失 ($BASE_TEMPLATE)，请升级脚本。"
    exit 1
fi

cp "$BASE_TEMPLATE" "$TMP_BASE.raw"
echo -n > "$TMP_BASE"

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

# ==========================================
# [全新阶段] 意图感知与物资申领 (Requisition)
# ==========================================
log_info "正在扫描战术意图，签发物资申领单..."
grep "list rule_set" "$TMP_BASE" | awk -F"'" '{print $2}' | awk '!x[$0]++' > "/tmp/hp_assets_id.list"

echo -n > "$REQ_LIST"
while read -r id; do
    [ -n "$id" ] && id_to_filename "$id" >> "$REQ_LIST"
done < "/tmp/hp_assets_id.list"

if [ -f "$MODULE_ASSETS" ]; then
    sh "$MODULE_ASSETS" --fetch-list "$REQ_LIST"
else
    log_err "物资代官 (Assets) 擅离职守，防线铸造中止！"
    exit 1
fi

# ==========================================
# [全新阶段] 安全熔断与动态铸造 (Dynamic Casting)
# ==========================================
log_info "正在执行动态铸造与安全熔断排查..."

SUCCESS_IDS=" "
if [ -f "$SUCCESS_LIST" ]; then
    while read -r fname; do
        [ -n "$fname" ] && SUCCESS_IDS="${SUCCESS_IDS}$(filename_to_id "$fname") "
    done < "$SUCCESS_LIST"
fi

mv "$TMP_BASE" "$TMP_BASE.raw2"
echo -n > "$TMP_BASE"
MISSING_COUNT=0

# 1. 熔断剔除
while IFS= read -r line; do
    if echo "$line" | grep -q "list rule_set"; then
        id=$(echo "$line" | awk -F"'" '{print $2}')
        if echo "$SUCCESS_IDS" | grep -q " $id "; then
            echo "$line" >> "$TMP_BASE"
        else
            log_warn "⚔️ 剔除失效意图: 舍弃规则引用 [$id] 以保全主阵型。"
            MISSING_COUNT=$((MISSING_COUNT + 1))
        fi
    else
        echo "$line" >> "$TMP_BASE"
    fi
done < "$TMP_BASE.raw2"
rm "$TMP_BASE.raw2"

# 2. 动态铸造
for id in $SUCCESS_IDS; do
    [ -z "$id" ] && continue
    fname=$(id_to_filename "$id")
    fpath="/etc/homeproxy/ruleset/$fname.srs"
    rtype="geoip"
    echo "$fname" | grep -q "^geosite" && rtype="geosite"

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

# --- 组建固定编制战队 ---
log_info "正在组建固定编制战队..."
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

# --- 注入瓦雷利亚节点 ---
log_info "正在注入瓦雷利亚节点 (智能映射模式)..."
echo "$JSON_DATA" | jq -c '.[]' | while read -r row; do
    LABEL=$(echo "$row" | jq -r '.tag')
    ID=$(echo -n "$LABEL" | md5sum | awk '{print $1}')
    TYPE=$(echo "$row" | jq -r '.type')
    SNIP="$TEMPLATE_DIR/${TYPE}.uci"
    
    if [ -f "$SNIP" ]; then
        SERVER=$(echo "$row" | jq -r '.server')
        PORT=$(echo "$row" | jq -r '.server_port')
        PASSWORD=$(echo "$row" | jq -r '.password // empty')
        UUID=$(echo "$row" | jq -r '.uuid // empty')
        METHOD=$(echo "$row" | jq -r '.method // empty')
        
        [ "$(echo "$row" | jq -r '.tls.enabled // false')" = "true" ] && TLS="1" || TLS="0"
        [ "$(echo "$row" | jq -r '.tls.insecure // false')" = "true" ] && INSECURE="1" || INSECURE="0"
        SNI=$(echo "$row" | jq -r '.tls.server_name // .host // .server')
        ALPN=$(echo "$row" | jq -r '.tls.alpn[0] // "h3"')
        RAW_UTLS=$(echo "$row" | jq -r '.tls.utls // empty')
        [ "$RAW_UTLS" = "null" ] && UTLS_VAL="chrome" || UTLS_VAL=$(echo "$RAW_UTLS" | jq -r '.fingerprint // "chrome"')

        FLOW=$(echo "$row" | jq -r '.flow // empty')
        CONGESTION=$(echo "$row" | jq -r '.congestion_control // "bbr"')
        
        PK=$(echo "$row" | jq -r '.tls.reality.public_key // empty')
        SID=$(echo "$row" | jq -r '.tls.reality.short_id // empty')
        if [ -n "$PK" ] && [ "$PK" != "null" ]; then
             REALITY_ENABLE="1"
        else
             REALITY_ENABLE="0"
             PK=""; SID=""
        fi

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
            >> "$TMP_NODES"
            
        echo "" >> "$TMP_NODES"
    fi
done

# --- 最终合并与战报通报 ---
if [ -s "$TMP_BASE" ] && [ -s "$TMP_NODES" ]; then
    # 严格按照层级组合配置：基础意图 -> 动态规则集 -> 固定编制战队 -> 具体兵源节点
    cat "$TMP_BASE" "$TMP_RULES" "$TMP_GROUPS" "$TMP_NODES" > "$FINAL_CONF"
else
    log_err "熔炼材料缺失，中止合并！"
    exit 1
fi

if [ -s "$FINAL_CONF" ]; then
    cp "$FINAL_CONF" "/etc/config/homeproxy.bak"
    log_success "配置熔炼完成 (新配置已就绪)。"
    
    stats=$(cat $COUNT_FILE | tr '\n' ' ' | sed 's/=$//')
    rand=$(hexdump -n 1 -e '/1 "%u"' /dev/urandom)
    case $((rand % 5)) in
        0) msg="🕯️ 报告领主，【$LOCATION】城墙蓝图已重绘。瓦雷利亚钢已熔炼完毕。" ;;
        1) msg="🦅 渡鸦传信：【$LOCATION】新阵型演练完成。预备守军分布：$stats" ;;
        2) msg="🍷 领主大人，【$LOCATION】的新装备已入库，随时可以换装！" ;;
        3) msg="❄️ 凛冬将至，但【$LOCATION】的炉火正旺。新配置已生成，静候指令。" ;;
        4) msg="🐉 龙焰重铸！【$LOCATION】积木已归位，只待您一声令下！" ;;
    esac
    
    if [ "$MISSING_COUNT" -gt 0 ]; then
        msg="${msg}%0A%0A⚠️ <b>战损警报:</b> <i>发现 $MISSING_COUNT 个无效规则集，已执行战术熔断（剔除），系统基础运行不受影响。</i>"
    fi
    
    tg_send "${msg}%0A%0A⚔️ <b>指令:</b> <i>语法检阅通过，请择机手动重启防线。</i>"
else
    log_err "熔炼失败 (生成结果为空)！"
    exit 1
fi
