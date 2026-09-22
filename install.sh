#!/usr/bin/env bash
# sops-vault-kit 一键安装：生成属于你自己的本地加密凭据库。
#
# 用法:
#   git clone https://github.com/skyzhao1223/sops-vault-kit && cd sops-vault-kit
#   ./install.sh                 # 默认装到 ~/Vault
#   VAULT_DIR=/path/to/vault ./install.sh
#
# 做的事：检查依赖 → 生成/复用 age 密钥 → 建库目录 → 写入模板（含你的公钥）
#         → 加密种子文件 → git init + 首次提交 → 软链 vault 到 ~/.local/bin
# 不做的事：不联网、不上传任何东西、不改 shell 配置文件（PATH 不含时只提示）。
set -euo pipefail

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
VAULT_DIR="${VAULT_DIR:-$HOME/Vault}"

say()  { printf '%s\n' "$*"; }
die()  { printf 'install: %s\n' "$*" >&2; exit 1; }
need() {
  command -v "$1" >/dev/null 2>&1 || die "缺少 $1。macOS: brew install $2 ；Linux: 用发行版包管理器或官方 release 安装。"
}

say "═══ sops-vault-kit 安装 ═══"

# ---- 1. 依赖 ----
need sops sops
need age age
need age-keygen age
need git git
need jq jq
need python3 python3
say "✓ 依赖齐全（sops $(sops --version 2>/dev/null | head -1 | awk '{print $2}') / age / git / jq / python3）"

# ---- 2. 目标目录 ----
if [ -e "$VAULT_DIR" ] && [ -n "$(ls -A "$VAULT_DIR" 2>/dev/null)" ]; then
  die "$VAULT_DIR 已存在且非空。换 VAULT_DIR 或先移走旧目录（绝不覆盖已有库）。"
fi

# ---- 3. age 密钥（平台默认位置，sops 免配置自动发现）----
case "$(uname -s)" in
  Darwin) KEY_FILE="$HOME/Library/Application Support/sops/age/keys.txt" ;;
  *)      KEY_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt" ;;
esac
if [ -f "$KEY_FILE" ]; then
  say "✓ 复用已有 age 密钥: $KEY_FILE"
else
  mkdir -p "$(dirname "$KEY_FILE")"
  chmod 700 "$(dirname "$KEY_FILE")"
  age-keygen -o "$KEY_FILE" >/dev/null 2>&1 || die "age-keygen 生成密钥失败"
  chmod 600 "$KEY_FILE"
  say "✓ 已生成新 age 密钥: ${KEY_FILE}（600 权限）"
fi
PUB="$(age-keygen -y "$KEY_FILE")" || die "无法从密钥文件导出公钥"

# ---- 4. 铺设库目录 ----
mkdir -p "$VAULT_DIR/bin"
cp "$KIT_DIR"/bin/vault "$KIT_DIR"/bin/vault-audit.py "$KIT_DIR"/bin/vault-shape.py \
   "$KIT_DIR"/bin/vault-render.py "$KIT_DIR"/bin/vault-import.py "$KIT_DIR"/bin/vault-view.html "$VAULT_DIR/bin/"
chmod +x "$VAULT_DIR/bin/vault" "$VAULT_DIR/bin/"*.py
sed "s|__AGE_PUBLIC_KEY__|$PUB|" "$KIT_DIR/templates/sops.yaml" > "$VAULT_DIR/.sops.yaml"
cp "$KIT_DIR/templates/secrets.yaml"  "$VAULT_DIR/secrets.yaml"
cp "$KIT_DIR/templates/systems.md"    "$VAULT_DIR/systems.md"
cp "$KIT_DIR/templates/gitignore"     "$VAULT_DIR/.gitignore"
cp "$KIT_DIR/templates/vault-README.md" "$VAULT_DIR/README.md"
cp "$KIT_DIR/templates/AGENTS.md"     "$VAULT_DIR/AGENTS.md"
say "✓ 库文件已铺设: $VAULT_DIR"

# ---- 5. 加密种子文件 ----
(cd "$VAULT_DIR" && sops encrypt -i secrets.yaml) || die "sops 加密失败（检查 .sops.yaml 与密钥）"
say "✓ secrets.yaml 已加密（白名单模式：除公开字段外全部加密）"

# ---- 6. git 初始化 ----
git init -q "$VAULT_DIR"
if [ -z "$(git -C "$VAULT_DIR" config user.email 2>/dev/null || true)" ] && [ -z "$(git config --global user.email 2>/dev/null || true)" ]; then
  git -C "$VAULT_DIR" config user.name  "sops-vault-kit"
  git -C "$VAULT_DIR" config user.email "kit@localhost"
fi
git -C "$VAULT_DIR" add -A
git -C "$VAULT_DIR" commit -q -m "vault: init by sops-vault-kit"
say "✓ git 仓库已初始化并完成首次提交"

# ---- 7. 命令入口 ----
mkdir -p "$HOME/.local/bin"
ln -sfn "$VAULT_DIR/bin/vault" "$HOME/.local/bin/vault"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) say "✓ vault 已链接到 ~/.local/bin（在 PATH 中）" ;;
  *) say "⚠ ~/.local/bin 不在 PATH，请把下面一行加进你的 shell 配置："
     echo "    export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# ---- 8. 自检 ----
say ""
"$VAULT_DIR/bin/vault" doctor || say "（doctor 有告警，见上）"

cat <<EOF

═══ 安装完成 ═══
库位置:   $VAULT_DIR
age 密钥: $KEY_FILE

接下来强烈建议：
  1. vault keycard   生成密钥离线备份卡，打印 2 份异地保存（密钥丢了库就打不开了！）
  2. vault backup    打一份加密 bundle 备份（默认进 iCloud Drive，可用参数指定目录）
  3. vault new "工作/第一个系统" --url https://... --username you

常用: vault ls / vault html（浏览器面板）/ vault audit / vault help
说明: $VAULT_DIR/README.md · 给 AI 的规程: $VAULT_DIR/AGENTS.md
配套 DSH 面板插件: https://github.com/skyzhao1223/dsh-plugin-sops-vault
EOF
