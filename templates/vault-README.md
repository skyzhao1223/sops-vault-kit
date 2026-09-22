# Vault —— 本地加密凭据库

工作生活中所有系统链接和账号密码，集中放在这一个加密文件里。**免费、纯本地、命令行驱动**，人和 AI 用同一套命令管理。

## 为什么是这套

| 需求 | 这套方案怎么满足 |
|---|---|
| 免费 | `age` + `sops` + `git` 全部开源，无服务端、无订阅 |
| 本地 | 库就是 `secrets.yaml` 一个文件，躺在你自己的磁盘上 |
| 方便 AI 管理 | 加密的是**字段值**，不是整个文件：AI 不解密就能看到全部系统的名字、入口、负责人、备注，只在真正需要某个密码时才取那一个值 |
| 不泄露给 AI | 解密只依赖密钥文件（600 权限），**任何密码都不需要出现在命令行或对话里** |
| 可追溯 | git 管版本，谁改了哪一条、什么时候改的都能查、能回滚 |
| 能带走 | 库是标准 YAML，随时能导出成 CSV 给手机端密码管理器用 |

不选 KeePassXC 的原因是 `.kdbx` 是二进制格式，无法 diff、无法搜索，AI 只能一问一答地调 CLI，而且每次都要把主密码塞进命令行。不选 Bitwarden 的原因是凭据要放在别人的云上，且 CLI 同样需要主密码换取会话。

## 快速开始

```bash
vault ls                             # 列出所有系统（不解密任何密码）
vault new "工作/公司VPN" --url https://vpn.example.com --username zhangsan \
      --env prod --owner 运维-李四 --note "需先连办公网"
vault copy "工作/公司VPN"             # 密码进剪贴板，不打印到屏幕
vault totp "工作/公司VPN"             # 用存下的种子算动态验证码
vault save "新增公司VPN"              # 提交改动
vault doctor                         # 自检
```

不给 `--password` 时 `vault new` 会自动生成 24 位随机密码（**不打印**，用 `vault copy` 取）。

## 命令速查

**读取**

| 命令 | 作用 |
|---|---|
| `vault ls [关键词]` | 系统名 / 环境 / 负责人 / 入口地址，制表符分隔 |
| `vault peek` | 不解密、不需要密钥，直接从文件里列出系统名 |
| `vault show <系统>` | 整条记录（**含明文密码，谨慎**） |
| `vault get <系统> [字段]` | 取单个字段，默认 `password` |
| `vault copy <系统> [字段]` | 复制到剪贴板，不打印 |
| `vault search <关键词>` | 搜系统名/入口/用户名/备注，**不搜也不显示密码** |
| `vault find-secret <片段>` | 反查某个密码用在了哪些系统（只输出系统名） |
| `vault totp <系统>` | 当前动态验证码 + 剩余秒数 |

**明文查看**（残留面从小到大，按需选）

| 命令 | 残留面 | 适用场景 |
|---|---|---|
| `vault cat [系统]` | 只在标准输出，**不落盘** | 管道给 `grep`/`sed`，或 `vault cat \| less` |
| `vault view [系统]` | 在 `less` 里看，**退出后内容从屏幕清除** | 想在屏幕上扫一遍，又不想留回滚缓冲 |
| `vault html [文件]` | 会写一个 **600 权限的明文 HTML** 到 `/tmp` | 最方便：浏览器卡片视图，分组展示、全部字段可见、点击复制、动态码实时刷新 |
| `vault clean` | —— | 删除上面留下的明文临时文件 |

```bash
vault cat                          # 整个库的明文 YAML
vault cat "工作/公司VPN"             # 只解一条
vault cat | grep -c 'password:'    # 纯文本才能这么用
vault html                         # 生成并打开浏览器表格
vault clean                        # 看完务必执行
```

页面按 `工作 / 服务 / 生活` 分组展示卡片，**每条记录的全部字段都可见**（包括 appid、apiv3_key 这类自定义字段）。哪些值默认打码，由 `.sops.yaml` 的白名单**同源判定**——磁盘上加密的字段，页面上就打码，两边永不漂移。点 👁 展开单个字段，点值复制到剪贴板，右上角可全部展开。存了 TOTP 种子的条目直接显示**实时动态码**（浏览器内计算，30 秒轮换，种子不出页面）。默认打码是因为明文页面最大的风险是旁观和截图。

