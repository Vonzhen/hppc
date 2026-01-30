#!/bin/sh
# --- [ HPPC v2.1: Castellan Installer ] ---
# 职责：环境预检、交互配置、模块装配、哨兵注册

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[36m'; NC='\033[0m'
log() { echo -e "${BLUE}[工兵]${NC} $1"; }

CONF_FILE="/etc/hppc/hppc.conf"
# ⚠️ 请修改您的 GitHub 用户名
GH_USER="Vonzhen"
GH_REPO="hppc"
GH_BRANCH="master"
GH_BASE_URL="https://raw.githubusercontent.com/$GH_USER/$GH_REPO/$GH_BRANCH"

echo -e "\n🏰 \033[1;33mHPPC Castellan - 要塞指挥系统 v2.1\033[0m\n"

# [1] 征兵体检 (Pre-flight Check)
log "正在执行环境预检..."
PACKAGES=""
! command -v curl >/dev/null && PACKAGES="$PACKAGES curl"
! command -v jq >/dev/null   && PACKAGES="$PACKAGES jq"
! command -v openssl >/dev/null && PACKAGES="$PACKAGES openssl-util"

if [ -n "$PACKAGES" ]; then
    echo -e "${YELLOW}>> 发现缺失依赖: $PACKAGES，正在征召...${NC}"
    opkg update && opkg install $PACKAGES
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

    # 3.5 私有军械库 (新功能)
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
    wget -qO "$1" "$GH_BASE_URL/$2" && chmod +x "$1"
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
wget -qO "/usr/share/hppc/templates/hp_base.uci" "$GH_BASE_URL/templates/hp_base.uci"
for p in vless trojan hysteria2 shadowsocks; do
    wget -qO "/usr/share/hppc/templates/models/$p.uci" "$GH_BASE_URL/templates/models/$p.uci"
done

# [5] 部署守夜人
ln -sf /usr/share/hppc/bin/cli.sh /usr/bin/hppc

# 注册 Crontab (Core: 1min, Assets: 04:00 Daily)
(crontab -l 2>/dev/null | grep -v "hppc" | grep -v "daemon.sh" | grep -v "assets.sh") | crontab -
(crontab -l 2>/dev/null; \
 echo "* * * * * /usr/share/hppc/core/daemon.sh"; \
 echo "0 4 * * * /usr/share/hppc/modules/assets.sh --update") | crontab -

echo -e "\n${GREEN}✅ Castellan 系统部署完毕！${NC}"
echo -e "指令：输入 ${YELLOW}hppc${NC} 进入指挥面板。"
rm -f "$0"
