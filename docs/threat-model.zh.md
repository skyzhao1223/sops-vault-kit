# 威胁模型（Threat Model）

诚实的安全边界说明。**知道防不住什么，和知道防住什么同样重要。**

## 资产

| 资产 | 位置 | 静态保护 |
|---|---|---|
| 密钥值（密码/AppKey/Token/TOTP 种子） | `secrets.yaml` 内 `ENC[AES256_GCM,...]` | sops/age，白名单模式（未知字段默认加密） |
| age 私钥 | 平台默认路径（macOS `~/Library/Application Support/sops/age/keys.txt`，Linux `${XDG_CONFIG_HOME:-~/.config}/sops/age/keys.txt`） | 文件权限 600 |
| 元数据（系统名/URL/账号名/备注） | `secrets.yaml` 明文字段 + git 历史 + 备份 bundle | **无**（按设计公开给库的读者） |

## 攻击面与对策

### 防住的

| 威胁 | 对策 |
|---|---|
| 库文件/备份被拿走 | 值全密文（AES-256-GCM，每值独立 IV）；bundle 可放任何网盘 |
| 云服务商读到密钥值 | 同上；密钥永不离开本机 |
| **新字段忘了加密**（黑名单方案的经典死法） | 白名单 fail-closed：`unencrypted_regex` 之外的字段一律加密 |
| 规则漂移（改了 .sops.yaml 没重加密） | `vault audit` 直接解析密文文件核对白名单，`vault doctor` 提示 |
| 误提交明文到 git | `.gitignore` 拦截 export/视图/CSV；`vault audit` 可扫；git 历史里的值均为密文 |
| 恶意网页驱动本地 API（配套 DSH 插件时） | 插件 API 有 Origin 校验，跨源一律 403 |
| AI 助手读到全部明文 | 结构/值分离：`meta`/`ls` 免解密；取值走单字段 `get`；随库 `AGENTS.md` 约束行为 |
| 密码进入 shell 历史/进程列表 | `vault set … -`（stdin）、`pbpaste |` 管道、`vault copy` 不回显 |
| 备份后库损坏/误删 | git 逐提交回滚 + `vault restore`（校验可解密、绝不覆盖现库） |

### 防不住的（如实列出）

| 威胁 | 说明 | 缓解 |
|---|---|---|
| **同用户的本地恶意进程** | 能以你的身份运行的代码可直接读库+私钥，也能 `pbpaste` | 这是所有本地密码存储的共同边界；靠 macOS FileVault / Linux LUKS + 不装来历不明软件 |
| **age 私钥丢失** | 库永久不可解，无后门 | `vault keycard` 打印 2 份异地保存（装 qrencode 附二维码防手抄错） |
| **age 私钥泄露** | 持有者+任一备份 = 全部明文 | 卡当现金保管；泄露后换钥 + `vault reencrypt` + 轮换全部密钥值 |
| 明文查看时刻的肩窥/截屏/录屏 | `vault html`/`cat`/面板显示后，明文在屏幕与内存里 | 默认打码、按需单字段展开、`vault clean` 销毁落盘视图；投屏前关面板 |
| 浏览器扩展（用 `vault html` 时） | 有页面权限的扩展可读已显示的 DOM | 少装扩展；敏感操作用终端 `vault copy`（不上屏） |
| git 历史保留已删值 | `vault rm` 后旧提交仍可解出旧值（需要私钥） | 视为已暴露的密钥请轮换；这是"可回滚"的代价 |
| AI 对话通道 | 你主动把值打进对话，值会进会话日志/模型上下文 | 用剪贴板协议（`pbpaste | vault set … -`）或面板粘贴；见 AGENTS.md 第 11/12 条 |
|  coerced（胁迫） | 任何本地方案都防不了"人在场被迫解锁" | 超出软件边界 |

## 设计取舍备忘

- **为什么白名单而不是黑名单**：黑名单漏一个字段名 = 静默明文；白名单漏一个 = 多加密一个字段。失败模式不对称，选失败安全的一侧。
- **为什么元数据保持明文**：结构可读是"AI 可管理"与"grep 可检索"的前提；如果你的威胁模型里连系统清单都敏感，把 `unencrypted_regex` 收窄到 `^(url)$` 甚至空集，然后 `vault reencrypt`。
- **为什么不做主密码**：age 私钥文件就是主密钥，600 权限 + 永不进对话/命令行；主密码方案要么把密码交给脚本（更糟），要么每次交互输入（AI 不可用）。
- **为什么 git 而不是网盘同步**：可 diff、可回滚单条、冲突可解；`.kdbx`/网盘同步三者都做不到。
