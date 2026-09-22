# 迁移指南 / Migration Guide

从现有密码管理器搬进 sops-vault-kit。核心命令是 `vault import`（自动识别格式、
已存在条目跳过、密钥值走 stdin 不进命令参数）。

Migrate into sops-vault-kit from an existing password manager. The core command
is `vault import` (auto format detection, existing entries skipped, secrets
piped via stdin — never in process arguments).

---

## Bitwarden

1. 网页版 vault.bitwarden.com → 工具 → 导出保管库 → **CSV**（需主密码确认）
   Web vault → Tools → Export vault → **CSV** (master password required)
2. ```sh
   vault import ~/Downloads/bitwarden-export.csv
   ```
   - `folders` 列会成为条目前缀分组（`工作/xxx`）；无文件夹的进根目录
   - `login_totp` 若是 `otpauth://` URI，自动提取 seed，导入后 `vault totp` 直接出码
   - 自定义字段（Bitwarden CSV 的 `fields` 列）暂不导入——用 `vault set` 补
   - folders become entry-name prefixes; `otpauth://` TOTP seeds are extracted
     automatically; custom `fields` column is not imported yet — add via `vault set`

## 1Password

1. 桌面 App → 文件 → 导出 → **CSV**（1Password 8：选中保险库导出）
   Desktop app → File → Export → **CSV**
2. ```sh
   vault import ~/Downloads/1password-export.csv
   ```
   - `Title` 列作为条目名；建议导出前把重要条目改名成 `分组/名称` 形式，导入后自动分组
   - `Title` becomes the entry name; rename important items to `group/name`
     before exporting to get grouping

## Chrome / Edge / Brave（浏览器密码）

1. `chrome://password-manager/passwords` → 设置 → 导出密码（macOS 会要求 Touch ID）
   → Settings → Export passwords
2. ```sh
   vault import ~/Downloads/Chrome\ Passwords.csv
   ```

## 本库自己的 export（round-trip）

`vault export dump.csv` 产出的格式可直接 `vault import dump.csv` 导回——用于库迁移到新机器。

The kit's own `vault export` CSV round-trips through `vault import` — handy for
moving a vault to a new machine (though `vault backup` + `vault restore` is the
better path: it keeps git history).

## 导入后必做 / After importing

```sh
vault ls                 # 核对条目数 / verify the count
vault audit              # 白名单体检：确认所有密钥字段都被加密 / allowlist check
vault md && vault save "import from <manager>"
vault backup             # 立刻打一份备份 / take a backup right away
```

**然后立刻销毁明文 CSV / then destroy the plaintext CSV immediately:**

```sh
rm -P ~/Downloads/bitwarden-export.csv     # macOS：覆写后删除 / overwrite + unlink
shred -u ~/Downloads/bitwarden-export.csv  # Linux
```

CSV 在的每一天，你的全部密码都以明文躺在磁盘上（还会进 Time Machine / 回收站索引）。

Every day the CSV exists, all your passwords sit in plaintext on disk (and leak
into Time Machine / trash indexes).

## 不导入的东西 / What does NOT migrate

- **浏览器自动填充**：本库不是浏览器密码管理器。需要自动填充的登录类条目，
  建议留在系统钥匙串/Bitwarden，本库专注开发者凭据（AppKey/Token/证书/服务器）
  Browser autofill does not come along: keep pure website logins in your
  system keychain/Bitwarden if autofill matters; this vault targets developer
  credentials (API keys, tokens, certs, server access).
- **附件/文件**（1Password 的文档附件等）：手动放到磁盘并用 `vault set X cert_path /path`
  记录路径 Attachments: store files on disk and record the path in a field.
- **密码历史**：git 从导入那一刻开始记录历史 / Password history: git starts
  at import time.
