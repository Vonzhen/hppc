#!/bin/sh
# --- [ HPPC Core: 无面者 (Daemon) ] ---
# 职责：静默监听学城信号

[ -f "/etc/hppc/hppc.conf" ] || exit 1
source /etc/hppc/hppc.conf

TICK_FILE="/etc/hppc/last_tick"
LOCK_FILE="/tmp/hppc_daemon.lock"

# 1. 屏息 (File Lock)
exec 9>"$LOCK_FILE"
if ! flock -n 9; then exit 1; fi

# 2. 截获密信 (Check Tick)
REMOTE_TICK=$(curl -skL --connect-timeout 10 "https://$CF_DOMAIN/tg-sync?token=$CF_TOKEN")
[ -z "$REMOTE_TICK" ] || [ "$REMOTE_TICK" = "Unauthorized" ] && exit 1

LAST_TICK=$(cat "$TICK_FILE" 2>/dev/null || echo "0")

# 3. 命运裁决 (Trigger Update)
if [ "$REMOTE_TICK" -gt "$LAST_TICK" ] 2>/dev/null; then
    echo "$REMOTE_TICK" > "$TICK_FILE"
    
    # 执行军需官与炼金术士
    /bin/sh /usr/share/hppc/core/fetch.sh >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        /bin/sh /usr/share/hppc/core/synthesize.sh >/dev/null 2>&1
    fi
fi
