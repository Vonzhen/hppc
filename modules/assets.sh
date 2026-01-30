#!/bin/sh
# --- [ HPPC Module: 物资代官 (Assets) v2.3 ] ---
# 职责：规则集 (RuleSet) 的订阅、下载、战报汇报与手动采购
# 适配源：MetaCubeX (sing branch) & 私有仓库

source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

RULE_DIR="/etc/homeproxy/ruleset"
mkdir -p "$RULE_DIR"

# 1. 定义源 (Sources)
SRC_PRIVATE="$ASSETS_PRIVATE_REPO"
# MetaCubeX 仓库基地址 (sing 分支)
BASE_URL="https://github.com/MetaCubeX/meta-rules-dat/raw/sing"

# 通用下载器
download_file() {
    local url="$1"
    local dest="$2"
    
    # -k: 允许不安全SSL, -L: 跟随重定向, -f: 失败不输出
    if curl -k -sL --connect-timeout 15 --retry 2 -f "$url" -o "$dest.tmp"; then
        # 双重校验：确保文件不为空且不是 HTML 报错页
        if [ -s "$dest.tmp" ] && ! head -n 1 "$dest.tmp" | grep -q "<!DOCTYPE"; then
            mv "$dest.tmp" "$dest"
            return 0
        fi
    fi
    rm -f "$dest.tmp"
    return 1
}

# 核心逻辑：下载单个规则
download_rule() {
    local target_filename="$1"  # 例如: geosite-apple
    local target_path="$2"      # 例如: /etc/homeproxy/ruleset/geosite-apple.srs
    
    log_info "正在寻访典籍: $target_filename ..."

    # [策略 A] 私有库优先 (Private First)
    if [ -n "$SRC_PRIVATE" ]; then
        # 拼接逻辑: 私有源基地址 + / + 文件名.srs
        if download_file "$SRC_PRIVATE/$target_filename.srs" "$target_path"; then
            log_success "⚔️ [私有] 已获取: $target_filename"
            return 0
        fi
    fi

    # [策略 B] 智能解析 MetaCubeX 仓库结构
    # 拆解前缀: geosite-apple -> type="geosite", name="apple"
    local type="${target_filename%%-*}"
    local name="${target_filename#*-}"

    local urls_to_try=""
    # 尝试顺序 1: Standard 目录
    urls_to_try="$urls_to_try $BASE_URL/geo/$type/$name.srs"
    # 尝试顺序 2: Lite 目录 (解决 geoip-apple 等缺失问题)
    urls_to_try="$urls_to_try $BASE_URL/geo-lite/$type/$name.srs"

    for url in $urls_to_try; do
        if download_file "$url" "$target_path"; then
            log_success "📚 [公共] 已获取: $target_filename"
            return 0
        fi
    done

    log_err "物资缺失: $target_filename (所有源均未找到)"
    return 1
}

# 模式 1: 依赖补全 (HPPC 调用)
resolve_deps() {
    local config_file="$1"
    log_info "代官正在核对物资清单..."
    grep "option path" "$config_file" | awk -F"'" '{print $2}' | sort | uniq | while read -r file_path; do
        if [ ! -s "$file_path" ]; then
            filename=$(basename "$file_path")
            name=$(echo "$filename" | sed 's/\.srs$//; s/\.json$//')
            log_warn "发现短缺: $name，启动紧急采购..."
            download_rule "$name" "$file_path"
        fi
    done
}

# 模式 2: 手动采购 (CLI 调用)
download_manual() {
    local name="$1"
    local path="$RULE_DIR/$name.srs"
    
    if [[ "$name" != geosite-* ]] && [[ "$name" != geoip-* ]]; then
        log_err "格式错误！名称必须以 'geosite-' 或 'geoip-' 开头。"
        return 1
    fi

    if download_rule "$name" "$path"; then
        echo ""
        log_success "✅ 规则集已入库: $path"
        echo -e "${C_INFO}提示:${C_RESET} 请记得在 hp_base.uci 中添加配置引用它。"
    else
        echo ""
        log_err "❌ 下载失败，请检查名称是否正确。"
    fi
}

# 模式 3: 全量更新 & 战报 (Cron 调用)
update_all() {
    log_info "开始每日物资修缮..."
    CURRENT_CONF="/etc/config/homeproxy"
    [ ! -f "$CURRENT_CONF" ] && return
    
    local total=0; local success=0; local fail=0; local failed_list=""

    # 使用临时文件防止管道子 Shell 变量丢失
    grep "option path" "$CURRENT_CONF" | awk -F"'" '{print $2}' | sort | uniq > /tmp/assets_list.tmp
    
    while read -r file_path; do
        filename=$(basename "$file_path")
        name=$(echo "$filename" | sed 's/\.srs$//; s/\.json$//')
        
        total=$((total + 1))
        if download_rule "$name" "$file_path"; then
            success=$((success + 1))
        else
            fail=$((fail + 1))
            failed_list="$failed_list\n- $name"
        fi
    done < /tmp/assets_list.tmp
    rm -f /tmp/assets_list.tmp

    log_info "修缮完成。成功: $success / 失败: $fail"

    # 发送 TG 战报
    if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
        local msg="📚 <b>[HPPC] 典籍修缮报告</b>%0A"
        msg="${msg}--------------------------------%0A"
        msg="${msg}✅ 成功更新: <b>$success</b> 本%0A"
        if [ "$fail" -gt 0 ]; then
            msg="${msg}❌ 更新失败: <b>$fail</b> 本%0A"
            msg="${msg}⚠️ 缺失清单: $failed_list"
        else
            msg="${msg}🎉 所有规则集均为最新。"
        fi
        curl -sk -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
            -d "chat_id=$TG_CHAT_ID" -d "parse_mode=HTML" -d "text=$msg" > /dev/null 2>&1
    fi
}

# 路由入口
case "$1" in
    --resolve) resolve_deps "$2" ;;
    --update)  update_all ;;
    --download) download_manual "$2" ;;
    *) echo "Usage: $0 {--resolve <file> | --update | --download <name>}" ;;
esac
