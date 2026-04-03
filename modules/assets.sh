#!/bin/sh
# --- [ HPPC Module: 物资代官 (Assets) v3.6 镜像加速版 ] ---
# 职责：规则集下载、MD5增量更新、断网自愈、jsDelivr 镜像补给
# 准则：DRY 原则，严禁重复下载；内存操作，保护闪存；失败回滚，确保可用。

source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

# 路径定义 (遵循 Linux 标准目录结构)
RULE_DIR="/etc/homeproxy/ruleset"
TEMP_DIR="/tmp/hppc_assets_temp"
BACKUP_DIR="/etc/homeproxy/ruleset_backup"

mkdir -p "$RULE_DIR"

# [核心优化] 补给源定义：优先使用 jsDelivr 镜像，确保无代理环境下的冷启动成功率
SRC_PRIVATE="$ASSETS_PRIVATE_REPO"
# 公有库镜像 (指向 MetaCubeX 官方规则集的 sing 分支)
BASE_URL="https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing"

# ----------------------------------------------------------
# 1. 基础工具函数 (Infrastructure)
# ----------------------------------------------------------

# 带有安全校验的下载器
download_file() {
    local url="$1"
    local dest="$2"
    # -k: 忽略证书报错 (冷启动必备)
    # -sL: 静默并跟随重定向
    # -f: HTTP 错误时返回非零状态码
    if curl -k -sL --connect-timeout 15 --retry 2 -f "$url" -o "$dest"; then
        # 验证文件是否为空，且过滤掉 GitHub 的 HTML 错误页面
        if [ -s "$dest" ] && ! head -n 1 "$dest" | grep -q "<!DOCTYPE"; then
            return 0
        fi
    fi
    rm -f "$dest"
    return 1
}

# 战备备份
backup_rules() {
    rm -rf "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    cp -a "$RULE_DIR"/* "$BACKUP_DIR"/ 2>/dev/null
}

