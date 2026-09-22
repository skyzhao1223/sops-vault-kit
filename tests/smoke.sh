#!/usr/bin/env bash
# sops-vault-kit 冒烟测试：在一次性隔离 HOME 里跑完整生命周期。
# 覆盖：install → new → stdin set → shape 回环 → meta/audit → find-secret →
#       totp → md → save → backup → restore → import(CSV) → html/clean → doctor
# 用法：bash tests/smoke.sh          （macOS 与 Linux 通用，CI 双平台跑）
set -uo pipefail

KIT="$(cd "$(dirname "$0")/.." && pwd)"
FAKE="$(mktemp -d "${TMPDIR:-/tmp}/vault-smoke.XXXXXX")"
export HOME="$FAKE"
# 故意让 XDG_CONFIG_HOME 偏离 $HOME/.config，回归覆盖 runner 上的真实事故
export XDG_CONFIG_HOME="$FAKE/xdg-config"
PASS=0; FAIL=0
printf 'env: %s | bash %s | sops %s\n' "$(uname -srm)" "$BASH_VERSION" "$(sops --version 2>/dev/null | head -1 | awk '{print $2}')"

cleanup() { rm -rf "$FAKE"; }
trap cleanup EXIT

ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %s\n     %s\n' "$1" "${2:-}"; }
check() { # check <描述> <期望子串> <实际输出>
  case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "期望含 [$2]，实际: $(printf '%s' "$3" | head -2 | tr '\n' ' ')" ;; esac
}

# ── 1. 安装 ──────────────────────────────────────────────
if (cd "$KIT" && ./install.sh) > "$FAKE/install.log" 2>&1; then
  ok "install.sh 全流程"
else
  bad "install.sh 全流程" "$(tail -5 "$FAKE/install.log")"
  echo "安装失败，终止"; exit 1
fi
V="$FAKE/Vault/bin/vault"

# ── 2. 版本与空库 ────────────────────────────────────────
check "version"        "vault 0.4.0" "$("$V" version 2>&1)"
[ -z "$("$V" ls)" ] && ok "空库 ls 为空" || bad "空库 ls 为空" "$("$V" ls)"

# ── 3. 建条目 + stdin 写值 + shape 回环 ──────────────────
NEW_OUT=$("$V" new "服务/Stripe" --url "https://dashboard.stripe.com" --username "ops@corp" --note "生产" 2>&1) \
  && ok "new（自动生成密码）" || bad "new" "$NEW_OUT"
LEN=$("$V" get "服务/Stripe" password | tr -d '\n' | wc -c | tr -d ' ')
[ "$LEN" = "24" ] && ok "自动生成密码 24 位" || bad "自动生成密码 24 位" "实际 $LEN"

SECRET='sk_test_SMOKE_FAKE_1234567890abcdef'
SET_OUT=$(printf '%s' "$SECRET" | "$V" set "服务/Stripe" appkey - 2>&1) && ok "set 走 stdin" || bad "set stdin" "$SET_OUT"
A=$(printf '%s' "$SECRET" | "$V" shape | grep -o 'sha256:[a-f0-9]*')
B=$("$V" get "服务/Stripe" appkey | tr -d '\n' | "$V" shape | grep -o 'sha256:[a-f0-9]*')
[ -n "$A" ] && [ "$A" = "$B" ] && ok "shape 指纹回环一致" || bad "shape 回环" "$A vs $B"
check "shape 异常检测" "含空格" "$(printf 'appkey: xxx yyy' | "$V" shape)"

# ── 4. 结构类命令 ────────────────────────────────────────
check "meta 加密标记"   '"enc":true'   "$("$V" meta | jq -c '.["服务/Stripe"].appkey')"
check "meta 明文元数据" 'dashboard.stripe.com' "$("$V" meta)"
"$V" audit >/dev/null 2>&1 && ok "audit 通过（exit 0）" || bad "audit" ""
check "find-secret 反查" "服务/Stripe" "$("$V" find-secret 'SMOKE_FAKE')"
check "search"           "服务/Stripe" "$("$V" search 'stripe')"
check "peek 免密钥"       "服务/Stripe" "$("$V" peek)"

# ── 5. TOTP（公开测试种子）───────────────────────────────
"$V" set "服务/Stripe" totp "JBSWY3DPEHPK3PXP" >/dev/null 2>&1
TOTP_OUT="$("$V" totp "服务/Stripe" 2>&1)"
echo "$TOTP_OUT" | grep -qE '^[0-9]{6}' && ok "totp 输出 6 位码" || bad "totp" "$TOTP_OUT"

# ── 6. md / save / log ───────────────────────────────────
"$V" md >/dev/null 2>&1
check "md 生成入口表" "服务/Stripe" "$(cat "$FAKE/Vault/systems.md")"
"$V" save "smoke" >/dev/null 2>&1 && ok "save 提交" || bad "save" ""
check "log 有提交" "smoke" "$("$V" log 2>&1)"

# ── 7. backup / restore ──────────────────────────────────
"$V" backup "$FAKE/bk" >/dev/null 2>&1
BUNDLE=$(ls "$FAKE"/bk/vault-*.bundle 2>/dev/null | head -1)
[ -n "$BUNDLE" ] && ok "backup 生成 bundle" || bad "backup" ""
if [ -n "$BUNDLE" ]; then
  R_OUT=$(cd / && "$V" restore "$BUNDLE" "$FAKE/rs" 2>&1 | head -1)
  check "restore（库外运行）" "1 条记录" "$R_OUT"
