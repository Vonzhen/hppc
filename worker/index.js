/**
 * HPPC v2.0 - 云端指挥中心 (Cloud Command Center)
 * ------------------------------------------------
 * 职责：
 * 1. 信号塔：维护全局 Update Tick，供本地哨兵 (Watchdog) 轮询。
 * 2. 联络官：接收 Telegram 指令 (/update) 或网页指令并更新信号。
 * 3. 补给线：作为 Sub-Store 与 路由器 之间的安全中转站。
 *
 * 对应本地配置：
 * - env.AUTH_TOKEN  <==> 本地 hppc.conf 中的 CF_TOKEN
 */

const validateToken = (url, env) => {
  const token = url.searchParams.get("token");
  return token === env.AUTH_TOKEN;
};

const signalManager = {
  // 获取当前云端版本号 (Tick)
  async getCurrent(env) {
    return await env.KV.get("GLOBAL_UPDATE_TICK") || "0";
  },

  // 手动更新信号（通过访问 /update 触发）
  async manualUpdate(env) {
    const tick = Date.now().toString();
    await env.KV.put("GLOBAL_UPDATE_TICK", tick);
    return tick;
  },

  // 从 TG 消息同步信号 (核心逻辑：只响应特定 ID 的 /update 指令)
  async syncWithTG(env) {
    let currentKVTick = await this.getCurrent(env);
    try {
      // 轮询 TG Bot 更新
      const tgRes = await fetch(`https://api.telegram.org/bot${env.TG_TOKEN}/getUpdates?offset=-1`);
      const data = await tgRes.json();
      const lastMsg = data.result?.[0]?.message;

      // 鉴权：只有指定的 Chat ID 发送的 /update 才有效
      if (lastMsg?.text === "/update" && lastMsg.from.id.toString() === env.TG_CHAT_ID) {
        const tgTick = lastMsg.date.toString();
        // 如果 TG 消息时间戳比 KV 里的新，则更新 KV
        if (parseInt(tgTick) > parseInt(currentKVTick.substring(0, 10))) {
          await env.KV.put("GLOBAL_UPDATE_TICK", tgTick);
          return tgTick;
        }
      }
    } catch (e) {
      console.error("HPCC TG Sync Error:", e);
    }
    return currentKVTick;
  }
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // 1. 严格鉴权 (拒绝一切没有正确 Token 的请求)
    if (!validateToken(url, env)) {
      return new Response("HPCC Command Center: Unauthorized Access", { status: 401 });
    }

    // 2. 路由分发
    switch (url.pathname) {
      // [指令] 手动触发更新 (通常用于快捷指令或浏览器访问)
      case "/update":
        const newTick = await signalManager.manualUpdate(env);
        return new Response(`🚀 [HPCC] 信号已发射！\nTick: ${newTick}\n\n哨兵将在 1 分钟内捕获此信号。`);

      // [哨兵] 本地 Watchdog 轮询接口
      case "/tg-sync":
        const syncTick = await signalManager.syncWithTG(env);
        return new Response(syncTick);

      // [搬运] 拉取节点数据 (中转 Sub-Store)
      case "/fetch-nodes":
        try {
          const res = await fetch(env.SUB_STORE_API);
          if (!res.ok) throw new Error(`Sub-Store Unreachable: ${res.status}`);
          const nodeData = await res.text();
          return new Response(nodeData, { 
            headers: { 
                "Content-Type": "application/json; charset=utf-8",
                "X-HPCC-Source": "Sub-Store"
            } 
          });
        } catch (e) {
          return new Response(`[HPCC Proxy Error] ${e.message}`, { status: 500 });
        }

      default:
        return new Response("🏢 HPCC Cloud Module is Active.\nSystem Status: Online");
    }
  }
};
