#!/bin/sh
# --- [ HPPC Core: 炼金术士的熔炉 (Synthesize) v4.2 事务安全无损版 ] ---
# 职能：解析战术意图 -> 批量申领军械 -> 触发安全熔断 -> 隔离区动态铸造 -> 原子级替换 -> 战报通报
# 架构：PREPARE (生成) -> VERIFY (校验) -> COMMIT (原子替换) -> RELOAD (按需重启)

. /etc/hppc/hppc.conf
. /usr/share/hppc/lib/utils.sh

# ==========================================
# Category A: 事务工作区与资源常量定义
# ==========================================
TMP_BASE="$DIR_TMP/hp_base.uci"
TMP_NODES="$DIR_TMP/hp_nodes.uci"
TMP_GROUPS="$DIR_TMP/hp_groups.uci"
TMP_RULES="$DIR_TMP/hp_rules.uci"
REQ_LIST="$DIR_TMP/hp_assets.req"
COUNT_FILE="$DIR_TMP/hp_counts"

# 中间态验证文件与生产文件 (通过常量挂载确保安全)
FILE_NEXT_CONF="$DIR_TMP/homeproxy"
SUCCESS_LIST="/tmp/hp_assets.success" 

# ==========================================
# [第一阶段] 战术意图沙盘推演 (Logic Mapping)
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
# [第二阶段] 检阅兵力与战术重塑 (Data Extraction)
# ==========================================
echo -n > "$TMP_NODES"
echo -n > "$TMP_GROUPS"
echo -n > "$TMP_RULES"

log_info "正在检阅各家族兵力 (Counting Nodes)..."
JSON_FILE="$DIR_TMP/hppc_nodes.json"
if [ ! -f "$JSON_FILE" ]; then
    log_err "未发现斥候情报 ($JSON_FILE)，请先执行 '集结' (Fetch)。"
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

log_info "正在重塑战术意图 (Rendering Hp_Base)..."
BASE_TEMPLATE="$DIR_TEMPLATES/hp_base.uci"

if [ ! -f "$BASE_TEMPLATE" ]; then
    log_err "战术蓝图缺失 ($BASE_TEMPLATE)，防线崩塌。"
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
# [第三阶段] 军需调拨与熔断防御 (Asset Requisition)
# ==========================================
log_info "正在扫描战术意图，签发军械申领单..."
grep "list rule_set" "$TMP_BASE" | awk -F"'" '{print $2}' | awk '!x[$0]++' > "$DIR_TMP/hp_assets_id.list"

echo -n > "$REQ_LIST"
while read -r id; do
    [ -n "$id" ] && id_to_filename "$id" >> "$REQ_LIST"
done < "$DIR_TMP/hp_assets_id.list"

if [ -f "$DIR_MODULES/assets.sh" ]; then
    sh "$DIR_MODULES/assets.sh" --fetch-list "$REQ_LIST"
else
    log_err "军需代官 (assets.sh) 擅离职守，防线铸造中止！"
    exit 1
fi

log_info "正在排查军需战损，触发安全熔断 (Circuit Breaker)..."
SUCCESS_IDS=" "
if [ -f "$SUCCESS_LIST" ]; then
    while read -r fname; do
        [ -n "$fname" ] && SUCCESS_IDS="${SUCCESS_IDS}$(filename_to_id "$fname") "
    done < "$SUCCESS_LIST"
fi

mv "$TMP_BASE" "$TMP_BASE.raw2"
echo -n > "$TMP_BASE"
MISSING_COUNT=0

# 熔断剔除 (Pruning failed rulesets)
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

# ==========================================
# [第四阶段] 瓦雷利亚钢动态锻造 (Dynamic Node Casting)
# ==========================================
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

log_info "正在组建固定编制战队 (Routing Groups)..."
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

log_info "正在注入瓦雷利亚兵团 (Injecting Proxy Nodes)..."
echo "$JSON_DATA" | jq -c '.[]' | while read -r row; do
    LABEL=$(echo "$row" | jq -r '.tag')
    ID=$(echo -n "$LABEL" | md5sum | awk '{print $1}')
    TYPE=$(echo "$row" | jq -r '.type')
    SNIP="$DIR_TEMPLATES/${TYPE}.uci"
    
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

# ==========================================
# [第五阶段] 誓言约束与结界替换 (Transaction State Machine)
# ==========================================
log_info "正在将所有部队集结至隔离营地 (Prepare Transaction)..."
if [ -s "$TMP_BASE" ] && [ -s "$TMP_NODES" ]; then
    cat "$TMP_BASE" "$TMP_RULES" "$TMP_GROUPS" "$TMP_NODES" > "$FILE_NEXT_CONF"
