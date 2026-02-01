#!/bin/sh
# --- [ HPPC Core: 无面者 (Daemon) v3.1 ] ---
# 职责：静默监听学城信号 (HTTP Header)，仅在变动时触发更新
# 修复：
# 1. 使用 curl -I (Head) 极速检测，不消耗流量
# 2. 修复了“先更新时间戳导致下载失败不重试”的 Bug

[ -f "/etc/hppc/hppc.conf" ] || exit 1
source /etc/hppc/hppc.conf
source /usr/share/hppc/lib/utils.sh

TICK_FILE="/etc/hppc/last_tick"
LOCK_FILE="/tmp/hppc_daemon.lock"

# 1. 屏息 (File Lock) - 避免并发
if [ -f "$LOCK_FILE" ]; then
    # 如果锁文件超过10分钟，强制删除 (防止死锁)
    if [ "$(find "$LOCK_FILE" -mmin +10)" ]; then
        rm -f "$LOCK_FILE"
    else
        exit 0
    fi
fi
touch "$LOCK_FILE"

# 2. 截获密信 (Check Signal)
# 使用 -I 参数，只看 HTTP 头，不下载内容
HEADERS=$(curl -skI --connect-timeout 8 "https://$CF_DOMAIN/sub?token=$CF_TOKEN")

if [ $? -eq 0 ]; then
    # 提取时间戳 (优先 Last-Modified，其次 ETag)
    REMOTE_TICK=$(echo "$HEADERS" | grep -i "Last-Modified:" | cut -d' ' -f2- | tr -d '\r')
    [ -z "$REMOTE_TICK" ] && REMOTE_TICK=$(echo "$HEADERS" | grep -i "ETag:" | cut -d' ' -f2- | tr -d '\r"')

    # 如果获取到了有效信号
    if [ -n "$REMOTE_TICK" ]; then
        LOCAL_TICK=$(cat "$TICK_FILE" 2>/dev/null)

        # 3. 命运裁决 (Trigger Update)
        # 使用字符串对比 (!=)，比数字对比 (-gt) 更兼容各种时间格式
        if [ "$REMOTE_TICK" != "$LOCAL_TICK" ]; then
            log_info "哨兵发现信号变更: [$LOCAL_TICK] -> [$REMOTE_TICK]"
            
            # [关键修复] 将新 Tick 传给 fetch
            # 只有当 fetch 成功返回 0 时，fetch 内部才会更新 TICK_FILE
            # 如果 fetch 失败，TICK_FILE 不变，下一分钟哨兵会再次尝试 (重试机制生效)
            if /bin/sh /usr/share/hppc/core/fetch.sh "$REMOTE_TICK"; then
                
                # 下载成功后，通知炼金术士生成配置
                # (Synthesize v2.6+ 仅生成配置并通知，不自动重启)
                /bin/sh /usr/share/hppc/core/synthesize.sh
            fi
        fi
    fi
fi

rm -f "$LOCK_FILE"