**代价要说清楚**：`cat` 和 `view` 的明文会进入终端回滚缓冲（`view` 用 less 会清除屏幕，好一些）；`html` 会在磁盘上留一个明文文件，直到 `vault clean`。所以日常取单个密码仍然优先 `vault copy`。

**写入**：`new` · `set` · `rm` · `edit`（用 `$EDITOR` 直接编辑）· `md`（重建 `systems.md` 的入口表）

`vault set` 的值写成 `-` 时从 stdin 读取——**推荐的密码入库方式**：

```bash
pbpaste | vault shape                        # ① 体检：只看形状（长度/构成/前缀/指纹），不看内容
pbpaste | vault set "服务/Stripe" appkey -   # ② 值从剪贴板直通加密库，
                                            #    不进命令行参数、shell 历史、进程列表
vault get "服务/Stripe" appkey | tr -d '\n' | vault shape
                                            # ③ 回环校验：指纹与 ① 一致才算写对
```

`vault shape` 会标记 多行/含空格/过短/首尾空白 等异常——专治"剪贴板里不知道是什么"。

**运维**：`save` · `log` · `remote <git地址>` · `push` / `pull` · `export [文件]` · `doctor` · `path`

**检查**：`audit`（查有没有明文漏网，不需要密钥）· `reencrypt`（改规则后重新加密整个库）

## 数据结构

```
systems:
  工作/公司VPN:          # 键名用「分组/系统名」，斜杠只是命名习惯
    url: https://...    # 明文
    username: zhangsan  # 明文
    password: ENC[...]  # 加密
    totp: ENC[...]      # 加密（base32 种子）
    token: ENC[...]     # 加密
    env: prod           # 明文
    owner: 运维-李四     # 明文
    note: 需先连办公网   # 明文
```

**加密策略是白名单（fail-closed）**：`.sops.yaml` 用 `unencrypted_regex` 列出"可以明文"的字段名，
**其余一切字段一律加密**——包括你以后新加的任何字段名。

这样设计是因为黑名单会静默漏网：早先的版本用 `encrypted_regex` 列举敏感词，
结果 `appkey`、`sign_key`、`map_key`、`sms_key` 这些**没被列举到的字段会以明文存下来，不报错也不提示**。
白名单把失败模式反了过来：新字段顶多被"多加密"，绝不会漏成明文。

当前白名单（42 个，都不是秘密）：`url` `endpoint` `restapi` `appid` `mch_id` `serial_no`
`username` `account` `bucket` `region` `env` `owner` `note` `sign_name`（短信签名名称，不是密钥）
`cert_path`（证书**路径**，不是证书内容）等，完整列表见 `.sops.yaml`。

改完 `.sops.yaml` 后必须执行 `vault reencrypt` 才生效——`sops updatekeys` 不会重新应用改过的规则。
改完跑一遍 `vault audit` 验证。

## 存服务凭据（AppID / AppKey / Secret）

这类记录没有"用户名密码"，而是一组自定义字段，用 `--field`：

```bash
vault new "服务/微信支付" --no-password --env prod --owner 我 \
  --note "商户平台；回调地址需在后台配置" \
  --field appid=wx8888888888888888 \
  --field mch_id=1900000109 \
  --field serial_no=4A3B2C1D... \
  --field apiv3_key=<从微信后台复制> \
  --field cert_path=/Users/me/certs/apiclient_cert.p12

vault new "服务/对象存储OSS" --no-password --env prod --owner 我 \
  --field access_key_id=<AK> --field access_key_secret=<SK> \
  --field bucket=my-prod-bucket --field region=cn-hongkong
```

- `--no-password` 不生成无意义的 password 字段
- `--field k=v` 想加多少加多少，**不用管哪些要加密**——白名单之外的字段自动加密
- `--gen 字段名` 让 vault 生成一个随机值填进去（比如自建的 webhook secret）

查回来：

```bash
vault ls                                   # 有哪些服务、什么环境、谁的
vault cat "服务/微信支付"                   # 看这条的全部字段
vault get "服务/微信支付" apiv3_key         # 只取一个
vault copy "服务/微信支付" apiv3_key        # 进剪贴板，不上屏
vault search 支付                           # 搜系统名/备注
vault find-secret <某个 AppSecret 片段>      # 反查这个密钥用在哪些服务
```

