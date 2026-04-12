#!/bin/sh
# --- [ HPPC Core: 安全回滚 (Rollback) v3.6 ] ---
# 职责：执行配置回滚并恢复系统服务
# 修复：文案专业化；对接全局常量；增加启动状态判断闭环。

. /etc/hppc/hppc.conf
. /usr/share/hppc/lib/utils.sh

CONF="$HP_CONF_FILE"
BAK_CONF="${HP_CONF_FILE}.bak"

if [ -f "$BAK_CONF" ]; then
    log_warn "检测到紧急状况，正在执行配置回滚..."
    
    # 原子恢复配置
    cp "$BAK_CONF" "$CONF"
    uci commit homeproxy
    
    log_success "配置已还原至上一个安全备份。正在重启系统服务..."
    
    # 重启并捕捉状态
    if /etc/init.d/homeproxy restart; then
        tg_send "🚨 <b>系统警报</b>%0A--------------------------------%0A【$LOCATION】遭遇异常，已成功执行配置回滚并重启服务。"
        log_success "回滚重启完成，网络防线已恢复正常。"
    else
        log_err "严重故障：回滚后服务仍无法启动，请通过终端手动排查！"
        tg_send "❌ <b>致命警报</b>%0A--------------------------------%0A【$LOCATION】回滚后服务仍然启动失败，系统可能处于断网状态，请立即介入排查。"
    fi
else
    log_err "未发现可用备份 ($BAK_CONF)，回滚中止。"
fi
