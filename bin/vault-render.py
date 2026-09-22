#!/usr/bin/env python3
"""vault-render.py —— 把解密后的库 JSON 渲染进 vault-view.html 模板。

用法（由 `vault html` 调用）：
    <解密 JSON 从 stdin> | vault-render.py <模板路径> <.sops.yaml 路径>

做两件事：
  1. 注入 DATA（全部记录，值已解密）
  2. 对照 .sops.yaml 的白名单算出 SENSITIVE（哪些字段名是加密存储的），
     页面据此决定哪些值默认打码 —— 打码规则与磁盘加密规则**同源**，不会漂移。

安全说明：输出的 HTML 含全部明文（600 权限、放 /tmp、用完 vault clean），
这与旧版一致，是 `vault html` 的既定代价。
"""
import json
import pathlib
import re
import sys


def load_allowlist(cfg_text):
    m = re.search(r"^\s*unencrypted_regex:\s*(.+?)\s*$", cfg_text, re.M)
    if not m:
        return None
    raw = m.group(1).strip()
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "'\"":
        raw = raw[1:-1]
    try:
        return re.compile(raw)
    except re.error:
        return None


def main():
    if len(sys.argv) < 3:
        sys.exit("用法: vault-render.py <模板> <.sops.yaml>（库 JSON 走 stdin）")
    tpl_path, cfg_path = sys.argv[1], sys.argv[2]
    tpl = pathlib.Path(tpl_path).read_text()
    cfg = pathlib.Path(cfg_path).read_text()

    try:
        data = json.load(sys.stdin).get("systems", {})
    except json.JSONDecodeError as exc:
        sys.exit(f"vault-render: 库 JSON 解析失败: {exc}")

    allow = load_allowlist(cfg)
    # fail-closed：白名单读不出来时，把所有字段都当敏感处理（全打码）
    sensitive = sorted({
        k for v in data.values() if isinstance(v, dict)
        for k in v if not (allow and allow.search(k))
    })

    def esc(obj):
        return json.dumps(obj, ensure_ascii=False).replace("<", "\\u003c")

    for marker in ("/*__DATA__*/{}", "/*__SENSITIVE__*/[]"):
        if marker not in tpl:
            sys.exit(f"vault-render: 模板 {tpl_path} 缺少占位符 {marker}（模板与脚本版本不匹配？）")

    out = tpl.replace("/*__DATA__*/{}", esc(data)).replace("/*__SENSITIVE__*/[]", esc(sensitive))
    sys.stdout.write(out)


if __name__ == "__main__":
    main()