# 时光倒流 (回滚逻辑)
restore_rules() {
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A $BACKUP_DIR)" ]; then
        log_warn "正在执行自动回滚 (Restoring Rules)..."
        rm -rf "$RULE_DIR"/*
        cp -a "$BACKUP_DIR"/* "$RULE_DIR"/
        log_success "✅ 规则集已恢复至备份状态。"
        return 0
    fi
    log_err "无可用备份 (No Backup Found)。"
    return 1
}

# 多级物资探测逻辑
fetch_to_temp() {
    local name="$1"
    local temp_path="$2"
    
    # 路径 1: 尝试私有库 (用户自定义的 jsDelivr 目录)
    if [ -n "$SRC_PRIVATE" ]; then
        if download_file "$SRC_PRIVATE/$name.srs" "$temp_path"; then return 0; fi
    fi

    # 路径 2: 尝试公有库 (根据前缀自动分流 geo/geo-lite)
    local type="${name%%-*}"      # 提取 geosite/geoip
    local core_name="${name#*-}"  # 提取具体名称 (如 openai/netflix)
    
    # 尝试标准库路径
    if download_file "$BASE_URL/geo/$type/$core_name.srs" "$temp_path"; then return 0; fi
    # 尝试精简库路径
    if download_file "$BASE_URL/geo-lite/$type/$core_name.srs" "$temp_path"; then return 0; fi

    return 1
}

# ----------------------------------------------------------
# 2. 核心业务逻辑
# ----------------------------------------------------------

# 批量申领 (供模块间调用)
fetch_list() {
    local req_file="$1"
    local success_file="/tmp/hp_assets.success"
    echo -n > "$success_file"

    log_info "代官收到申领单，开始核对物资..."
    
    while read -r name; do
        [ -z "$name" ] && continue
        local final_path="$RULE_DIR/$name.srs"
        local temp_path="/tmp/${name}.srs.tmp" # RAM 操作
        
        if fetch_to_temp "$name" "$temp_path" >/dev/null; then
            if [ -f "$final_path" ]; then
                local old_md5=$(md5sum "$final_path" | awk '{print $1}')
                local new_md5=$(md5sum "$temp_path" | awk '{print $1}')
                if [ "$old_md5" != "$new_md5" ]; then
                    mv "$temp_path" "$final_path"
                    log_info "📦 物资翻新: $name"
                else
                    rm -f "$temp_path" # 无变化则释放内存
                fi
            else
                mv "$temp_path" "$final_path"
                log_success "📦 物资入库: $name"
            fi
            echo "$name" >> "$success_file"
        else
            # 降级处理：若下载失败但本地有存货，则继续使用旧版
            if [ -f "$final_path" ]; then
                log_warn "⚠️ [$name] 获取失败，启用陈旧库存维持防线。"
                echo "$name" >> "$success_file"
            else
                log_err "❌ 致命断供: [$name] 彻底获取失败！"
            fi
        fi
    done < "$req_file"
}

# 手动征收
download_manual() {
    local name="$1"
    local final_path="$RULE_DIR/$name.srs"
    local temp_path="/tmp/$name.srs.tmp"

    if [[ "$name" != geosite-* ]] && [[ "$name" != geoip-* ]]; then
        log_err "格式错误！必须以 'geosite-' 或 'geoip-' 开头。"
        return 1
    fi
    
    log_info "正在手动征收: $name ..."
    if fetch_to_temp "$name" "$temp_path" >/dev/null; then
        mv "$temp_path" "$final_path"
        echo ""
        log_success "✅ 物资入库: $final_path"
    else
        echo ""
        log_err "❌ 下载失败。请检查名称或私有源地址是否正确。"
    fi
}

# 每日全量巡检
update_all() {
    local mode="$1" # auto / manual
    log_info "开始物资巡检 (模式: $mode)..."
    
    CURRENT_CONF="/etc/config/homeproxy"
    [ ! -f "$CURRENT_CONF" ] && return

    rm -rf "$TEMP_DIR" && mkdir -p "$TEMP_DIR"
    
    local update_count=0
    local fail_count=0
    local change_log=""
    
    # 扫描当前配置中引用的所有规则集
    grep "option path" "$CURRENT_CONF" | awk -F"'" '{print $2}' | sort | uniq > "$TEMP_DIR/list.txt"
    
    while read -r live_path; do
        local filename=$(basename "$live_path")
        local name=$(echo "$filename" | sed 's/\.srs$//; s/\.json$//')
        local temp_file="$TEMP_DIR/$filename"
        
        if fetch_to_temp "$name" "$temp_file" >/dev/null; then
            local new_md5=$(md5sum "$temp_file" | awk '{print $1}')
            if [ -f "$live_path" ]; then
                local old_md5=$(md5sum "$live_path" | awk '{print $1}')
                if [ "$new_md5" != "$old_md5" ]; then
                    update_count=$((update_count + 1))
                    change_log="${change_log}%0A🔹 <b>$name</b> (更新)"
                    mv "$temp_file" "$live_path"
                else
                    rm -f "$temp_file"
                fi
            else
                update_count=$((update_count + 1))
                change_log="${change_log}%0A✨ <b>$name</b> (新增)"
                mv "$temp_file" "$live_path"
            fi
        else
            fail_count=$((fail_count + 1))
            change_log="${change_log}%0A❌ <b>$name</b> (下载失败)"
        fi
    done < "$TEMP_DIR/list.txt"

    # 处理重启与通知
    local status_msg=""
    if [ "$update_count" -gt 0 ]; then
        if [ "$mode" == "auto" ]; then
            backup_rules # 更新前先备份
            log_info "触发自动重启以应用变更..."
            if /etc/init.d/homeproxy restart; then
                status_msg="%0A♻️ 服务自动重启: <b>成功</b>"
                # [核心修正] 等待网络稳固后再发 TG，防止通知丢失
                sleep 20 
            else
                log_err "启动失败！回滚中..."
                restore_rules
                /etc/init.d/homeproxy restart
                status_msg="%0A🛡️ 重启失败，已自动执行<b>安全回滚</b>。"
            fi
        else
            status_msg="%0A⚠️ 已更新文件，请择机重启。"
        fi
    else
        status_msg="%0A💤 物资均在有效期内，无需更新。"
    fi

    # 发送 Telegram 战报
    if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
        local msg="🏰 <b>[${LOCATION}] 物资巡检报告</b>%0A"
        msg="${msg}--------------------------------%0A"
        msg="${msg}📦 更新数量: <b>$update_count</b>%0A"
        [ -n "$change_log" ] && msg="${msg}📝 详细清单: ${change_log}%0A"
        msg="${msg}${status_msg}"
        
        curl -sk -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
            -d "chat_id=$TG_CHAT_ID" -d "parse_mode=HTML" -d "text=$msg" > /dev/null 2>&1
    fi
}

# ----------------------------------------------------------
# 3. 入口控制 (Interface)
# ----------------------------------------------------------
case "$1" in
    --fetch-list) fetch_list "$2" ;;
    --update)    update_all "$2" ;;
    --download)  download_manual "$2" ;;
    --restore)   restore_rules ;;
    *) echo "Usage: $0 {--fetch-list <file> | --update [auto] | --download <name> | --restore}" ;;
esac
