# 给 AI 助手的操作说明

这个目录是一个 sops + age 加密的凭据库（由 sops-vault-kit 生成）。AI 助手处理凭据相关请求时按下面的规矩来。

## 基本事实

- 库文件：`~/Vault/secrets.yaml`（敏感字段的值是 `ENC[AES256_GCM,...]`，其余字段明文）
- 解密密钥：`~/Library/Application Support/sops/age/keys.txt`，sops 会自动读取，**不需要也不能要求用户提供密码**
- 统一入口：`vault`（在 PATH 里，源码是 `~/Vault/bin/vault`）。**不要手改 YAML**，用命令改。

## 允许做的

```bash
vault ls                     # 先看全貌，这一步不会解密任何密码
vault get "<系统>" <字段>     # 只在确实需要某个值时才取
vault search "<关键词>"       # 找系统；不显示密码
vault find-secret "<片段>"    # 反查密码归属
vault new "<系统>" --url ... --username ... --env ... --owner ... --note ...
vault set "<系统>" <字段> "<值>"
vault rm "<系统>" [字段]
vault md                     # 改完库后同步 systems.md 的入口表
vault save "<说明>"           # 收尾必须提交
vault doctor                 # 怀疑环境有问题时
vault clean                  # 用户要过明文视图时，用完清掉临时文件
vault audit                  # 改完规则、或怀疑有明文漏网时
vault reencrypt              # 改过 .sops.yaml 后必须跑，否则规则不生效
vault backup [目录]           # 打包备份（bundle 内敏感值均为密文，元数据明文）
vault restore <bundle> [目录] # 从备份恢复，绝不覆盖现有库
```

## 必须遵守

1. **绝不把密码内容写进回复、日志或任何文件**。需要展示时只报告字段是否存在、长度、是否为空。
2. **优先 `vault ls` / `vault search`，不要 `vault show`**。`show` 会把明文密码打进终端。
3. **`vault cat` / `vault view` / `vault html` 只在用户明确要求明文查看时才执行**，它们会输出或落盘明文。绝不要把这三个命令的输出原样贴进回复；需要核对时只报"字段存在 / 长度 / 是否为空"。用过 `vault html` 必须接着 `vault clean`。
4. 新建条目**不要自己指定密码**，让 `vault new` 自动生成；用户用 `vault copy` 取。
5. 每次改完库，跑 `vault md` 再跑 `vault save "说明"`，保证入口清单同步且有版本记录。
6. 不要执行 `vault export`（会生成明文文件），除非用户明确要求，并在用完后删除。
7. 不要修改 `.sops.yaml` 里的 age 公钥；也不要复制、打印或移动 age 私钥。
8. 加密策略是**白名单**：`.sops.yaml` 的 `unencrypted_regex` 列出可以明文的字段，其余一律加密。
   **新增自定义字段不需要你做任何事**，会自动加密；不要去改白名单把敏感字段放行。
9. 改过 `.sops.yaml` 必须跑 `vault reencrypt`（`sops updatekeys` 不生效），然后 `vault audit` 验证。
10. 系统名是用户自定的层级命名（如 `工作/公司VPN`），必须原样引用，包括斜杠和中文。
11. **剪贴板入库协议**（用户说“把剪贴板里的值存到 X 字段”时，四步走）：
    a. **先体检不入库**：`pbpaste | vault shape`——只回报形状（长度/行数/字符构成/已知前缀/sha256 指纹），绝不打印内容；
    b. **形状异常先问**：多行 / 含空格 / <8 字符 / 首尾空白 / 指纹与字段现值相同（重复写入）→ 报告异常并等用户确认，不自动写；
    c. **确认后写入**：`pbpaste | vault set "<系统>" "<字段> -`；
    d. **回环校验**：`vault get "<系统>" "<字段>" | tr -d '\n' | vault shape` 的 sha256 指纹与写入前一致，才报告“已写入并校验”。
    全程值不出现在回复、命令参数、进程列表、日志里。多行值（PEM 私钥等）不走剪贴板协议，引导用面板 ✏️ 编辑或 `vault edit`。
12. **若用户选择在对话里直接给值（默认应优先引导 stdin/面板通道）**，必须遵守对话通道卫生：
    - 值只允许出现在**一次**工具调用里（`vault set`/`vault new --field`），立即入库；
    - 绝不在回复、确认、后续任何命令中复述值——只报字段名、长度、sha256 指纹（`vault get "<系统>" <字段> | tr -d '\n' | vault shape` 取指纹，值走管道不外显）；
    - 多个字段合并成尽量少的工具调用；
    - 存完高敏值后提醒一句：本会话上下文的每次续聊都会重发该值，建议之后开新会话；
    - 若当前模型路由是第三方网关/云端且用户似乎没意识到，第一次处理值前提示一次路由事实，之后不再提。
13. **绝不代用户运行 `vault keycard`**，也不读取、打印、复制、移动 age 私钥；密钥离线备份卡必须由用户本人生成并打印。`vault backup` / `vault restore` 可以正常运行。

## 交付给用户时的口径

告诉用户做了什么、涉及哪个系统名、字段是否已设置。**不要复述密码**。
