#!/bin/sh
# --- [ HPPC Module: 物资代官 (Assets) v3.1 ] ---
# 职责：规则集下载、MD5 增量更新、备份回滚、自动重启(Auto模式)
# 修复：补全回滚函数、修正 TG 换行格式

source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

# 路径定义
RULE_DIR="/etc/homeproxy/ruleset"
TEMP_DIR="/tmp/hppc_assets_temp"
BACKUP_DIR="/etc/homeproxy/ruleset_backup"

mkdir -p "$RULE_DIR"

# 源定义
SRC_PRIVATE="$ASSETS_PRIVATE_REPO"
BASE_URL="https://github.com/MetaCubeX/meta-rules-dat/raw/sing"

# ----------------------------------------------------------
# 1. 基础工具 (Tools)
# ----------------------------------------------------------
download_file() {
    local url="$1"
    local dest="$2"
    # -k: 忽略SSL, -L: 跟随重定向, -f: 404不写入
    if curl -k -sL --connect-timeout 15 --retry 2 -f "$url" -o "$dest"; then
        # 校验文件有效性 (非空且非HTML错误页)
        if [ -s "$dest" ] && ! head -n 1 "$dest" | grep -q "<!DOCTYPE"; then
            return 0
        fi
    fi
    rm -f "$dest"
    return 1
}

# [新增] 备份功能
backup_rules() {
    # log_info "正在创建规则集快照..."
    rm -rf "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    cp -a "$RULE_DIR"/* "$BACKUP_DIR"/ 2>/dev/null
}

