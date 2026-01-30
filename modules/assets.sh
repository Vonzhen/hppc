#!/bin/sh
# --- [ HPPC Module: 物资代官 (Assets) ] ---
# 职责：规则集 (RuleSet) 的订阅、下载与依赖补全

source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

RULE_DIR="/etc/homeproxy/ruleset"
mkdir -p "$RULE_DIR"

# 1. 定义源 (Source Definition)
SRC_PRIVATE="$ASSETS_PRIVATE_REPO"
SRC_GEOSITE="https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set"
SRC_GEOIP="https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set"

download_rule() {
    local name="$1"
    local path="$2"
    
    log_info "正在寻访典籍: $name ..."

    # [策略 A] 私有库优先
    if [ -n "$SRC_PRIVATE" ]; then
        if curl -sL --connect-timeout 10 "$SRC_PRIVATE/$name.srs" -o "$path.tmp"; then
            if [ -s "$path.tmp" ] && ! grep -q "404" "$path.tmp"; then
                mv "$path.tmp" "$path"
                log_success "⚔️ 已从私有库获取: $name"
                return 0
            fi
        fi
        rm -f "$path.tmp"
    fi

    # [策略 B] 公共库兜底
    local url=""
    case "$name" in
        geoip-*)   url="$SRC_GEOIP/${name#geoip-}.srs" ;;
        geosite-*) url="$SRC_GEOSITE/${name#geosite-}.srs" ;;
        *)         log_err "命名违规: $name"; return 1 ;;
    esac

    curl -sL --connect-timeout 15 "$url" -o "$path.tmp"
    
    if [ -s "$path.tmp" ] && ! grep -q "404" "$path.tmp"; then
        mv "$path.tmp" "$path"
        log_success "📚 已从公共库获取: $name"
        return 0
    else
        rm -f "$path.tmp"
        log_err "物资缺失 (所有源均未找到): $name"
        return 1
    fi
}

resolve_deps() {
    local config_file="$1"
    log_info "代官正在核对物资清单..."
    # 提取所有 option path '...'
    grep "option path" "$config_file" | awk -F"'" '{print $2}' | sort | uniq | while read -r file_path; do
        if [ ! -f "$file_path" ]; then
            filename=$(basename "$file_path")
            name=$(echo "$filename" | sed 's/\.srs$//; s/\.json$//')
            log_warn "发现短缺: $name，启动紧急采购..."
            download_rule "$name" "$file_path"
        fi
    done
}

update_all() {
    log_info "开始每日物资修缮..."
    CURRENT_CONF="/etc/config/homeproxy"
    [ ! -f "$CURRENT_CONF" ] && return
    
    grep "option path" "$CURRENT_CONF" | awk -F"'" '{print $2}' | sort | uniq | while read -r file_path; do
        filename=$(basename "$file_path")
        name=$(echo "$filename" | sed 's/\.srs$//; s/\.json$//')
        download_rule "$name" "$file_path"
    done
}

case "$1" in
    --resolve) resolve_deps "$2" ;;
    --update)  update_all ;;
    *) echo "Usage: $0 {--resolve <file> | --update}" ;;
esac
