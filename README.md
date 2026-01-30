
---

# 🏰 HPPC: Castellan (要塞代官)

> **HomeProxy Profile Controller - 自动化配置与规则管理系统**

HPPC Castellan 是专为 OpenWrt 上的 **HomeProxy** 插件设计的全自动化指挥系统。它就像一位忠诚的“城堡代官”，为您打理节点订阅、配置熔炼、规则集更新以及系统健康监测，让复杂的网络配置变得如臂使指。

---

## ✨ 核心功能 (Features)

* **⚔️ 自动化配置熔炼 (Auto Synthesis)**：自动拉取节点，根据预设模板（hp_base.uci）智能生成 HomeProxy 配置，支持节点分层随机注入。
* **📚 智能规则管理 (Assets Manager)**：
* **双源策略**：优先从您的**私有 GitHub 仓库**下载规则，缺失时自动回退到公共源（MetaCubeX）。
* **级联寻址**：自动适配 Standard 和 Lite 目录结构，确保存活率。
* **按需补给**：生成配置前自动检查依赖，缺什么下什么，杜绝启动失败。


* **🩺 要塞诊断 (Doctor)**：一键检查网络连通性、依赖完整性（curl, jq, openssl）及配置状态。
* **🌐 WebUI 集成**：支持将核心命令注册到 OpenWrt LuCI 界面，手机也能轻松管理。
* **🦅 战报系统**：规则更新后自动发送 Telegram 统计报告。

---

## 🚀 安装 (Installation)

请通过 SSH 登录您的 OpenWrt 路由器，执行以下一键安装指令：

```bash
# 请将 'master' 替换为您的实际分支名
wget -qO /tmp/install.sh https://raw.githubusercontent.com/Vonzhen/hppc/master/install.sh && sh /tmp/install.sh

```

**安装过程交互：**

1. **环境预检**：脚本会自动补全缺失的系统依赖（curl, jq 等）。
2. **私有源配置**：如果您有自建的规则集仓库，请在安装时按提示输入地址。

---

## 📖 使用指南 (Usage)

安装完成后，在终端输入 `hppc` 即可唤出指挥面板：

```text
root@OpenWrt:~# hppc

```

### 🎮 菜单功能说明

1. **⚔️ 集结军队 (Muster)**
* 强制从 Worker 拉取最新节点，结合本地模板重写配置，并重启 HomeProxy。


2. **📚 修缮典籍 (Assets)**
* 更新所有当前配置中使用的 GeoIP/Geosite 规则集。支持私有源优先策略。


3. **📥 征收物资 (Download)**
* 手动下载指定的规则集（如 `geosite-openai`），无需等待自动更新。


4. **🛡️ 死守城池 (Rollback)**
* 配置出错？一键回滚到上一次正常的配置版本。


5. **🩺 要塞诊断 (Doctor)**
* 系统体检，快速排查无法更新或启动的原因。


6. **🌐 部署 WebUI**
* 将 HPPC 命令注册到 LuCI 网页后台（系统 -> 自定义命令），方便移动端操作。



### ⚙️ 高级配置

配置文件位于 `/etc/hppc/hppc.conf`，您可以修改：

* `ASSETS_PRIVATE_REPO`: 您的私有规则集 GitHub Raw 地址。
* `TG_BOT_TOKEN` / `TG_CHAT_ID`: 配置 Telegram 通知的密钥。

---

## ❤️ 致谢 (Credits)

本项目的诞生离不开开源社区巨人们的肩膀，特此向以下项目致以最崇高的敬意：

* **[immortalwrt/homeproxy](https://github.com/immortalwrt/homeproxy)**: 本项目的基石，优秀的 OpenWrt 代理插件。
* **[SagerNet/sing-box](https://github.com/SagerNet/sing-box)**: 强大的通用代理平台，HomeProxy 的核心引擎。
* **[MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat/tree/sing)**: 高质量、维护及时的规则集数据源（Sing 分支）。

---

## 🤖 关于作者 (Author's Note)

**Special Note:**

本项目是一个**完全由人类创意与人工智能协作**的产物。

作为所谓的“作者”，我（**Vonzhen**）其实**并不懂代码**。HPPC 的每一行 Bash 脚本、每一个逻辑判断、每一次架构重构，皆是由 **AI (Google Gemini)** 在我的设想与需求描述下编写完成的。

这是一次跨越认知鸿沟的尝试。如果你觉得这个项目好用，请感谢 AI 的强大；如果你发现了 Bug，那是我的提示词还不够精准。

*Powered by Human Imagination & AI Code Generation.*

---

**License:** MIT