# [新增] 回滚功能 (供 CLI 和 Auto 模式调用)
restore_rules() {
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A $BACKUP_DIR)" ]; then
        log_warn "正在执行时光倒流 (Restoring Rules)..."
        rm -rf "$RULE_DIR"/*
        cp -a "$BACKUP_DIR"/* "$RULE_DIR"/
        log_success "✅ 规则集已恢复至备份状态。"
        return 0
    else
        log_err "无可用备份 (Backup Not Found)。"
        return 1
    fi
}

fetch_to_temp() {
    local name="$1"
    local temp_path="$2"
    
    # [策略 A] 私有库优先
    if [ -n "$SRC_PRIVATE" ]; then
        if download_file "$SRC_PRIVATE/$name.srs" "$temp_path"; then
            return 0
        fi
    fi

    # [策略 B] MetaCubeX (Standard + Lite)
    local type="${name%%-*}"
    local core_name="${name#*-}"
    
    # 尝试 Standard
    if download_file "$BASE_URL/geo/$type/$core_name.srs" "$temp_path"; then
        return 0
    fi
    
    # 尝试 Lite
    if download_file "$BASE_URL/geo-lite/$type/$core_name.srs" "$temp_path"; then
        return 0
    fi

    return 1
}

# ----------------------------------------------------------
# 2. 核心功能 (Core Functions)
# ----------------------------------------------------------

# [手动下载]
download_manual() {
    local name="$1"
    local final_path="$RULE_DIR/$name.srs"
    local temp_path="/tmp/$name.srs.tmp"

    if [[ "$name" != geosite-* ]] && [[ "$name" != geoip-* ]]; then
        log_err "格式错误！名称必须以 'geosite-' 或 'geoip-' 开头。"
        return 1
    fi
    
    log_info "正在手动征收: $name ..."
    if fetch_to_temp "$name" "$temp_path" >/dev/null; then
        mv "$temp_path" "$final_path"
        echo ""
        log_success "✅ 规则集已入库: $final_path"
        echo -e "${C_INFO}提示:${C_RESET} 请记得在 hp_base.uci 中添加配置引用它。"
    else
        echo ""
        log_err "❌ 下载失败，请检查名称是否正确。"
    fi
}

# [依赖补全]
resolve_deps() {
    local config_file="$1"
    log_info "代官正在核对物资清单..."
    grep "option path" "$config_file" | awk -F"'" '{print $2}' | sort | uniq | while read -r file_path; do
        if [ ! -s "$file_path" ]; then
            filename=$(basename "$file_path")
            name=$(echo "$filename" | sed 's/\.srs$//; s/\.json$//')
            log_warn "发现短缺: $name，启动紧急采购..."
            
            temp_file="/tmp/${name}_resolve.tmp"
            if fetch_to_temp "$name" "$temp_file" >/dev/null; then
                mv "$temp_file" "$file_path"
                log_success "补给送达: $name"
            else
                log_err "无法获取: $name"
            fi
        fi
    done
}

# [全量更新] 智能增量更新 + 备份回滚
update_all() {
    local mode="$1" # auto / manual
    log_info "开始每日物资修缮 (模式: $mode)..."
    
    CURRENT_CONF="/etc/config/homeproxy"
    [ ! -f "$CURRENT_CONF" ] && return

    # 1. 准备工作
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    
    local total=0
    local update_count=0
    local fail_count=0
    local change_log=""
    
    # 提取所有规则路径
    grep "option path" "$CURRENT_CONF" | awk -F"'" '{print $2}' | sort | uniq > "$TEMP_DIR/list.txt"
    
    # 2. 循环检测
    while read -r live_path; do
        filename=$(basename "$live_path")
        name=$(echo "$filename" | sed 's/\.srs$//; s/\.json$//')
        temp_file="$TEMP_DIR/$filename"
        
        total=$((total + 1))
        
        # 下载到临时目录
        if fetch_to_temp "$name" "$temp_file" >/dev/null; then
            # 计算 MD5
            new_md5=$(md5sum "$temp_file" | awk '{print $1}')
            
            if [ -f "$live_path" ]; then
                old_md5=$(md5sum "$live_path" | awk '{print $1}')
                
                if [ "$new_md5" != "$old_md5" ]; then
                    # MD5 不同 -> 需要更新
                    update_count=$((update_count + 1))
                    # [修复] 使用 %0A 换行
                    change_log="${change_log}%0A🔹 <b>$name</b> (更新)"
                    log_info "检测到更新: $name"
                else
                    # MD5 相同 -> 删除临时文件
                    rm -f "$temp_file"
                fi
            else
                # 本地不存在 -> 新增
                update_count=$((update_count + 1))
                # [修复] 使用 %0A 换行
                change_log="${change_log}%0A✨ <b>$name</b> (新增)"
                log_info "检测到新增: $name"
            fi
        else
            fail_count=$((fail_count + 1))
            # [修复] 使用 %0A 换行
            change_log="${change_log}%0A❌ <b>$name</b> (下载失败)"
            log_err "下载失败: $name"
        fi
    done < "$TEMP_DIR/list.txt"

    # 3. 决策执行
    local status_msg=""
    
    if [ "$update_count" -eq 0 ]; then
        log_success "所有规则集均是最新的。"
        status_msg="%0A💤 规则集已是最新，无需变更。"
        rm -rf "$TEMP_DIR"
    else
        log_info "准备应用 $update_count 个更新..."
        
        # [步骤 A] 备份旧规则 (调用函数)
        backup_rules
        
        # [步骤 B] 覆盖新规则
        # 将 TEMP_DIR 里剩余的文件移动过去
        cp -f "$TEMP_DIR"/*.srs "$RULE_DIR"/ 2>/dev/null
        rm -rf "$TEMP_DIR"
        
        # [步骤 C] 重启服务 (仅 Auto 模式)
        if [ "$mode" == "auto" ]; then
            log_info "触发自动重启 HomeProxy..."
            if /etc/init.d/homeproxy restart; then
                status_msg="%0A♻️ 服务自动重启: <b>成功</b>"
                log_success "服务重启成功。"
            else
                log_err "服务启动失败！正在执行自动回滚..."
                
                # [步骤 D] 紧急回滚
                restore_rules
                
                # 回滚后再次重启
                if /etc/init.d/homeproxy restart; then
                    status_msg="%0A🛡️ 重启失败，已<b>回滚</b>并恢复服务。"
                else
                    status_msg="%0A💀 严重: 回滚后重启仍失败！"
                fi
            fi
        else
            # 手动模式，不重启，由 CLI 处理
            status_msg="%0A⚠️ 已更新文件，请择机重启。"
        fi
    fi

    # 4. 发送战报
    if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
        local msg="🏰 <b>[${LOCATION}] 典籍修缮报告</b>%0A"
        msg="${msg}--------------------------------%0A"
        
        if [ "$update_count" -gt 0 ]; then
            msg="${msg}📦 变更数量: <b>$update_count</b>%0A"
            msg="${msg}📝 变更清单: ${change_log}%0A"
        else
            msg="${msg}✅ 所有规则集均为最新版本。%0A"
        fi
        
        if [ "$fail_count" -gt 0 ]; then
            msg="${msg}🚫 失败数量: <b>$fail_count</b>%0A"
        fi
        
        msg="${msg}${status_msg}"
        
        curl -sk -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
            -d "chat_id=$TG_CHAT_ID" -d "parse_mode=HTML" -d "text=$msg" > /dev/null 2>&1
    fi
}

# 入口
case "$1" in
    --resolve) resolve_deps "$2" ;;
    --update)  update_all "$2" ;;
    --download) download_manual "$2" ;;
    --restore) restore_rules ;;
    *) echo "Usage: $0 {--resolve | --update [auto] | --download | --restore}" ;;
esac
