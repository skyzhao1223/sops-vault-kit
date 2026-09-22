#!/usr/bin/env python3
"""vault audit —— 直接检查加密后的文件，确认敏感字段真的没有以明文存在。

设计前提：.sops.yaml 用**白名单** unencrypted_regex ——
默认全部字段加密，只有列进白名单的字段保持明文。

因此风险只剩三种，这个脚本逐一检查：
  1. 明文存放、但不在白名单里      → 规则没生效（正则写错、或改了规则没 reencrypt）
  2. 白名单里包含了本身敏感的字段名 → 设计错误，等于主动放行
  3. 白名单字段的值看起来像密钥     → 值放错了字段

特点：**不需要 age 密钥也能运行**——该明文的部分本来就在文件里，
该加密的部分已经是密文，两者都能直接看见。

用法（由 `vault audit` 调用）：
    vault-audit.py <.sops.yaml 路径> <secrets.yaml 路径>
"""
import pathlib
import re
import sys

# 字段名里出现这些词就是敏感的，绝不该出现在白名单里
SENSITIVE_WORDS = (
    "password", "passwd", "passphrase", "secret", "token", "totp", "otp", "pin",
    "key", "credential", "cert", "private", "sign", "salt", "seed", "auth",
    "cookie", "session", "dsn", "aes",
)

# 白名单里允许出现的例外（名字里含敏感词，但确实不是秘密）
ALLOWED_EXCEPTIONS = {
    "sign_name",   # 短信签名名称，例如「某某科技」
    "cert_path",   # 证书文件的路径，不是证书内容
    "key_name",    # 密钥的名称/别名，不是密钥本身
    "auth_url",    # 认证入口地址
}

SECRET_PREFIX = re.compile(
    r"^(sk-|pk-|rk-|AKIA|ASIA|LTAI|ghp_|gho_|glpat-|xox[baprs]-|eyJ|-----BEGIN|AIza|wx[0-9a-f]{16})"
)
B64ISH = re.compile(r"^[A-Za-z0-9+/=_\-\.]+$")


def load_allowlist(path):
    text = pathlib.Path(path).read_text()
    m = re.search(r"^\s*unencrypted_regex:\s*(.+?)\s*$", text, re.M)
    if not m:
        sys.exit(
            "vault audit: .sops.yaml 里找不到 unencrypted_regex。\n"
            "  若它用的是 encrypted_regex（黑名单），请切到白名单模式，见 .sops.yaml 的说明。"
        )
    raw = m.group(1).strip()
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "'\"":
        raw = raw[1:-1]
    try:
        rx = re.compile(raw)
    except re.error as exc:
        sys.exit(f"vault audit: unencrypted_regex 不是合法正则: {exc}")
    body = raw.replace("(?i)", "").strip()
    body = body.lstrip("^").rstrip("$")
    if body.startswith("(") and body.endswith(")"):
        body = body[1:-1]
    names = [n for n in body.split("|") if n]
    return rx, names


def load_fields(path):
    """从加密文件里读出所有字段，以及它是否为密文。只解析 systems 段。"""
    rows = []
    entry = None
    for line in pathlib.Path(path).read_text().splitlines():
        if re.match(r"^sops:\s*$", line):
            break
        m = re.match(r"^ {4}([^\s#][^:]*):\s*$", line)
        if m:
            entry = m.group(1).strip()
            continue
        m = re.match(r"^ {8}([^\s#-][^:]*):\s?(.*)$", line)
        if m and entry is not None:
            name, value = m.group(1).strip(), m.group(2).strip()
            value = value.strip("\"'")
            rows.append((entry, name, value, value.startswith("ENC[")))
    return rows


def looks_like_secret(value):
    """启发式：像不像一个密钥。宁可误报，不要漏报。"""
    if not isinstance(value, str) or len(value) < 12:
        return False
    if SECRET_PREFIX.match(value):
        return True
    # 路径和 URL 不是密钥（否则 cert_path 这类字段会一直误报）
    if value.startswith(("/", "~", "./")) or "://" in value:
        return False
    if re.search(r"\s", value) or not B64ISH.match(value):
        return False
    return any(c.isdigit() for c in value) and any(c.isalpha() for c in value)


def main():
    if len(sys.argv) < 3:
        sys.exit("用法: vault-audit.py <.sops.yaml> <secrets.yaml>")
    rx, names = load_allowlist(sys.argv[1])
    rows = load_fields(sys.argv[2])

    plain = [r for r in rows if not r[3]]
    enc = [r for r in rows if r[3]]
    entries = sorted({r[0] for r in rows})

    print(f"库中字段：{len(enc)} 个已加密 / {len(plain)} 个明文（共 {len(entries)} 条记录）")
    print(f"白名单：{len(names)} 个字段名保持明文，其余一律加密")
    print()

    problems = 0

    # 风险 1：明文存放，但不在白名单里
    leak = [(e, n) for e, n, v, _ in plain if v and not rx.search(n)]
    if leak:
        problems += len(leak)
        print("🔴 高危：明文存放，但不在白名单里（规则没生效？）")
        for e, n in leak:
            print(f"     {e}  →  {n}")
        print("     处理：检查 .sops.yaml 的白名单是否写错，然后执行 vault reencrypt")
    else:
        print("🔴 明文未授权字段：无")
    print()

    # 风险 2：白名单里混进了敏感字段名
    risky = [
        n for n in names
        if any(w in n.lower() for w in SENSITIVE_WORDS) and n.lower() not in ALLOWED_EXCEPTIONS
    ]
    if risky:
        problems += len(risky)
        print("🔴 高危：白名单里有敏感字段名，等于主动放行明文")
        for n in risky:
            print(f"     {n}")
        print("     处理：从 .sops.yaml 白名单里删掉它，再 vault reencrypt")
    else:
        print(f"🔴 白名单敏感词检查：通过（{len(ALLOWED_EXCEPTIONS)} 个已知例外已豁免）")
    print()

    # 风险 3：白名单字段的值看起来像密钥
    suspect = [(e, n, len(v)) for e, n, v, _ in plain if rx.search(n) and looks_like_secret(v)]
    if suspect:
        print("🟡 待确认：明文白名单字段，但值看起来像密钥（启发式）")
        for e, n, size in suspect:
            print(f"     {e}  →  {n}（{size} 字符）")
        print("     说明：appid、序列号这类标识符本来就会命中这个启发式，确认后可忽略；")
        print("           但若某个白名单字段里真的放了密钥，请把它从白名单删掉并 vault reencrypt")
    else:
        print("🟡 白名单字段的值：无异常")
    print()

    # 提示：白名单字段实际却是密文（白名单拼写可能有误）
    over = [(e, n) for e, n, v, e_ in rows if e_ and rx.search(n)]
    if over:
        print("🟡 白名单字段却是密文（白名单拼写可能有误，本该可读的字段被加密了）")
        for e, n in over:
            print(f"     {e}  →  {n}")

    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
