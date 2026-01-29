#!/bin/sh
# --- [ HPPC Core: 红袍祭司 (Rollback) ] ---
# 职责：执行物理回滚并复活服务

source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

CONF="/etc/config/homeproxy"
BAK_CONF="/etc/config/homeproxy.bak"

if [ -f "$BAK_CONF" ]; then
    log_warn "正在施展复活术 (物理回滚)..."
    cp "$BAK_CONF" "$CONF"
    uci commit homeproxy
    
    log_success "已恢复至旧日荣光。正在重启服务以自愈..."
    /etc/init.d/homeproxy restart
    
    tg_send "🚨 <b>警报</b>：【$LOCATION】已执行物理回滚并重启！\n光之王保佑我们。"
else
    log_err "未发现先祖遗物 (Backup)，复活失败。"
fi
