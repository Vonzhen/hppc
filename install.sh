#!/bin/sh
# --- [ HPPC: The Vaelen Protocol ] ---
# 职责：筑城 (初始化)、宣誓 (配置)、连接学城 (Worker)

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[36m'; NC='\033[0m'
log() { echo -e "${BLUE}[工兵]${NC} $1"; }

# 1. 清理旧时代的废墟
CONF_FILE="/etc/hppc/hppc.conf"
[ -d "/usr/share/hppc" ] && rm -rf /usr/share/hppc
# 建立 HPPC 标准目录
mkdir -p /etc/hppc /usr/share/hppc/core /usr/share/hppc/lib /usr/share/hppc/bin /usr/share/hppc/templates/models /tmp/hppc

# 2. 锁定铁金库坐标 (GitHub)
GH_USER="Vonzhen"
GH_REPO="hppc"   # 统一为 hppc
GH_BRANCH="master"
GH_BASE_URL="https://raw.githubusercontent.com/$GH_USER/$GH_REPO/$GH_BRANCH"

# 3. 宣誓仪式 (配置生成)
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
    log "🏮 发现旧有誓言，【$LOCATION】要塞正在静默整编..."
else
    log "⚔️  领主大人，无面者工兵已就位。请赐予新要塞以名讳..."
    echo "------------------------------------------------"
    exec < /dev/tty

    # 3.1 命名
    echo -e "${YELLOW}1. 赐名 (要塞代号)${NC}"
    printf "   (例如 Winterfell, CastleBlack): "; read -r LOC_INPUT
    LOCATION="${LOC_INPUT:-Winterfell}"

    # 3.2 学城连接
    echo -e "\n${YELLOW}2. 连接学城 (Cloudflare Worker)${NC}"
    echo -e "   域名示例: ${BLUE}hppc.name.workers.dev${NC}"
    printf "   请输入: "; read -r CF_DOMAIN

    # 3.3 信物
    echo -e "\n${YELLOW}3. 交出信物 (Token)${NC}"
    printf "   请输入: "; read -r CF_TOKEN

    # 3.4 渡鸦
    echo -e "\n${YELLOW}4. 驯养渡鸦 (Telegram 通知)${NC}"
    printf "   Bot Token (回车跳过): "; read -r TG_TOKEN
    printf "   Chat ID   (回车跳过): "; read -r TG_ID
    echo "------------------------------------------------"

    # 刻录誓言
    {
        echo "# --- HPCC: Vaelen's Oath ---"
        echo "GH_RAW_URL='$GH_BASE_URL'"
        echo "CF_DOMAIN='$CF_DOMAIN'"
        echo "CF_TOKEN='$CF_TOKEN'"
        echo "TG_BOT_TOKEN='$TG_TOKEN'"
        echo "TG_CHAT_ID='$TG_ID'"
        echo "LOCATION='$LOCATION'"
    } > "$CONF_FILE"
    chmod 600 "$CONF_FILE"
    log "📝 誓言已刻录于 $CONF_FILE"
fi

# 4. 调配物资 (下载)
download_asset() {
    local dest="$1"; local src="$2"
    wget -qO "$dest" "$GH_BASE_URL/$src" && chmod +x "$dest"
}

log "正在从铁金库调拨物资..."
# Core
download_asset "/usr/share/hppc/core/synthesize.sh" "core/synthesize.sh"
download_asset "/usr/share/hppc/core/fetch.sh"      "core/fetch.sh"
download_asset "/usr/share/hppc/core/daemon.sh"     "core/daemon.sh"
download_asset "/usr/share/hppc/core/rollback.sh"   "core/rollback.sh"
# Lib & Bin
download_asset "/usr/share/hppc/lib/utils.sh"      "lib/utils.sh"
download_asset "/usr/share/hppc/bin/cli.sh"        "bin/cli.sh"
# Templates
wget -qO "/usr/share/hppc/templates/hp_base.uci" "$GH_BASE_URL/templates/hp_base.uci"
for p in vless trojan hysteria2 shadowsocks; do
    wget -qO "/usr/share/hppc/templates/models/$p.uci" "$GH_BASE_URL/templates/models/$p.uci"
done

# 5. 就位
ln -sf /usr/share/hppc/bin/cli.sh /usr/bin/hppc
(crontab -l 2>/dev/null | grep -v "hppc") | crontab -
(crontab -l 2>/dev/null; echo "* * * * * /usr/share/hppc/core/daemon.sh") | crontab -

echo -e "\n${GREEN}==============================================${NC}"
echo -e "${YELLOW}   HPCC 要塞建造完毕！${NC}"
echo -e "----------------------------------------------"
echo -e " 领主：${BLUE}$GH_USER${NC}"
echo -e " 坐标：${YELLOW}【$LOCATION】${NC}"
echo -e " 状态：${GREEN}守夜人 (Daemon) 已开始值守。${NC}"
echo -e " 指引：输入 ${GREEN}'hppc'${NC} 进入议事厅"
echo -e "${GREEN}==============================================${NC}\n"
rm -f "$0"
