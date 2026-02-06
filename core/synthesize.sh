#!/bin/sh
# --- [ HPPC Core: 炼金术士 (Synthesize) v3.1 ] ---
# 职责：解析节点 -> 意图平移 -> 供应链核查 (Assets) -> 铸造防线 -> 战报(仅通知)

source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

# 资源路径
TMP_BASE="/tmp/hp_base.uci"
TMP_NODES="/tmp/hp_nodes.uci"
TMP_GROUPS="/tmp/hp_groups.uci"
FINAL_CONF="/etc/config/homeproxy"
TEMPLATE_DIR="/usr/share/hppc/templates/models"
COUNT_FILE="/tmp/hp_counts"
MODULE_ASSETS="/usr/share/hppc/modules/assets.sh"

# ==========================================
# 1. 核心算法：意图平移 (The Strategy Shift)
# ==========================================
map_logic() {
    local val=$(echo "$1" | tr -d "' \t\r\n")
    # 跳过特殊值
    [ "$val" = "direct-out" ] || [ "$val" = "blackhole-out" ] || [ "$val" = "default-out" ] && echo "$val" && return
    
    # 提取地区 (hk, tw, sg, jp, us)
    local reg=$(echo "$val" | grep -oE "hk|tw|sg|jp|us" | head -1)
    [ -z "$reg" ] && echo "$val" && return
    
    # 提取编号 (默认 1)
    local num_str=$(echo "$val" | grep -oE "[0-9]+" | sed 's/^0//')
    [ -z "$num_str" ] && local num=1 || local num=$num_str
    
    # 获取该地区总节点数
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
# 主流程 (The Grand Process)
# ==========================================

# 1. 准备熔炉 (清理旧残渣)
echo -n > "$TMP_NODES"
echo -n > "$TMP_GROUPS"

# 2. 检阅兵力 (Counting)
log_info "正在检阅各家族兵力..."
# 确保 jq 存在
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
# 提取机场前缀 (例如 luckin, Totoro)
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

# 3. 重塑战术意图 (Mapping) - 处理 hp_base.uci
log_info "正在重塑战术意图 (Hp_Base)..."
BASE_TEMPLATE="/usr/share/hppc/templates/hp_base.uci"

if [ ! -f "$BASE_TEMPLATE" ]; then
    log_err "战术蓝图缺失 ($BASE_TEMPLATE)，请升级脚本。"
    exit 1
fi

cp "$BASE_TEMPLATE" "$TMP_BASE.raw"
echo -n > "$TMP_BASE"

# 逐行读取并应用映射算法
while IFS= read -r line; do
    if echo "$line" | grep -q "option outbound"; then
        val=$(echo "$line" | awk -F"'" '{print $2}')
        new_val=$(map_logic "$val")
        # 只替换确实改变了的值
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

# 供应链核查 (Supply Chain Check) 
if [ -f "$MODULE_ASSETS" ]; then
    # 呼叫物资代官，检查 TMP_BASE 中引用的规则文件是否存在
    # 如果不存在，代官会自动下载 (优先私有源)
    sh "$MODULE_ASSETS" --resolve "$TMP_BASE"
else
    log_warn "物资代官 (Assets) 未就位，跳过规则集检查。"
fi

# 4. 组建固定编制 (Groups)
log_info "正在组建固定编制战队..."
for reg in $REGIONS; do
    idx=1
    lower_reg=$(echo "$reg" | tr 'A-Z' 'a-z')
    # 设置国旗
    case "$reg" in "HK") flag="🇭🇰" ;; "SG") flag="🇸🇬" ;; "TW") flag="🇹🇼" ;; "JP") flag="🇯🇵" ;; "US") flag="🇺🇸" ;; esac
    
    for ap in $AIRPORTS; do
        # 获取该机场该地区的所有节点 Tag
        node_tags=$(echo "$JSON_DATA" | jq -r ".[] | select(.tag | contains(\"$ap\")) | select(.tag | contains(\"$reg\")) | .tag")
        
        if [ -n "$node_tags" ]; then
            group_id="${lower_reg}$(printf "%02d" $idx)"
            
            # 使用纯 echo 写入，避免 echo -e 的兼容性问题
            {
                echo "config routing_node '$group_id'"
                echo "    option label '$flag $reg-$ap'"
                echo "    option node 'urltest'"
                echo "    option enabled '1'"
                echo "    option urltest_tolerance '150'"
                echo "    option urltest_interrupt_exist_connections '1'"
                
                # 循环写入节点列表，使用 IFS= read -r 确保空格和特殊字符安全
                echo "$node_tags" | while IFS= read -r tag; do
                    # 使用 md5sum 生成唯一 ID
                    nid=$(echo -n "$tag" | md5sum | awk '{print $1}')
                    echo "    list urltest_nodes '$nid'"
                done
                echo "" 
            } >> "$TMP_GROUPS"
            
            idx=$((idx + 1))
        fi
    done
done

# ==========================================
# 5. 注入瓦雷利亚节点 (The Universal Injector)
# ==========================================
log_info "正在注入瓦雷利亚节点 (智能映射模式)..."

