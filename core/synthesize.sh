#!/bin/sh
# --- [ HPPC Core: 炼金术士 (Synthesize) ] ---
# 职责：解析节点 -> 意图平移 -> 铸造防线 -> 发送战报

source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

# 资源路径
TMP_BASE="/tmp/hp_base.uci"
TMP_NODES="/tmp/hp_nodes.uci"
TMP_GROUPS="/tmp/hp_groups.uci"
FINAL_CONF="/etc/config/homeproxy"
TEMPLATE_DIR="/usr/share/hppc/templates/models"
COUNT_FILE="/tmp/hp_counts"

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
    
    # --- 分层随机注入 (Tiered Random Injection) ---
    if [ "$num" -le 3 ]; then
        # 前排精锐 (Top 50%)
        local limit=$(( (N + 1) / 2 ))
        local rand_idx=$(( (seed % (limit > 0 ? limit : 1)) + 1 ))
        printf "%s%02d" "$reg" "$rand_idx"
    else
        # 后备军团 (Bottom 50%)
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

# 1. 准备熔炉
mkdir -p $(dirname "$TMP_BASE")
echo -n > "$TMP_NODES"; echo -n > "$TMP_GROUPS"

# 2. 检阅兵力 (Counting)
log_info "正在检阅各家族兵力..."
JSON_DATA=$(cat /tmp/hppc_nodes.json | jq -c '.outbounds')
AIRPORTS=$(echo "$JSON_DATA" | jq -r '.[] | .tag' | awk '{print $2}' | awk -F'-' '{print $1}' | awk '!x[$0]++')

echo -n > "$COUNT_FILE"
REGIONS="HK SG TW JP US"

for reg in $REGIONS; do
    count=0
    lower_reg=$(echo "$reg" | tr 'A-Z' 'a-z')
    for ap in $AIRPORTS; do
        has_nodes=$(echo "$JSON_DATA" | jq -r ".[] | select(.tag | contains(\"$ap\")) | select(.tag | contains(\"$reg\")) | .tag" | head -1)
        [ -n "$has_nodes" ] && count=$((count + 1))
    done
    echo "${lower_reg}=${count}" >> "$COUNT_FILE"
done

# 3. 重塑战术意图 (Mapping)
log_info "正在重塑战术意图 (Hp_Base)..."
cp "/usr/share/hppc/templates/hp_base.uci" "$TMP_BASE.raw"
rm -f "$TMP_BASE"

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

# 4. 组建固定编制 (Groups)
log_info "正在组建固定编制战队..."
for reg in $REGIONS; do
    idx=1; lower_reg=$(echo "$reg" | tr 'A-Z' 'a-z')
    case "$reg" in "HK") flag="🇭🇰" ;; "SG") flag="🇸🇬" ;; "TW") flag="🇹🇼" ;; "JP") flag="🇯🇵" ;; "US") flag="🇺🇸" ;; esac
    
    for ap in $AIRPORTS; do
        node_tags=$(echo "$JSON_DATA" | jq -r ".[] | select(.tag | contains(\"$ap\")) | select(.tag | contains(\"$reg\")) | .tag")
        if [ -n "$node_tags" ]; then
            group_id="${lower_reg}$(printf "%02d" $idx)"
            echo "config routing_node '$group_id'" >> "$TMP_GROUPS"
            echo "    option label '$flag $reg-$ap'"
            echo "    option node 'urltest'"
            echo "    option enabled '1'"
            echo "    option urltest_tolerance '150'"
            echo "    option urltest_interrupt_exist_connections '1'"
            echo "$node_tags" | while read tag; do
                nid=$(echo -n "$tag" | md5sum | awk '{print $1}')
                echo "    list urltest_nodes '$nid'"
            done
            echo "" >> "$TMP_GROUPS"
            idx=$((idx + 1))
        fi
    done
done