## 两个文件的分工

- `secrets.yaml` —— 凭据。加密，不放任何说明性文字。
- `systems.md` —— 入口清单。明文，写"有哪些系统、怎么进去、找谁、申请流程"。中间那段表格由 `vault md` 从库里的非敏感字段自动生成，别手改；上下两段随你写。

`vault md` 的意义是：**入口清单永远和凭据库同步**，不会出现"库里加了系统但清单忘了写"。

## 备份（重要）

**库丢了可以重建，密钥丢了就永久打不开。** 一条命令一件事：

### 1. 备份库 → `vault backup`

```bash
vault backup                        # 默认：iCloud Drive/VaultBackups，自动保留最近 5 份
vault backup /Volumes/极空间/备份     # 或任何目录（NAS 挂载、移动硬盘）
```

把整个库（含全部 git 历史）打包成单个 `.bundle` 文件。注意：bundle 里**敏感值全是密文**，但系统名、URL、备注这些按设计明文的元数据也在里面——放 iCloud 或你自己的 NAS 没问题，别放到你不信任的地方。

### 2. 备份密钥 → `vault keycard`

```bash
vault keycard        # 生成备份卡并在浏览器打开
```

**打印 2 份，存放在 2 个不同物理地点**，然后 `vault clean` 删掉磁盘上的卡片。卡片含明文私钥，像现金一样保管。这一步请亲手做，不要让任何 AI 代劳。

### 恢复（新电脑 / 灾难恢复）

```bash
brew install age sops                             # 1. 装工具
# 2. 按备份卡把私钥写回 ~/Library/Application Support/sops/age/keys.txt（chmod 600）
vault restore /路径/vault-XXXXXXXX-XXXXXX.bundle  # 3. 恢复，自动验证可解密
VAULT_DIR=~/Vault-restored-XXXX vault ls          # 4. 直接用，或 mv 成 ~/Vault
```

这三步也印在备份卡上。`vault restore` 恢复到的目录绝不覆盖现有库。

### 进阶：git 远端（可选）

偏好推私有仓库（GitHub 私有 / 极空间 Gitea / NAS 裸仓库）：

```bash
vault remote git@github.com:你的账号/vault.git
vault push
```

同样注意：值全密文，但元数据（系统名/URL/备注）明文可见，所以必须是**私有**仓库。

## 手机上怎么用（免费）

本方案没有官方手机 App，两条免费路子：

- **临时查**：`vault export` 出一个明文 CSV，用 AirDrop 发到手机，导入免费的 Bitwarden / 密码 App，用完删掉。
- **长期**：注册一个免费 Bitwarden 账号，把它当作手机的只读镜像；电脑上仍以 `vault` 为准，定期导出导入。

不建议把 CSV 留在 iCloud 或微信里 —— 那是明文。

## 安全须知

- 密钥文件权限必须是 `600`，`vault doctor` 会检查。
- `vault export` 出来的是**明文**，用完立刻删，永远不要提交到 git（`.gitignore` 已拦截常见后缀）。
- 用 AI 帮忙管理时，让它跑 `vault ls` / `vault get` 是可以的；**不要把密码内容粘进对话**，AI 能直接读本地命令输出，不需要你转述。
- `vault show` 会把明文密码打到终端，可能进入 shell 历史或终端日志。日常用 `vault copy`。
- 命令名 `vault` 与 HashiCorp Vault CLI 冲突。如果你以后要装后者，把 `~/.local/bin/vault` 这个软链改个名（比如 `kv`）。

## 位置

| 内容 | 路径 |
|---|---|
| 库 | `~/Vault/secrets.yaml` |
| 入口清单 | `~/Vault/systems.md` |
| 命令 | `~/Vault/bin/vault`（已软链到 `~/.local/bin/vault`） |
| age 密钥 | `~/Library/Application Support/sops/age/keys.txt` |
| sops 规则 | `~/Vault/.sops.yaml` |

`sops` 和 `age` 由 Homebrew 安装；`~/Vault` 本身是一个 git 仓库。
