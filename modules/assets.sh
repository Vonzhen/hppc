#!/bin/sh
# --- [ HPPC Module: 物资代官 (Assets) v3.1 ] ---
# 职责：规则集 (RuleSet) 的订阅、下载、单点获取与通知

source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

RULE_DIR="/etc/homeproxy/ruleset"
mkdir -p "$RULE_DIR"

# 1. 定义源 (Sources)
SRC_PRIVATE="$ASSETS_PRIVATE_REPO"
# MetaCubeX 仓库基地址 (sing 分支)
BASE_URL="https://github.com/MetaCubeX/meta-rules-dat/raw/sing"

# 通用下载函数
download_file() {
    local url="$1"
    local dest="$2"
    # -k: 允许不安全SSL, -L: 跟随重定向, -z: 只有文件更新了才下载 (基于时间戳)
    # 注意：GitHub Raw 对 -z 支持不一定完美，主要靠 hash 校验或强制覆盖
    if curl -k -sL --connect-timeout 15 --retry 2 -f "$url" -o "$dest.tmp"; then
        if [ -s "$dest.tmp" ] && ! head -n 1 "$dest.tmp" | grep -q "<!DOCTYPE"; then
            mv "$dest.tmp" "$dest"
            return 0
        fi
    fi
    rm -f "$dest.tmp"
    return 1
}

# 核心下载逻辑
download_rule() {
    local target_filename="$1"
    local target_path="$2"
    local source_tag="" # 记录来源用于日志

    # [策略 A] 私有库优先
    if [ -n "$SRC_PRIVATE" ]; then
        if download_file "$SRC_PRIVATE/$target_filename.srs" "$target_path"; then
            log_success "⚔️ [私有] 获取成功: $target_filename"
            return 0
        fi
    fi

    # [策略 B] MetaCubeX 级联搜寻
    local type="${target_filename%%-*}"
    local name="${target_filename#*-}"
    local urls_to_try="$BASE_URL/geo/$type/$name.srs $BASE_URL/geo-lite/$type/$name.srs"

    for url in $urls_to_try; do
        if download_file "$url" "$target_path"; then
            log_success "📚 [公共] 获取成功: $target_filename"
            return 0
        fi
    done

    log_err "物资缺失: $target_filename"
    return 1
}

# [模式 1] 依赖补全 (静默模式，只补缺)
resolve_deps() {
    local config_file="$1"
    log_info "代官正在核对物资清单..."
    grep "option path" "$config_file" | awk -F"'" '{print $2}' | sort | uniq | while read -r file_path; do
        if [ ! -s "$file_path" ]; then
            name=$(basename "$file_path" | sed 's/\.srs$//; s/\.json$//')
            log_warn "发现短缺: $name，启动紧急采购..."
            download_rule "$name" "$file_path"
        fi
    done
}

# [模式 2] 全量更新 (带战报)
update_all() {
    log_info "开始每日物资修缮..."
    CURRENT_CONF="/etc/config/homeproxy"
    [ ! -f "$CURRENT_CONF" ] && return

    local updated_count=0
    local updated_list=""

    # 创建临时文件列表
    tmp_list=$(mktemp)
    grep "option path" "$CURRENT_CONF" | awk -F"'" '{print $2}' | sort | uniq > "$tmp_list"

    while read -r file_path; do
        name=$(basename "$file_path" | sed 's/\.srs$//; s/\.json$//')
        
        # 计算旧文件的 Hash
        old_hash="none"
        [ -f "$file_path" ] && old_hash=$(md5sum "$file_path" | awk '{print $1}')

        # 尝试下载
        download_rule "$name" "$file_path"
        
        # 计算新文件的 Hash
        new_hash=$(md5sum "$file_path" | awk '{print $1}')

        # 如果 Hash 变了，说明有实质性更新
        if [ "$old_hash" != "$new_hash" ]; then
            updated_count=$((updated_count + 1))
            updated_list="$updated_list $name"
        fi
    done < "$tmp_list"
    rm "$tmp_list"

    # 发送战报
    if [ "$updated_count" -gt 0 ]; then
        log_success "修缮完成，共更新 $updated_count 卷。"
        # 重载服务以应用新规则 (重要优化)
        /etc/init.d/homeproxy reload 2>/dev/null
        
        # 发送 TG 通知
        MSG="📚 <b>[HPPC] 藏书阁修缮报告</b>%0A--------------------------------%0A已更新规则: <b>$updated_count</b> 个%0A清单: $updated_list%0A--------------------------------%0A🔄 服务已重载"
        tg_send "$MSG"
    else
        log_info "所有典籍完好，无需更新。"
    fi
}

# [模式 3] 单点获取 (手动模式)
get_single() {
    local name="$1"
    # 自动补全路径
    local path="$RULE_DIR/$name.srs"
    log_info "领主指定获取: $name ..."
    if download_rule "$name" "$path"; then
        echo ""
        log_success "✅ 下载完成！路径: $path"
        log_info "提示: 请确保您的 hp_base.uci 或配置中引用了此文件。"
    else
        echo ""
        log_err "❌ 下载失败，请检查名称是否正确 (例如: geosite-google)。"
    fi
}

# 入口判断
case "$1" in
    --resolve) resolve_deps "$2" ;;
    --update)  update_all ;;
    --get)     get_single "$2" ;;
    *) echo "Usage: $0 {--resolve <file> | --update | --get <name>}" ;;
esac
