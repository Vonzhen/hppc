#!/bin/sh
# --- [ HPPC: Castellan Dashboard v2.3 ] ---
source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

# 诊断模块
run_doctor() {
    echo -e "\n🩺 \033[1;33m正在进行要塞诊断 (System Doctor)...\033[0m"
    echo "-------------------------------------"
    check_item() { if eval "$2"; then echo -e "  ✅ $1"; else echo -e "  ❌ $1"; fi }
    
    check_item "网络连通 (GitHub)" "curl -kIs https://api.github.com | grep '200' >/dev/null"
    check_item "信使 (curl)" "command -v curl >/dev/null"
    check_item "翻译官 (jq)" "command -v jq >/dev/null"
    check_item "配置文件" "[ -f /etc/hppc/hppc.conf ] && [ -n '$CF_TOKEN' ]"
    check_item "规则目录" "[ -d /etc/homeproxy/ruleset ]"
    check_item "运行状态" "/etc/init.d/homeproxy status 2>/dev/null | grep -q 'running'"
    echo "-------------------------------------"
    echo "诊断完成。若有 ❌，请检查网络或执行 'u' 升级修复。"
}

# 卸载模块
run_uninstall() {
    echo -e "\n${C_ERR}⚠️  危险操作：您确定要拆除 HPPC Castellan 系统吗？${C_RESET}"
    echo -e "   这将删除所有脚本、配置、Cron 任务及 WebUI 入口。"
    echo -ne "   确认拆除? [y/N]: "
    read confirm
    if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
        echo "执行焦土战术..."
        # 移除 WebUI
        uci delete luci.hppc_group 2>/dev/null
        uci delete luci.hppc_sync 2>/dev/null
        uci delete luci.hppc_assets 2>/dev/null
        uci commit luci
        # 移除 Cron
        (crontab -l 2>/dev/null | grep -v "hppc" | grep -v "daemon.sh" | grep -v "assets.sh") | crontab -
        # 删除文件
        rm -rf /usr/share/hppc /etc/hppc /usr/bin/hppc /tmp/hp_*
        echo -e "${C_OK}✅ 拆除完毕。江湖路远，有缘再见。${C_RESET}"
        exit 0
    else
        echo "操作取消。"
    fi
}

# WebUI 集成模块
setup_webui() {
    echo -e "\n🌐 \033[1;33m正在部署 WebUI 指挥台...\033[0m"
    if ! opkg list-installed | grep -q luci-app-commands; then
        echo "正在安装 luci-app-commands..."
        opkg update && opkg install luci-app-commands
    fi

    # 注册命令组
    uci set luci.hppc_group=command
    uci set luci.hppc_group.name='HPPC Castellan'
    uci set luci.hppc_group.command='' 

    # 注册指令 1: 集结
    uci set luci.hppc_sync=command
    uci set luci.hppc_sync.name='⚔️ 集结军队 (Sync Config)'
    uci set luci.hppc_sync.command='/usr/bin/hppc sync'
    uci set luci.hppc_sync.param='1' # 允许带参数? 这里不需要

    # 注册指令 2: 更新规则
    uci set luci.hppc_assets=command
    uci set luci.hppc_assets.name='📚 修缮典籍 (Update Rules)'
    uci set luci.hppc_assets.command='/usr/bin/hppc assets'

    uci commit luci
    echo -e "${C_OK}✅ 部署完成！请刷新 LuCI 页面，查看 [系统] -> [自定义命令]。${C_RESET}"
}

