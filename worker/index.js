/**
 * HPPC v2.0 - 学城中枢 (The Citadel)
 * ------------------------------------------------
 * 世界观设定：
 * 1. 星盘 (Astrolabe): 维护全局时间线 (Tick)，指引凡间要塞。
 * 2. 渡鸦 (Raven): 接收来自领主 (TG) 的急信 (/update)。
 * 3. 补给线 (Valyrian Link): 连接铁金库 (Sub-Store) 与要塞。
 *
 * 对应本地配置：
 * - env.AUTH_TOKEN  <==> 本地 hppc.conf 中的 CF_TOKEN
 */

const validateToken = (url, env) => {
  const token = url.searchParams.get("token");
  return token === env.AUTH_TOKEN;
};

const signalManager = {
  // 观测星盘 (获取当前版本号)
  async getCurrent(env) {
    return await env.KV.get("GLOBAL_UPDATE_TICK") || "0";
  },

  // 点燃烽火 (手动触发更新)
  async manualUpdate(env) {
    const tick = Date.now().toString();
    await env.KV.put("GLOBAL_UPDATE_TICK", tick);
    return tick;
  },

  // 接收渡鸦 (TG 同步)
  async syncWithTG(env) {
    let currentKVTick = await this.getCurrent(env);
    try {
      const tgRes = await fetch(`https://api.telegram.org/bot${env.TG_TOKEN}/getUpdates?offset=-1`);
      const data = await tgRes.json();
      const lastMsg = data.result?.[0]?.message;

      // 鉴权：只有领主本人的渡鸦才会被受理
      if (lastMsg?.text === "/update" && lastMsg.from.id.toString() === env.TG_CHAT_ID) {
        const tgTick = lastMsg.date.toString();
        if (parseInt(tgTick) > parseInt(currentKVTick.substring(0, 10))) {
          await env.KV.put("GLOBAL_UPDATE_TICK", tgTick);
          return tgTick;
        }
      }
    } catch (e) {
      console.error("Citadel Raven Error:", e);
    }
    return currentKVTick;
  }
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // 1. 守夜人鉴权
    if (!validateToken(url, env)) {
      return new Response("The Citadel: You shall not pass. (Unauthorized)", { status: 401 });
    }

    // 2. 事务分发
    switch (url.pathname) {
      case "/update":
        const newTick = await signalManager.manualUpdate(env);
        return new Response(`🔥 [HPPC] 烽火已点燃！\nTick: ${newTick}\n\n无面者将在 1 分钟内响应。`);

      case "/tg-sync":
        const syncTick = await signalManager.syncWithTG(env);
        return new Response(syncTick);

      case "/fetch-nodes":
        try {
          const res = await fetch(env.SUB_STORE_API);
          if (!res.ok) throw new Error(`Supply Line Broken: ${res.status}`);
          const nodeData = await res.text();
          return new Response(nodeData, { 
            headers: { 
                "Content-Type": "application/json; charset=utf-8",
                "X-HPCC-Source": "IronBank"
            } 
          });
        } catch (e) {
          return new Response(`[Citadel Error] ${e.message}`, { status: 500 });
        }

      default:
        return new Response("🏰 The Citadel is Online.\nWinter is Coming.");
    }
  }
};
