#!/bin/sh
# --- [ HPPC: 领主议事厅 ] ---
source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

show_menu() {
    clear
    # 读取最新的 Tick (密令版本)
    TICK=$(cat /etc/hppc/last_tick 2>/dev/null || echo "Unknown")
    
    echo -e "${C_INFO}======================================${C_RESET}"
    echo -e "   ${C_WARN}HPCC 要塞指挥系统${C_RESET}"
    echo -e "   📍 驻地：${C_OK}$LOCATION${C_RESET}"
    echo -e "   📜 密令：${C_INFO}$TICK${C_RESET}"
    echo -e "${C_INFO}======================================${C_RESET}"
    echo ""
    echo -e "  1) ⚔️  ${C_OK}集结军队 (Muster)${C_RESET}"
    echo -e "     - 强制从学城拉取名单，重铸防线。"
    echo ""
    echo -e "  2) 🛡️  ${C_ERR}死守城池 (Retreat)${C_RESET}"
    echo -e "     - 紧急回滚至上一次的稳定防线。"
    echo ""
    echo -e "  3) 🦅  ${C_WARN}渡鸦汇报 (Status)${C_RESET}"
    echo -e "     - 检阅当前守夜人日志与系统状态。"
    echo ""
    echo -e "  4) 🗝️  ${C_INFO}查看誓言 (Config)${C_RESET}"
    echo -e "     - 查阅当前的环境变量配置。"
    echo ""
    echo -e "--------------------------------------"
    echo -e "  u) 🆙 军械升级 (Update Scripts)"
    echo -e "  q) 👋 离开议事厅"
    echo ""
    echo -ne "  ⚔️  请领主下令: "
}

while true; do
    show_menu
    read choice
    case $choice in
        1)
            echo ""
            log_info "正在吹响集结号角..."
            sh /usr/share/hppc/core/fetch.sh && sh /usr/share/hppc/core/synthesize.sh
            echo ""; echo "按回车返回..."; read ;;
        2)
            echo ""
            log_warn "正在执行焦土战术..."
            sh /usr/share/hppc/core/rollback.sh
            echo ""; echo "按回车返回..."; read ;;
        3)
            echo ""
            echo "--- [ 守夜人日志 ] ---"
            # 这里可以显示最近的日志，或者简单的运行状态
            ps | grep daemon.sh | grep -v grep >/dev/null && echo "✅ 哨兵 (Daemon): 在岗" || echo "❌ 哨兵 (Daemon): 缺席"
            echo "📅 最近更新: $(date -r /etc/config/homeproxy "+%Y-%m-%d %H:%M:%S")"
            echo "--- [ 兵力统计 ] ---"
            cat /tmp/hp_counts 2>/dev/null || echo "暂无数据"
            echo ""; echo "按回车返回..."; read ;;
        4)
            echo ""
            echo "--- [ 核心誓言 ] ---"
            grep -v "TOKEN" /etc/hppc/hppc.conf # 隐藏 Token 显示
            echo ""; echo "按回车返回..."; read ;;
        u)
            echo ""
            log_info "正在从铁金库重新打造兵器..."
            wget -qO /tmp/install.sh "$GH_RAW_URL/install.sh" && sh /tmp/install.sh
            echo ""; echo "按回车返回..."; read ;;
        q)
            clear; exit 0 ;;
        *)
            echo "无效指令"; sleep 1 ;;
    esac
done
