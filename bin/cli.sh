#!/bin/sh
# --- [ HPPC: Castellan Dashboard ] ---
source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

# 诊断模块 (Doctor)
run_doctor() {
    echo -e "\n🩺 \033[1;33m正在进行要塞诊断 (System Doctor)...\033[0m"
    echo "-------------------------------------"
    
    check_item() {
        if eval "$2"; then echo -e "  ✅ $1"; else echo -e "  ❌ $1"; fi
    }
    
    check_item "网络连通 (GitHub)" "curl -Is https://api.github.com | grep '200' >/dev/null"
    check_item "信使 (curl)" "command -v curl >/dev/null"
    check_item "翻译官 (jq)" "command -v jq >/dev/null"
    check_item "配置文件" "[ -f /etc/hppc/hppc.conf ] && [ -n '$CF_TOKEN' ]"
    check_item "规则目录" "[ -d /etc/homeproxy/ruleset ]"
    check_item "运行状态" "/etc/init.d/homeproxy status 2>/dev/null | grep -q 'running'"
    
    echo "-------------------------------------"
    echo "诊断完成。若有 ❌，请检查网络或重新安装依赖。"
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
    echo -e "     - 从学城拉取最新配置，重铸防线。"
    echo ""
    echo -e "  2) 📚 ${C_WARN}修缮典籍 (Assets)${C_RESET}"
    echo -e "     - 更新所有规则集 (含私有源)。"
    echo ""
    echo -e "  3) 🛡️  ${C_ERR}死守城池 (Rollback)${C_RESET}"
    echo -e "     - 紧急回滚至上一次的稳定防线。"
    echo ""
    echo -e "  4) 🩺 ${C_INFO}要塞诊断 (Doctor)${C_RESET}"
    echo -e "     - 检查系统健康度与依赖项。"
    echo ""
    echo -e "-----------------------------------------"
    echo -e "  u) 🆙 升级脚本    q) 👋 离开"
    echo ""
    echo -ne "  ⚔️  请领主下令: "
}

# 支持命令行参数: hppc doctor / hppc assets
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
        3) echo ""; log_warn "执行焦土战术..."; sh /usr/share/hppc/core/rollback.sh; echo ""; echo "按回车返回..."; read ;;
        4) run_doctor; echo ""; echo "按回车返回..."; read ;;
        u) echo ""; log_info "重新打造兵器..."; wget -qO /tmp/install.sh "$GH_RAW_URL/install.sh" && sh /tmp/install.sh; echo ""; echo "按回车返回..."; read ;;
        q) clear; exit 0 ;;
        *) echo "无效指令"; sleep 1 ;;
    esac
done
