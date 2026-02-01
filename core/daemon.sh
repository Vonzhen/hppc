#!/bin/sh
# --- [ HPPC Core: 无面者 (Daemon) v2.1 Fixed ] ---
# 职责：静默监听学城信号 (Endpoint: /tg-sync)
# 修复：下载成功后才更新时间戳，防止网络失败导致漏更

[ -f "/etc/hppc/hppc.conf" ] || exit 1
source /etc/hppc/hppc.conf

TICK_FILE="/etc/hppc/last_tick"
LOCK_FILE="/tmp/hppc_daemon.lock"

# 1. 屏息 (File Lock)
exec 9>"$LOCK_FILE"
if ! flock -n 9; then exit 1; fi

# 2. 截获密信 (Check Tick)
# 注意：这里保留了您特定的 /tg-sync 接口
REMOTE_TICK=$(curl -skL --connect-timeout 10 "https://$CF_DOMAIN/tg-sync?token=$CF_TOKEN")

# 简单校验：必须非空，且不包含 Unauthorized
[ -z "$REMOTE_TICK" ] || [ "$REMOTE_TICK" = "Unauthorized" ] && exit 1

LAST_TICK=$(cat "$TICK_FILE" 2>/dev/null || echo "0")

# 3. 命运裁决 (Trigger Update)
# 使用数字对比 (-gt)
if [ "$REMOTE_TICK" -gt "$LAST_TICK" ] 2>/dev/null; then
    
    # [关键修复] 不要在这里先写文件！先去执行任务
    
    # 执行军需官 (Fetch)
    if /bin/sh /usr/share/hppc/core/fetch.sh >/dev/null 2>&1; then
        
        # 只有 Fetch 成功了，才更新本地时间戳
        echo "$REMOTE_TICK" > "$TICK_FILE"
        
        # 进而执行炼金术士 (Synthesize)
        /bin/sh /usr/share/hppc/core/synthesize.sh >/dev/null 2>&1
    fi
    # 如果 Fetch 失败，TICK_FILE 保持不变，下一分钟哨兵会再次尝试 (重试机制)
fi
