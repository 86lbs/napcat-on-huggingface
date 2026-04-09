# 🐱 NapCat on Hugging Face

在 Hugging Face Spaces 上免费部署 NapCat QQ 机器人框架。

---

## ✨ 特性

- 🆓 **完全免费** — 基于 HF Spaces 免费 CPU 实例
- 💾 **数据持久化** — 登录态自动备份到 HF Dataset，重启不丢失
- 🔄 **自动保活** — 支持 GitHub Actions 定时 ping，防止 Space 休眠
- 📦 **分离备份** — NapCat 配置、QQ 配置、插件分开备份，恢复更可靠
- 🌐 **端口转发** — nginx 将内部端口转发至外部可访问地址

---

## ⚠️ 使用前须知

- HF Spaces 服务器位于**美国**，QQ 登录存在异地风控风险
- 首次登录需扫码，后续重启通过备份恢复 session
- 仅适合个人学习/测试使用，生产环境建议使用国内服务器

---

## 📋 准备工作

1. [Hugging Face](https://huggingface.co) 账号
2. QQ 号码
3. GitHub 账号（可选，用于保活）

---

## 🚀 部署步骤

### 第一步：创建备份 Dataset

1. HF 主页右上角头像 → **New Dataset**
2. 填写名称（如 `napcat-backup`），可见性选 **Private**
3. 点击 **Create**
4. 记录仓库名：`你的用户名/napcat-backup`

### 第二步：获取 HF Token

1. HF 设置页 → **Access Tokens** → **New token**
2. 权限选 **Write**
3. 复制并保存 Token

### 第三步：创建 Space

1. HF 主页 → **New Space**
2. SDK 选 **Docker**
3. 可见性选 **Public** 或 **Private**
4. 点击 **Create**

### 第四步：上传文件

将以下文件上传到你的 Space：

```
Dockerfile
entrypoint.sh
nginx.conf
```

### 第五步：配置环境变量

在 Space 的 **Settings → Variables and secrets** 中添加：

| 变量名 | 类型 | 说明 |
|--------|------|------|
| `HF_TOKEN` | **Secret** | 第二步获取的 HF Token |
| `DATASET_REPO` | **Secret** | 备份仓库名，如 `yourname/napcat-backup` |
| `ACCOUNT` | **Secret** | QQ 号码 |
| `NAPCAT_WEBUI_SECRET_KEY` | **Secret** | WebUI 登录密码（自定义） |
| `NAPCAT_QUICK_PASSWORD` | **Secret** | NapCat 快速登录密码（可与 WebUI 密码相同） |

> ⚠️ 所有含敏感信息的变量务必设为 **Secret**

**可选变量（高级）：**

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `NAPCAT_DISABLE_MULTI_PROCESS` | Variable | — | 设为 `1` 可禁用多进程，HF 环境建议开启 |
| `NAPCAT_ENABLE_VERBOSE_LOG` | Variable | — | 设为 `1` 开启详细日志，排查问题时使用 |
| `NAPCAT_SESSION_PROXY` | Variable | — | 设为 `1` 启用会话代理 |

### 第六步：首次登录

1. Space 启动后点击 **App** 标签打开 WebUI
2. 地址：`https://你的用户名-你的space名.hf.space`
3. 使用 `NAPCAT_WEBUI_SECRET_KEY` 设置的密码登录
4. 在 WebUI 中扫码登录 QQ

---

## 🌐 连接地址

| 用途 | 地址 |
|------|------|
| WebUI | `https://用户名-space名.hf.space` |
| 正向 WebSocket | `ws://用户名-space名.hf.space/3001/` |
| HTTP 上报 | `http://用户名-space名.hf.space/5700/` |
| 调试 WebSocket | `ws://用户名-space名.hf.space/api/Debug/ws/` |

> **调试 WebSocket 说明**
>
> 连接调试 WebSocket 需要附带临时 token：
> ```
> ws://用户名-space名.hf.space/api/Debug/ws?token=xxxxxx
> ```
> **容器已内置保活进程**，会在启动后自动获取 token 并维持连接，通常无需手动操作。
>
> 如需手动连接（如使用外部调试工具），请在 WebUI 中访问 **实时调试**（`/webui/debug/ws`），页面会自动生成 token 并显示完整连接地址。

---

## 🔄 配置保活

HF 免费 Space 超过 **48 小时无访问**会自动休眠。

### 使用 GitHub Actions 保活

1. 在你的 GitHub 仓库创建 `.github/workflows/keepalive.yml`
2. 填入以下内容（替换 Space URL）：

```yaml
name: Keep NapCat Alive

on:
  schedule:
    - cron: "0 */12 * * *"  # 每 12 小时执行一次
  workflow_dispatch:

jobs:
  ping:
    runs-on: ubuntu-latest
    steps:
      - name: Ping HF Space
        run: |
          STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://你的用户名-你的space名.hf.space)
          echo "HTTP Status: $STATUS"
```

---

## 💾 备份说明

每次重启时自动从 HF Dataset 恢复，运行期间每 **30 分钟**自动备份一次。

| 文件 | 内容 |
|------|------|
| `napcat.zip` | NapCat 配置文件 |
| `qq.zip` | QQ 登录态、设备信息（已排除缓存） |
| `plugins.zip` | NapCat 插件数据 |

---

## ❓ 常见问题

**Q: 每次重启都需要重新扫码吗？**  
A: 不需要。只要 QQ 没有踢掉设备，备份恢复后可直接复用 session。

**Q: HF Space 会收费吗？**  
A: 免费 CPU 实例完全免费，只有升级到 GPU 或付费 Persistent Storage 才会产生费用。本方案均不使用付费功能。

**Q: 连接不稳定怎么办？**  
A: 优先使用正向 WebSocket（`/3001/`），无法连接时可改用调试端口（`/api/Debug/ws/`）。

**Q: QQ 登录被风控怎么办？**  
A: HF 服务器 IP 在美国，QQ 可能触发异地登录保护。建议使用小号，或换用国内服务器部署。

---

## 📄 License

MIT