fi

# ── 8. import（chrome 格式 CSV，含带逗号引号的字段）──────
cat > "$FAKE/imp.csv" <<'CSV'
name,url,username,password
工作/GitLab,https://git.corp.com,alice,"P@ss,w0rd!quoted"
生活/电商,https://shop.example.com,bob@example.com,hunter2hunter2
CSV
IMP_OUT=$("$V" import "$FAKE/imp.csv" 2>&1)
check "import 计数" "导入 2 条" "$IMP_OUT"
check "import 引号逗号字段" "P@ss,w0rd!quoted" "$("$V" get "工作/GitLab" password)"
IMP2=$("$V" import "$FAKE/imp.csv" 2>&1)
check "import 幂等（跳过已存在）" "跳过 2 条" "$IMP2"

# ── 8b. kdbx 导出（KeePassXML 结构可解析、含 TOTP）──────
"$V" kdbx "$FAKE/exp.xml" >/dev/null 2>&1 && ok "kdbx 导出" || bad "kdbx 导出" ""
if [ -f "$FAKE/exp.xml" ]; then
  KX=$(python3 -c "
import xml.etree.ElementTree as ET
t = ET.parse('$FAKE/exp.xml')
es = list(t.getroot().iter('Entry'))
otp = any(s.text == 'otp' for s in t.getroot().iter('Key'))
print(f'{len(es)} {int(otp)}')")
  set -- $KX
  [ "${1:-0}" -ge 2 ] && ok "kdbx 条目数 (${1})" || bad "kdbx 条目数" "${1:-0}"
  [ "${2:-0}" = "1" ] && ok "kdbx 含 TOTP otpauth" || bad "kdbx TOTP" ""
fi

# ── 8c. rename（值随行搬移，目标冲突拒绝）───────────────
(cd / && "$V" rename "服务/Stripe" "服务/Stripe2") >/dev/null 2>&1   # 故意在库外运行：回归 cwd 敏感
[ "$("$V" get "服务/Stripe2" appkey 2>/dev/null)" = "$SECRET" ] && ok "rename 值完整搬移" || bad "rename 值搬移" ""
"$V" peek | grep -Fxq "服务/Stripe" && bad "rename 旧名残留" || ok "rename 旧名已除"
REN_OUT=$("$V" rename "服务/Stripe2" "工作/GitLab" 2>&1) && bad "rename 应拒绝冲突" || check "rename 冲突拒绝" "已存在" "$REN_OUT"
"$V" rename "服务/Stripe2" "服务/Stripe" >/dev/null 2>&1 && ok "rename 改回" || bad "rename 改回" ""

# ── 9. html / clean ──────────────────────────────────────
HTML_OUT="$("$V" html "$FAKE/view.html" 2>&1)"
[ -f "$FAKE/view.html" ] && ok "html 生成视图" || bad "html" "$HTML_OUT"
case "$(uname -s)" in
  Darwin) PERM=$(stat -f '%Lp' "$FAKE/view.html") ;;
  *)      PERM=$(stat -c '%a' "$FAKE/view.html") ;;
esac
[ "$PERM" = "600" ] && ok "html 视图 600 权限" || bad "html 权限" "$PERM"
rm -f "$FAKE/view.html"

# ── 9b. sort + VAULT_LANG=en ─────────────────────────────
"$V" new "测试/zzz" --no-password >/dev/null 2>&1
"$V" new "测试/aaa" --no-password >/dev/null 2>&1
"$V" sort >/dev/null 2>&1 && ok "sort 执行" || bad "sort" ""
A_LINE=$("$V" peek | grep -n '^测试/aaa$' | cut -d: -f1)
Z_LINE=$("$V" peek | grep -n '^测试/zzz$' | cut -d: -f1)
[ -n "$A_LINE" ] && [ -n "$Z_LINE" ] && [ "$A_LINE" -lt "$Z_LINE" ] && ok "sort 字典序生效" || bad "sort 顺序" "aaa=$A_LINE zzz=$Z_LINE"
"$V" rm "测试/zzz" >/dev/null 2>&1; "$V" rm "测试/aaa" >/dev/null 2>&1
check "en help" "list entries" "$(VAULT_LANG=en "$V" help)"
SET_EN=$(printf 'x12345678901' | VAULT_LANG=en "$V" set "服务/Stripe" en_probe - 2>&1)
check "en set 消息" "Set 服务/Stripe.en_probe" "$SET_EN"
"$V" rm "服务/Stripe" en_probe >/dev/null 2>&1

# ── 10. rm / doctor ──────────────────────────────────────
"$V" rm "生活/电商" >/dev/null 2>&1
"$V" ls | grep -q "生活/电商" && bad "rm 删除条目" || ok "rm 删除条目"
"$V" doctor >/dev/null 2>&1 && ok "doctor 全绿" || bad "doctor" "$("$V" doctor 2>&1 | tail -3)"

printf '\n═══ 冒烟结果: %d 通过 / %d 失败 ═══\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