else
    log_err "熔炼材料缺失，防线不可摧毁，停止事务！"
    exit 1
fi

log_info "学士正在校验新法阵的符文语法 (UCI Syntax Verification)..."
# 使用 OpenWrt 原生命令校验位于 /tmp 工作区的文件
if ! uci -q -c "$DIR_TMP" show homeproxy >/dev/null 2>&1; then
    log_err "符文语法错误 (UCI Syntax Validation Failed)！放弃部署，旧阵型维持不变。"
    exit 1
fi

log_info "校验通过！正在执行无缝替换 (Atomic Commit)..."
cp "$FILE_CONF_PROD" "${FILE_CONF_PROD}.bak" 2>/dev/null
if mv "$FILE_NEXT_CONF" "$FILE_CONF_PROD"; then
    log_success "配置熔炼与替换完成。"
else
    log_err "城墙土石崩塌 (文件系统异常)，替换失败！正在紧急回滚..."
    mv "${FILE_CONF_PROD}.bak" "$FILE_CONF_PROD" 2>/dev/null
    exit 1
fi

# ==========================================
# [第六阶段] 渡鸦战报与号令流转 (Notification & Reload)
# ==========================================
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
    msg="${msg}%0A%0A⚠️ <b>战损警报:</b> <i>发现 $MISSING_COUNT 个无效军械，已执行战术熔断（剔除），绝境长城基础防御不受影响。</i>"
fi

if [ "$SETTING_AUTO_RELOAD" = "1" ]; then
    log_info "接领主谕旨，正在唤醒结界 (Auto Reloading Service)..."
    if /etc/init.d/homeproxy reload; then
        tg_send "${msg}%0A%0A⚔️ <b>结界状态:</b> <i>自动重启成功，长城已上线新防线。</i>"
    else
        tg_send "${msg}%0A%0A🔥 <b>结界状态:</b> <i>自动重启失败！请领主速速查看。</i>"
    fi
else
    tg_send "${msg}%0A%0A⚔️ <b>指令:</b> <i>系统处于静默待命状态，请择机【手动重启】防线。</i>"
fi

exit 0#!/bin/sh
# --- [ HPPC Core: 炼金术士的熔炉 (Synthesize) v4.0 事务安全版 ] ---
# 职能：解析战术意图 -> 批量申领军械 -> 触发安全熔断 -> 隔离区动态铸造 -> 原子级替换 -> 战报通报
# 架构：PREPARE (生成) -> VERIFY (校验) -> COMMIT (原子替换) -> RELOAD (按需重启)

. /etc/hppc/hppc.conf
. /usr/share/hppc/lib/utils.sh

# ==========================================
# Category A: 事务工作区与资源常量定义
# ==========================================
# 隔离工作区 (Workspace)
TMP_BASE="$DIR_TMP/hp_base.uci"
TMP_NODES="$DIR_TMP/hp_nodes.uci"
TMP_GROUPS="$DIR_TMP/hp_groups.uci"
TMP_RULES="$DIR_TMP/hp_rules.uci"
REQ_LIST="$DIR_TMP/hp_assets.req"
COUNT_FILE="$DIR_TMP/hp_counts"

# 中间态验证文件与生产文件
FILE_NEXT_CONF="$DIR_TMP/homeproxy"
SUCCESS_LIST="/tmp/hp_assets.success" 

# ==========================================
# [第一阶段] 战术意图沙盘推演 (Logic Mapping)
# 警告：此算法涉及核心路由流转，严禁篡改
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
# [第二阶段] 检阅兵力与战术重塑 (Data Extraction)
# ==========================================

echo -n > "$TMP_NODES"
echo -n > "$TMP_GROUPS"
echo -n > "$TMP_RULES"

log_info "正在检阅各家族兵力 (Counting Nodes)..."
JSON_FILE="$DIR_TMP/hppc_nodes.json"
if [ ! -f "$JSON_FILE" ]; then
    log_err "未发现斥候情报 ($JSON_FILE)，请先执行 '集结' (Fetch)。"
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

log_info "正在重塑战术意图 (Rendering Hp_Base)..."
BASE_TEMPLATE="$DIR_TEMPLATES/hp_base.uci"

