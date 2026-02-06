#!/bin/sh
# --- [ HPPC v2.2: Castellan Installer (Fixed) ] ---
# 职责：环境预检、交互配置、模块装配、哨兵注册
# 修复：Wget SSL 问题、Crontab 自动模式参数

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[36m'; NC='\033[0m'
log() { echo -e "${BLUE}[工兵]${NC} $1"; }

CONF_FILE="/etc/hppc/hppc.conf"
# ⚠️ 请修改您的 GitHub 用户名
GH_USER="Vonzhen"
GH_REPO="hppc"
GH_BRANCH="master"
GH_BASE_URL="https://raw.githubusercontent.com/$GH_USER/$GH_REPO/$GH_BRANCH"

echo -e "\n🏰 \033[1;33mHPPC Castellan - 要塞指挥系统 v2.2 (Fix)\033[0m\n"

# [1] 征兵体检 (Pre-flight Check)
log "正在执行环境预检..."
PACKAGES=""
! command -v curl >/dev/null && PACKAGES="$PACKAGES curl"
! command -v jq >/dev/null   && PACKAGES="$PACKAGES jq"
! command -v openssl >/dev/null && PACKAGES="$PACKAGES openssl-util"
# [修复] 增加 SSL 根证书依赖检查
if ! opkg list-installed | grep -q "ca-bundle" && ! opkg list-installed | grep -q "ca-certificates"; then
    PACKAGES="$PACKAGES ca-bundle"
fi

if [ -n "$PACKAGES" ]; then
    echo -e "${YELLOW}>> 发现缺失依赖: $PACKAGES，正在征召...${NC}"
    # [修复] 尝试安装 ca-bundle，如果失败尝试 ca-certificates
    opkg update
    if ! opkg install $PACKAGES; then
        opkg install ca-certificates 2>/dev/null
    fi
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 依赖安装失败，请检查网络或软件源。${NC}"; exit 1
    fi
else
    echo -e "${GREEN}>> 环境健康，准予通行。${NC}"
fi

# [2] 清理与重建
[ -d "/usr/share/hppc" ] && rm -rf /usr/share/hppc
mkdir -p /etc/hppc /tmp/hppc
mkdir -p /usr/share/hppc/core /usr/share/hppc/lib /usr/share/hppc/bin /usr/share/hppc/modules
mkdir -p /usr/share/hppc/templates/models

# [3] 宣誓仪式 (配置)
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
    log "🏮 发现旧誓言，【$LOCATION】要塞保留原配置..."
else
    echo "------------------------------------------------"
    # 3.1 命名
    printf "${YELLOW}1. 赐名 (Location)${NC} [Winterfell]: "; read -r LOC_INPUT
    LOCATION="${LOC_INPUT:-Winterfell}"

    # 3.2 学城
    printf "${YELLOW}2. 学城域名 (Worker)${NC} [hppc.x.workers.dev]: "; read -r CF_DOMAIN

    # 3.3 信物
    printf "${YELLOW}3. 验证信物 (Token)${NC}: "; read -r CF_TOKEN

    # 3.4 渡鸦
    printf "${YELLOW}4. 渡鸦 Token (TG)${NC} [回车跳过]: "; read -r TG_TOKEN
    printf "${YELLOW}   渡鸦 ChatID (TG)${NC} [回车跳过]: "; read -r TG_ID

    # 3.5 私有军械库
    echo -e "${YELLOW}5. 私有规则源 (Private Rules Repo)${NC}"
    echo "   (例如: https://raw.githubusercontent.com/Me/rules/main)"
    printf "   请输入 [回车跳过]: "; read -r ASSETS_REPO
    echo "------------------------------------------------"

    # 刻录
    {
        echo "# --- HPPC: Castellan's Oath ---"
        echo "GH_RAW_URL='$GH_BASE_URL'"
        echo "CF_DOMAIN='$CF_DOMAIN'"
        echo "CF_TOKEN='$CF_TOKEN'"
        echo "TG_BOT_TOKEN='$TG_TOKEN'"
        echo "TG_CHAT_ID='$TG_ID'"
        echo "LOCATION='$LOCATION'"
        echo "ASSETS_PRIVATE_REPO='$ASSETS_REPO'"
    } > "$CONF_FILE"
    chmod 600 "$CONF_FILE"
fi

# [4] 调拨物资
download_asset() {
    # [修复] 增加 --no-check-certificate 防止 wget 自身的 SSL 报错
    wget --no-check-certificate -qO "$1" "$GH_BASE_URL/$2" && chmod +x "$1"
}

log "正在调配战略物资..."
# Core
download_asset "/usr/share/hppc/core/synthesize.sh" "core/synthesize.sh"
download_asset "/usr/share/hppc/core/fetch.sh"      "core/fetch.sh"
download_asset "/usr/share/hppc/core/daemon.sh"     "core/daemon.sh"
download_asset "/usr/share/hppc/core/rollback.sh"   "core/rollback.sh"
# Lib & Modules (Assets)
download_asset "/usr/share/hppc/lib/utils.sh"      "lib/utils.sh"
download_asset "/usr/share/hppc/modules/assets.sh" "modules/assets.sh"
# Bin
download_asset "/usr/share/hppc/bin/cli.sh"        "bin/cli.sh"
# Templates
wget --no-check-certificate -qO "/usr/share/hppc/templates/hp_base.uci" "$GH_BASE_URL/templates/hp_base.uci"
# 加入 anytls 和 tuic 到遍历列表
# --- 智能模具下载逻辑 ---
log "正在同步最新兵器模具 (Smart Sync)..."
# 1. 构建 API 请求地址
API_URL="https://api.github.com/repos/$GH_USER/$GH_REPO/contents/templates/models?ref=$GH_BRANCH"

# 2. 询问学城 (GitHub API) 目录下有哪些文件
# 使用 jq 提取所有 name 字段 (文件名)
TEMPLATE_LIST=$(curl -s "$API_URL" | jq -r '.[].name' 2>/dev/null)

if [ -n "$TEMPLATE_LIST" ]; then
    # 3. 清理旧模具 (防止改名后残留僵尸文件)
    rm -f /usr/share/hppc/templates/models/*.uci
    
    # 4. 动态遍历下载
    for uci_file in $TEMPLATE_LIST; do
        # 只下载 .uci 结尾的文件，防止误下载其他杂项
        if echo "$uci_file" | grep -q "\.uci$"; then
            echo "   - 获取模具: $uci_file"
            wget -qO "/usr/share/hppc/templates/models/$uci_file" "$GH_BASE_URL/templates/models/$uci_file"
        fi
    done
else
    # [降级方案] 如果 API 请求失败 (如 API 速率限制)，回退到核心列表
    log_warn "API 连接受限，切换至紧急备用清单..."
    for p in vless trojan hysteria2 shadowsocks anytls tuic; do
        wget -qO "/usr/share/hppc/templates/models/$p.uci" "$GH_BASE_URL/templates/models/$p.uci"
    done
fi

# [5] 部署守夜人
ln -sf /usr/share/hppc/bin/cli.sh /usr/bin/hppc

# 注册 Crontab (Core: 1min, Assets: 07:30 Daily [Auto Mode])
(crontab -l 2>/dev/null | grep -v "hppc" | grep -v "daemon.sh" | grep -v "assets.sh") | crontab -
(crontab -l 2>/dev/null; \
 echo "* * * * * /usr/share/hppc/core/daemon.sh"; \
 echo "30 7 * * * /usr/share/hppc/modules/assets.sh --update auto") | crontab -
# [注意] 上一行末尾增加了 'auto' 参数，这是实现每日自动重启的关键

echo -e "\n${GREEN}✅ Castellan 系统部署完毕！${NC}"
echo -e "指令：输入 ${YELLOW}hppc${NC} 进入指挥面板。"
echo -e "提示：首次安装后，请运行 'hppc' -> '6) 部署 WebUI'。"
rm -f "$0"
