#!/bin/sh
# --- [ HPPC Core: 后台巡检守护进程 (Daemon) v3.6 ] ---
# 职责：静默监听远端信号并触发更新
# 修复：引入全局互斥锁防止与手动同步踩踏；去除角色扮演；强化错误处理。

[ -f "/etc/hppc/hppc.conf" ] || exit 0
. /etc/hppc/hppc.conf
. /usr/share/hppc/lib/utils.sh

TICK_FILE="/etc/hppc/last_tick"
LOCK_FILE="$HPPC_MAIN_LOCK" # 对接 utils.sh 中的全局锁常量

# 1. 获取全局排他锁 (防并发踩踏)
exec 200>"$LOCK_FILE"
if ! flock -n 200; then 
    # 锁被占用，静默退出等待下一分钟
    exit 0
fi

# 2. 检查远端版本信号 (Tick)
REMOTE_TICK=$(curl -skL --connect-timeout 10 "https://$CF_DOMAIN/tg-sync?token=$CF_TOKEN")
[ -z "$REMOTE_TICK" ] || [ "$REMOTE_TICK" = "Unauthorized" ] && exit 0

LAST_TICK=$(cat "$TICK_FILE" 2>/dev/null || echo "0")

# 3. 触发更新逻辑
if [ "$REMOTE_TICK" != "$LAST_TICK" ]; then
    # 确保依赖组件 Fetch 执行成功后才更新本地 Tick
    if /bin/sh /usr/share/hppc/core/fetch.sh >/dev/null 2>&1; then
        echo "$REMOTE_TICK" > "$TICK_FILE"
        # 进而触发合成器
        /bin/sh /usr/share/hppc/core/synthesize.sh >/dev/null 2>&1
    fi
fi