if [ ! -f "$BASE_TEMPLATE" ]; then
    log_err "战术蓝图缺失 ($BASE_TEMPLATE)，防线崩塌。"
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
# [第三阶段] 军需调拨与熔断防御 (Asset Requisition)
# ==========================================
log_info "正在扫描战术意图，签发军械申领单..."
grep "list rule_set" "$TMP_BASE" | awk -F"'" '{print $2}' | awk '!x[$0]++' > "$DIR_TMP/hp_assets_id.list"

echo -n > "$REQ_LIST"
while read -r id; do
    [ -n "$id" ] && id_to_filename "$id" >> "$REQ_LIST"
done < "$DIR_TMP/hp_assets_id.list"

if [ -f "$DIR_MODULES/assets.sh" ]; then
    sh "$DIR_MODULES/assets.sh" --fetch-list "$REQ_LIST"
else
    log_err "军需代官 (assets.sh) 擅离职守，防线铸造中止！"
    exit 1
fi

log_info "正在排查军需战损，触发安全熔断 (Circuit Breaker)..."
SUCCESS_IDS=" "
if [ -f "$SUCCESS_LIST" ]; then
    while read -r fname; do
        [ -n "$fname" ] && SUCCESS_IDS="${SUCCESS_IDS}$(filename_to_id "$fname") "
    done < "$SUCCESS_LIST"
fi

mv "$TMP_BASE" "$TMP_BASE.raw2"
echo -n > "$TMP_BASE"
MISSING_COUNT=0

# 熔断剔除 (Pruning failed rulesets)
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

# ==========================================
# [第四阶段] 瓦雷利亚钢动态锻造 (Dynamic Node Casting)
# ==========================================
# 铸造规则集
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

log_info "正在组建固定编制战队 (Routing Groups)..."
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

log_info "正在注入瓦雷利亚兵团 (Injecting Proxy Nodes)..."
echo "$JSON_DATA" | jq -c '.[]' | while read -r row; do
    LABEL=$(echo "$row" | jq -r '.tag')
    ID=$(echo -n "$LABEL" | md5sum | awk '{print $1}')
    TYPE=$(echo "$row" | jq -r '.type')
    SNIP="$DIR_TEMPLATES/${TYPE}.uci"
    
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

# ==========================================
# [第五阶段] 誓言约束与结界替换 (Transaction State Machine)
# ==========================================
log_info "正在将所有部队集结至隔离营地 (Prepare Transaction)..."
if [ -s "$TMP_BASE" ] && [ -s "$TMP_NODES" ]; then
    cat "$TMP_BASE" "$TMP_RULES" "$TMP_GROUPS" "$TMP_NODES" > "$FILE_NEXT_CONF"
else
    log_err "熔炼材料缺失，防线不可摧毁，停止事务！"
    exit 1
fi

log_info "学士正在校验新法阵的符文语法 (UCI Syntax Verification)..."
# 使用 OpenWrt 原生命令校验位于 /tmp 工作区的文件
if ! uci -q -c "$DIR_TMP" show homeproxy >/dev/null 2>&1; then
    log_err "符文语法错误 (UCI Syntax Validation Failed)！放弃部署，旧阵型维持不变。"
    exit 1
fi

log_info "校验通过！正在执行无缝替换 (Atomic Commit)..."
cp "$FILE_CONF_PROD" "${FILE_CONF_PROD}.bak" 2>/dev/null
if mv "$FILE_NEXT_CONF" "$FILE_CONF_PROD"; then
    log_success "配置熔炼与替换完成。"
else
    log_err "城墙土石崩塌 (文件系统异常)，替换失败！正在紧急回滚..."
    mv "${FILE_CONF_PROD}.bak" "$FILE_CONF_PROD" 2>/dev/null
    exit 1
fi

# ==========================================
# [第六阶段] 渡鸦战报与号令流转 (Notification & Reload)
# ==========================================
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
    msg="${msg}%0A%0A⚠️ <b>战损警报:</b> <i>发现 $MISSING_COUNT 个无效军械，已执行战术熔断（剔除），绝境长城基础防御不受影响。</i>"
fi

if [ "$SETTING_AUTO_RELOAD" = "1" ]; then
    log_info "接领主谕旨，正在唤醒结界 (Auto Reloading Service)..."
    if /etc/init.d/homeproxy reload; then
        tg_send "${msg}%0A%0A⚔️ <b>结界状态:</b> <i>自动重启成功，长城已上线新防线。</i>"
    else
        tg_send "${msg}%0A%0A🔥 <b>结界状态:</b> <i>自动重启失败！请领主速速查看。</i>"
    fi
else
    tg_send "${msg}%0A%0A⚔️ <b>指令:</b> <i>系统处于静默待命状态，请择机【手动重启】防线。</i>"
fi

exit 0