echo "$JSON_DATA" | jq -c '.[]' | while read -r row; do
    # 1. 基础身份识别
    LABEL=$(echo "$row" | jq -r '.tag')
    ID=$(echo -n "$LABEL" | md5sum | awk '{print $1}')
    TYPE=$(echo "$row" | jq -r '.type')
    
    # 智能寻找模具：只要 templates 目录里有这个 type.uci，就自动加载
    SNIP="$TEMPLATE_DIR/${TYPE}.uci"
    
    if [ -f "$SNIP" ]; then
        # --- [超级提取器] 一次性提取所有可能的战术参数 ---
        
        # A. 基础五维数据
        SERVER=$(echo "$row" | jq -r '.server')
        PORT=$(echo "$row" | jq -r '.server_port')
        PASSWORD=$(echo "$row" | jq -r '.password // empty')
        UUID=$(echo "$row" | jq -r '.uuid // empty')
        METHOD=$(echo "$row" | jq -r '.method // empty')
        
        # B. TLS 安全组件
        # 自动判定 TLS 开关 (Sing-box JSON 只有 tls.enabled=true 时才开启)
        [ "$(echo "$row" | jq -r '.tls.enabled // false')" = "true" ] && TLS="1" || TLS="0"
        # 自动判定跳过验证
        [ "$(echo "$row" | jq -r '.tls.insecure // false')" = "true" ] && INSECURE="1" || INSECURE="0"
        # SNI 优先取 tls.server_name，没有则取 host，再没有则取 server 地址
        SNI=$(echo "$row" | jq -r '.tls.server_name // .host // .server')
        # ALPN (取数组第一个，默认为 h3，部分协议可能需要空)
        ALPN=$(echo "$row" | jq -r '.tls.alpn[0] // "h3"')
        # Fingerprint (uTLS)
        RAW_UTLS=$(echo "$row" | jq -r '.tls.utls // empty')
        [ "$RAW_UTLS" = "null" ] && UTLS_VAL="chrome" || UTLS_VAL=$(echo "$RAW_UTLS" | jq -r '.fingerprint // "chrome"')

        # C. 协议特有组件 (VLESS/TUIC/Hysteria)
        FLOW=$(echo "$row" | jq -r '.flow // empty')
        CONGESTION=$(echo "$row" | jq -r '.congestion_control // "bbr"')
        OBFS_PASS=$(echo "$row" | jq -r '.plugin_opts.password // empty') # ShadowTLS 等插件密码
        
        # D. Reality 组件 (存在即启用)
        PK=$(echo "$row" | jq -r '.tls.reality.public_key // empty')
        SID=$(echo "$row" | jq -r '.tls.reality.short_id // empty')
        if [ -n "$PK" ] && [ "$PK" != "null" ]; then
             REALITY_ENABLE="1"
        else
             REALITY_ENABLE="0"
             PK=""; SID=""
        fi

        # --- [全量熔炼] 执行统一替换 ---
        # 无论模板里有没有 {{CONGESTION}}，都尝试替换。没有的变量会被 sed 忽略，不会报错。
        
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
    # else
        # log_debug "未找到协议模板: $TYPE (跳过)"
    fi
done

# 6. 最终合并 (The Merger)
if [ -s "$TMP_BASE" ] && [ -s "$TMP_NODES" ]; then
    cat "$TMP_BASE" "$TMP_NODES" "$TMP_GROUPS" > "$FINAL_CONF"
else
    log_err "熔炼材料缺失，中止合并！"
    exit 1
fi

# 7. 战报通报 (The Raven's Scroll)
if [ -s "$FINAL_CONF" ]; then
    cp "$FINAL_CONF" "/etc/config/homeproxy.bak"
    log_success "配置熔炼完成 (新配置已就绪)。"
    
    # --- 权游风随机文案 ---
    stats=$(cat $COUNT_FILE | tr '\n' ' ' | sed 's/=$//')
    rand=$(hexdump -n 1 -e '/1 "%u"' /dev/urandom)
    case $((rand % 5)) in
        0) msg="🕯️ 报告领主，【$LOCATION】城墙蓝图已重绘。瓦雷利亚钢已熔炼完毕。" ;;
        1) msg="🦅 渡鸦传信：【$LOCATION】新阵型演练完成。预备守军分布：$stats" ;;
        2) msg="🍷 领主大人，【$LOCATION】的新装备已入库，随时可以换装！" ;;
        3) msg="❄️ 凛冬将至，但【$LOCATION】的炉火正旺。新配置已生成，静候指令。" ;;
        4) msg="🐉 龙焰重铸！【$LOCATION】积木已归位，只待您一声令下！" ;;
    esac
    
    # 发送 TG (仅通知，不重启)
    tg_send "${msg}%0A%0A⚠️ <b>指令:</b> <i>节点配置已变更，请择机手动重启。</i>"
else
    log_err "熔炼失败 (生成结果为空)！"
    exit 1
fi