# 5. 注入瓦雷利亚节点 (Nodes)
log_info "正在注入瓦雷利亚节点..."
echo "$JSON_DATA" | jq -c '.[]' | while read -r row; do
    LABEL=$(echo "$row" | jq -r '.tag')
    ID=$(echo -n "$LABEL" | md5sum | awk '{print $1}')
    TYPE=$(echo "$row" | jq -r '.type')
    SNIP="$TEMPLATE_DIR/${TYPE}.uci"
    
    if [ -f "$SNIP" ]; then
        RAW_UTLS=$(echo "$row" | jq -r '.tls.utls // empty')
        [ "$RAW_UTLS" = "null" ] && UTLS_VAL="chrome" || UTLS_VAL=$(echo "$RAW_UTLS" | jq -r '.fingerprint // "chrome"')
        [ "$(echo "$row" | jq -r '.tls.insecure // false')" = "true" ] && INSECURE="1" || INSECURE="0"
        [ "$(echo "$row" | jq -r '.tls.enabled // true')" = "true" ] && TLS="1" || TLS="0"
        FLOW=$(echo "$row" | jq -r '.flow // empty')
        
        content=$(cat "$SNIP")
        content=$(echo "$content" | sed \
            -e "s/{{ID}}/$ID/g" -e "s/{{LABEL}}/$LABEL/g" \
            -e "s/{{SERVER}}/$(echo "$row" | jq -r '.server')/g" \
            -e "s/{{PORT}}/$(echo "$row" | jq -r '.server_port')/g" \
            -e "s/{{PASSWORD}}/$(echo "$row" | jq -r '.password // empty')/g" \
            -e "s/{{UUID}}/$(echo "$row" | jq -r '.uuid // empty')/g" \
            -e "s/{{METHOD}}/$(echo "$row" | jq -r '.method // empty')/g" \
            -e "s/{{SNI}}/$(echo "$row" | jq -r '.tls.server_name // .server')/g" \
            -e "s/{{INSECURE}}/$INSECURE/g" -e "s/{{TLS}}/$TLS/g" \
            -e "s/{{UTLS}}/$UTLS_VAL/g" -e "s/{{FLOW}}/$FLOW/g")
            
        PK=$(echo "$row" | jq -r '.tls.reality.public_key // empty')
        SID=$(echo "$row" | jq -r '.tls.reality.short_id // empty')
        if [ -n "$PK" ] && [ "$PK" != "null" ]; then
             content=$(echo "$content" | sed -e "s/{{REALITY_ENABLE}}/1/g" -e "s/{{REALITY_PK}}/$PK/g" -e "s/{{REALITY_SID}}/$SID/g")
        else
             content=$(echo "$content" | sed -e "s/{{REALITY_ENABLE}}/0/g")
        fi
        echo "$content" >> "$TMP_NODES"; echo "" >> "$TMP_NODES"
    fi
done

# 6. 最终合并
cat "$TMP_BASE" "$TMP_NODES" "$TMP_GROUPS" > "$FINAL_CONF"

# 7. 战报通报 (The Raven's Scroll)
if [ -s "$FINAL_CONF" ]; then
    cp "$FINAL_CONF" "/etc/config/homeproxy.bak"
    log_success "配置熔炼完成 (未重启)。"
    
    # --- 权游风随机战报 ---
    stats=$(cat $COUNT_FILE | tr '\n' ' ' | sed 's/=$//')
    rand=$(hexdump -n 1 -e '/1 "%u"' /dev/urandom)
    case $((rand % 5)) in
        0) msg="🕯️ 报告领主，【$LOCATION】城墙已加固。瓦雷利亚钢已熔炼完毕，丝滑度更胜往昔！" ;;
        1) msg="🦅 渡鸦传信：【$LOCATION】已完成阵型变换。当前守军分布：$stats" ;;
        2) msg="🍷 领主大人，【$LOCATION】的守卫已换上新甲，列阵待命，请下达攻坚指令！" ;;
        3) msg="❄️ 凛冬将至，但【$LOCATION】的炉火正旺。配置已自我进化，现在的守御坚不可摧。" ;;
        4) msg="🐉 龙焰重铸！【$LOCATION】所有积木已归位，正以 $stats 之势封锁边境！" ;;
    esac
    
    tg_send "$msg\n\n⚠️ <b>指令:</b> <i>请手动重启 (/etc/init.d/homeproxy restart)</i>"
else
    log_err "熔炼失败 (配置文件为空)！"
    exit 1
fi