show_menu() {
    clear
    TICK=$(cat /etc/hppc/last_tick 2>/dev/null || echo "Unknown")
    NODE_COUNT=$(grep "config node" /etc/config/homeproxy 2>/dev/null | wc -l)
    STATUS=$(/etc/init.d/homeproxy status 2>/dev/null | grep -q "running" && echo -e "${C_OK}运行中${C_RESET}" || echo -e "${C_ERR}已停止${C_RESET}")
    
    echo -e "${C_INFO}=========================================${C_RESET}"
    echo -e "   🐺 \033[1mHPPC Castellan - 要塞指挥系统\033[0m"
    echo -e "${C_INFO}=========================================${C_RESET}"
    echo -e "   📍 驻地: ${C_WARN}$LOCATION${C_RESET}      🟢 状态: $STATUS"
    echo -e "   📜 密令: ${C_INFO}$TICK${C_RESET}      🌍 节点: ${C_OK}$NODE_COUNT${C_RESET}"
    echo -e "${C_INFO}-----------------------------------------${C_RESET}"
    echo ""
    echo -e "  1) ⚔️  ${C_OK}集结军队 (Muster)${C_RESET}"
    echo -e "     - 拉取配置，检查依赖，重铸防线。"
    echo ""
    echo -e "  2) 📚 ${C_WARN}修缮典籍 (Update Rules)${C_RESET}"
    echo -e "     - 更新规则集 (含 TG 通知)。"
    echo ""
    echo -e "  3) 📥 ${C_INFO}征收物资 (Download Rule)${C_RESET}"
    echo -e "     - 手动下载指定规则 (GeoIP/Geosite)。"
    echo ""
    echo -e "  4) 🛡️  ${C_ERR}死守城池 (Rollback)${C_RESET}"
    echo -e "     - 紧急回滚至上一次的稳定配置。"
    echo ""
    echo -e "  5) 🩺 ${C_INFO}要塞诊断 (Doctor)${C_RESET}"
    echo -e "     - 检查环境健康度。"
    echo ""
    echo -e "  6) 🌐 ${C_OK}部署 WebUI (LuCI Integration)${C_RESET}"
    echo -e "     - 将 HPPC 命令注册到网页后台。"
    echo ""
    echo -e "-----------------------------------------"
    echo -e "  x) ❌ 拆除要塞    u) 🆙 升级脚本    q) 👋 离开"
    echo ""
    echo -ne "  ⚔️  请领主下令: "
}

# 命令行直达接口
case "$1" in
    doctor) run_doctor; exit 0 ;;
    assets) sh /usr/share/hppc/modules/assets.sh --update; exit 0 ;;
    sync)   sh /usr/share/hppc/core/fetch.sh && sh /usr/share/hppc/core/synthesize.sh; exit 0 ;;
esac

while true; do
    show_menu
    read choice
    case $choice in
        1) echo ""; log_info "吹响集结号角..."; sh /usr/share/hppc/core/fetch.sh && sh /usr/share/hppc/core/synthesize.sh; echo ""; echo "按回车返回..."; read ;;
        2) echo ""; log_info "开始修缮典籍..."; sh /usr/share/hppc/modules/assets.sh --update; echo ""; echo "按回车返回..."; read ;;
        
        # [手动下载]
        3) 
           echo ""
           echo -e "${C_INFO}请输入规则集名称 (必须包含前缀):${C_RESET}"
           echo -e "示例: ${C_WARN}geosite-openai${C_RESET} 或 ${C_WARN}geoip-netflix${C_RESET}"
           echo -ne "输入: "
           read rule_name
           if [ -n "$rule_name" ]; then
               sh /usr/share/hppc/modules/assets.sh --download "$rule_name"
           fi
           echo ""; echo "按回车返回..."; read 
           ;;
           
        4) echo ""; log_warn "执行焦土战术..."; sh /usr/share/hppc/core/rollback.sh; echo ""; echo "按回车返回..."; read ;;
        5) run_doctor; echo ""; echo "按回车返回..."; read ;;
        # [WebUI]
        6) setup_webui; echo ""; echo "按回车返回..."; read ;;
        
        x) run_uninstall ;;
        u) echo ""; log_info "重新打造兵器..."; wget -qO /tmp/install.sh "$GH_RAW_URL/install.sh" && sh /tmp/install.sh; echo ""; echo "按回车返回..."; read ;;
        q) clear; exit 0 ;;
        *) echo "无效指令"; sleep 1 ;;
    esac
done
