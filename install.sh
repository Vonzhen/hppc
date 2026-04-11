#!/bin/sh
# --- [ HPPC v3.0: Castellan Installer (要塞指挥系统铸造仪式) ] ---
# 职能：长城地基勘探、要塞资源初始化、核心指挥系统装配
# 修复：预装阶段未定义函数导致的 P0 级崩溃；写入事务化所需的常量配置

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[36m'; NC='\033[0m'

# [预装期日志函数] 修复 P0: 防止在 utils.sh 落地前触发调用崩溃
log()      { echo -e "${BLUE}[$(date +'%H:%M:%S')][INFO][工兵]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')][WARN][警示]${NC} $1"; }
log_err()  { echo -e "${RED}[$(date +'%H:%M:%S')][ERR][噩耗]${NC} $1"; }

CONF_FILE="/etc/hppc/hppc.conf"
# [军需官注意] 请确认您的 GitHub 将领旗号
GH_USER="Vonzhen"
GH_REPO="hppc"
GH_BRANCH="master"
GH_BASE_URL="https://raw.githubusercontent.com/$GH_USER/$GH_REPO/$GH_BRANCH"

echo -e "\n🏰 \033[1;33mHPPC Castellan - 要塞指挥系统 v3.0\033[0m\n"

# [1] 征兵体检 (Pre-flight Dependency Check)
log "正在执行环境预检..."
PACKAGES=""
! command -v curl >/dev/null && PACKAGES="$PACKAGES curl"
! command -v jq >/dev/null   && PACKAGES="$PACKAGES jq"
! command -v openssl >/dev/null && PACKAGES="$PACKAGES openssl-util"

# 增加 SSL 根证书依赖检查，防止铁金库物资被劫持
if ! opkg list-installed | grep -q "ca-bundle" && ! opkg list-installed | grep -q "ca-certificates"; then
    PACKAGES="$PACKAGES ca-bundle"
fi

if [ -n "$PACKAGES" ]; then
    echo -e "${YELLOW}>> 发现缺失依赖: $PACKAGES，正在紧急征召...${NC}"
    opkg update
    if ! opkg install $PACKAGES; then
        # 尝试备用根证书包
        opkg install ca-certificates 2>/dev/null
    fi
    
    if [ $? -ne 0 ]; then
        log_err "依赖安装失败，补给线被切断。停止安装。"
        exit 1
    fi
else
    echo -e "${GREEN}>> 驻地环境健康，准予通行。${NC}"
fi

# [2] 清理与重建 (Foundation Rebuild)
[ -d "/usr/share/hppc" ] && rm -rf /usr/share/hppc
mkdir -p /etc/hppc /tmp/hppc
mkdir -p /usr/share/hppc/core /usr/share/hppc/lib /usr/share/hppc/bin /usr/share/hppc/modules
mkdir -p /usr/share/hppc/templates/models

# [3] 宣誓仪式 (Configuration Generation)
if [ -f "$CONF_FILE" ]; then
    . "$CONF_FILE"
    log "🏮 发现旧日誓言，【$LOCATION】要塞保留原防线配置..."
else
    echo "------------------------------------------------"
    printf "${YELLOW}1. 赐名 (Location)${NC} [Winterfell]: "; read -r LOC_INPUT
    LOCATION="${LOC_INPUT:-Winterfell}"

    printf "${YELLOW}2. 学城域名 (Worker)${NC} [hppc.x.workers.dev]: "; read -r CF_DOMAIN
    printf "${YELLOW}3. 验证信物 (Token)${NC}: "; read -r CF_TOKEN
    printf "${YELLOW}4. 渡鸦 Token (TG)${NC} [回车跳过]: "; read -r TG_TOKEN
    printf "${YELLOW}   渡鸦 ChatID (TG)${NC} [回车跳过]: "; read -r TG_ID
    
    echo -e "${YELLOW}5. 私有规则源 (Private Rules Repo)${NC}"
    echo "   (例如: https://raw.githubusercontent.com/Me/rules/main)"
    printf "   请输入 [回车跳过]: "; read -r ASSETS_REPO
    echo "------------------------------------------------"

    # 刻录誓言卷轴，注入架构常量
    {
        echo "# --- [ HPPC: 守夜人誓言卷轴 ] ---"
        echo "DIR_BASE='/usr/share/hppc'"
        echo "DIR_CORE='\${DIR_BASE}/core'"
        echo "DIR_MODULES='\${DIR_BASE}/modules'"
        echo "DIR_TEMPLATES='\${DIR_BASE}/templates'"
        echo "DIR_TMP='/tmp/hppc'"
        echo "FILE_CONF_PROD='/etc/config/homeproxy'"
        echo "FILE_LOCK='/var/run/hppc.lock'"
        echo ""
        echo "SETTING_AUTO_RELOAD=0"
        echo "SETTING_INSECURE_SKIP_VERIFY=0"
        echo ""
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

# [4] 调拨物资 (Assets Fetching)
download_asset() {
    local target_path="$1"
    local repo_path="$2"
    # 打印透明账本明细
    echo -e "   - 📥 \033[36m换装\033[0m: $repo_path"
    
    # 执行下载并赋予执行权限
    if ! wget --no-check-certificate -qO "$target_path" "$GH_BASE_URL/$repo_path"; then
        log_err "物资调拨失败: $repo_path"
        exit 1
    fi
    chmod +x "$target_path"
}

log "正在从铁金库调配核心战略物资 (Core & Modules)..."
download_asset "/usr/share/hppc/core/synthesize.sh" "core/synthesize.sh"
download_asset "/usr/share/hppc/core/fetch.sh"      "core/fetch.sh"
download_asset "/usr/share/hppc/core/daemon.sh"     "core/daemon.sh"
download_asset "/usr/share/hppc/core/rollback.sh"   "core/rollback.sh"

download_asset "/usr/share/hppc/lib/utils.sh"       "lib/utils.sh"
download_asset "/usr/share/hppc/modules/assets.sh"  "modules/assets.sh"
download_asset "/usr/share/hppc/bin/cli.sh"         "bin/cli.sh"
download_asset "/usr/share/hppc/templates/hp_base.uci" "templates/hp_base.uci"

# --- 智能模具下载逻辑 (Smart Sync) ---
log "正在同步最新兵器模具 (Smart Sync)..."
API_URL="https://api.github.com/repos/$GH_USER/$GH_REPO/contents/templates/models?ref=$GH_BRANCH"

TEMPLATE_LIST=$(curl -skL --connect-timeout 10 "$API_URL" | jq -r '.[].name' 2>/dev/null)

if [ -n "$TEMPLATE_LIST" ] && [ "$TEMPLATE_LIST" != "null" ]; then
    rm -f /usr/share/hppc/templates/models/*.uci
    for uci_file in $TEMPLATE_LIST; do
        if echo "$uci_file" | grep -q "\.uci$"; then
            echo "   - 获取模具: $uci_file"
            download_asset "/usr/share/hppc/templates/models/$uci_file" "templates/models/$uci_file"
        fi
    done
else
    # [应急机制] API 封锁时的降级防御
    log_warn "铁金库 API 连接受限，切换至紧急备用兵器清单..."
    for p in vless trojan hysteria2 shadowsocks anytls tuic; do
        download_asset "/usr/share/hppc/templates/models/$p.uci" "templates/models/$p.uci"
    done
fi

# [5] 部署守夜人驻防序列 (Cron & CLI)
ln -sf /usr/share/hppc/bin/cli.sh /usr/bin/hppc

(crontab -l 2>/dev/null | grep -v "hppc" | grep -v "daemon.sh" | grep -v "assets.sh") | crontab -
(crontab -l 2>/dev/null; \
 echo "* * * * * /usr/share/hppc/core/daemon.sh"; \
 echo "30 7 * * * /usr/share/hppc/modules/assets.sh --update auto") | crontab -

echo -e "\n${GREEN}✅ Castellan 系统部署完毕，长城防线已建立！${NC}"
echo -e "指令：输入 ${YELLOW}hppc${NC} 进入指挥面板。"
echo -e "提示：若需要自动化重载服务，请修改 /etc/hppc/hppc.conf 中的 SETTING_AUTO_RELOAD=1。"
rm -f "$0"
