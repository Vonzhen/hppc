#!/bin/sh
# --- [ HPPC Module: 物资代官 (Assets) v3.0 ] ---
# 职责：规则集 (RuleSet) 的订阅、下载与依赖补全
# 适配源：MetaCubeX/meta-rules-dat (sing branch)

source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

RULE_DIR="/etc/homeproxy/ruleset"
mkdir -p "$RULE_DIR"

# 1. 定义源 (Sources)
SRC_PRIVATE="$ASSETS_PRIVATE_REPO"

# MetaCubeX 仓库基地址 (sing 分支)
# 结构: https://github.com/MetaCubeX/meta-rules-dat/raw/sing/geo/[type]/[name].srs
BASE_URL="https://github.com/MetaCubeX/meta-rules-dat/raw/sing"

download_file() {
    local url="$1"
    local dest="$2"
    
    # -k: 允许不安全SSL (防止 OpenWrt 证书问题)
    # -L: 跟随重定向
    # -f: HTTP 错误时(如404)不写入文件
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

download_rule() {
    local target_filename="$1"  # 例如: geosite-apple
    local target_path="$2"      # 例如: /etc/homeproxy/ruleset/geosite-apple.srs
    
    log_info "正在寻访典籍: $target_filename ..."

    # ---------------------------------------------------------
    # [策略 A] 私有库优先 (Private First)
    # ---------------------------------------------------------
    if [ -n "$SRC_PRIVATE" ]; then
        if download_file "$SRC_PRIVATE/$target_filename.srs" "$target_path"; then
            log_success "⚔️ [私有] 已获取: $target_filename"
            return 0
        fi
    fi

    # ---------------------------------------------------------
    # [策略 B] 智能解析 MetaCubeX 仓库结构
    # ---------------------------------------------------------
    # 1. 拆解前缀: geosite-apple -> type="geosite", name="apple"
    local type="${target_filename%%-*}" # 取第一个 - 左边的 (geoip / geosite)
    local name="${target_filename#*-}"  # 取第一个 - 右边的 (apple / cn / ...)

    # 修正 type 目录名 (MetaCubeX 仓库里是 geosite 和 geoip)
    # 这里的 type 变量已经是 'geosite' 或 'geoip' 了，直接用即可

    # 定义可能的上游路径列表 (按优先级尝试)
    # 注意：MetaCubeX 的文件名通常不带前缀，如 apple.srs
    local urls_to_try=""
    
    # 尝试顺序 1: Standard 目录 (geo/...)
    urls_to_try="$urls_to_try $BASE_URL/geo/$type/$name.srs"
    
    # 尝试顺序 2: Lite 目录 (geo-lite/...) - 解决您提到的 geoip-apple 问题
    urls_to_try="$urls_to_try $BASE_URL/geo-lite/$type/$name.srs"

    # ---------------------------------------------------------
    # [策略 C] 执行搜寻
    # ---------------------------------------------------------
    for url in $urls_to_try; do
        # 调试模式下可以打印尝试的 URL
        # echo "Trying: $url" 
        
        if download_file "$url" "$target_path"; then
            log_success "📚 [公共] 已获取: $target_filename"
            return 0
        fi
    done

    # ---------------------------------------------------------
    # [策略 D] 失败处理
    # ---------------------------------------------------------
    log_err "物资缺失: $target_filename (在标准库和 Lite 库均未找到)"
    return 1
}

resolve_deps() {
    local config_file="$1"
    log_info "代官正在核对物资清单..."
    # 提取所有 option path '...' 并去重
    grep "option path" "$config_file" | awk -F"'" '{print $2}' | sort | uniq | while read -r file_path; do
        # 如果文件不存在，或者文件大小为0 (之前的错误下载)，则重新下载
        if [ ! -s "$file_path" ]; then
            filename=$(basename "$file_path")
            # 去掉后缀 .srs 或 .json 得到纯名称 (如 geosite-apple)
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

# 命令行入口
case "$1" in
    --resolve) resolve_deps "$2" ;;
    --update)  update_all ;;
    *) echo "Usage: $0 {--resolve <file> | --update}" ;;
esac
