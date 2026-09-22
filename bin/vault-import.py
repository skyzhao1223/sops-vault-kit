#!/usr/bin/env python3
"""vault-import.py —— 把密码管理器导出的 CSV 转成 JSONL，供 `vault import` 逐条入库。

支持格式（--format auto 时按表头自动识别）：
  bitwarden   folders,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp
  1password   Title,Username,Password,URL,Notes,...
  chrome      name,url,username,password
  generic     含 name/url/username/password/note 的任意列组合（本库 `vault export` 的格式即此类）

输出：每行一个 JSON 对象 {name,url,username,password,totp,note}（空字段省略）。
TOTP 若是 otpauth:// URI，自动提取其中的 secret 参数。
本脚本只读 CSV、只写 stdout——不接触密钥文件。
"""
import csv
import json
import re
import sys


def pick(row, *candidates):
    """按候选列名（不区分大小写、忽略首尾空白）取第一个非空值。"""
    for k in row:
        kl = (k or "").strip().lower()
        if kl in candidates:
            v = (row[k] or "").strip()
            if v:
                return v
    return ""


def totp_secret(value):
    if value.startswith("otpauth://"):
        m = re.search(r"[?&]secret=([A-Za-z2-7]+)", value)
        return m.group(1).upper() if m else ""
    return value


def detect(header_lower):
    if "login_uri" in header_lower or "login_password" in header_lower:
        return "bitwarden"
    if "title" in header_lower:
        return "1password"
    if "name" in header_lower and "url" in header_lower and "password" in header_lower:
        return "chrome"
    return "generic"


def main():
    if len(sys.argv) < 2:
        sys.exit("用法: vault-import.py <csv> [format]")
    path = sys.argv[1]
    fmt = sys.argv[2] if len(sys.argv) > 2 else "auto"

    try:
        with open(path, newline="", encoding="utf-8-sig") as f:
            rows = list(csv.DictReader(f))
    except OSError as exc:
        sys.exit(f"无法读取 CSV: {exc}")

    if not rows:
        print("format=empty entries=0", file=sys.stderr)
        return

    header_lower = [(k or "").strip().lower() for k in rows[0].keys()]
    if fmt == "auto":
        fmt = detect(header_lower)

    out = []
    for r in rows:
        if fmt == "bitwarden":
            name = pick(r, "name")
            folder = pick(r, "folders", "folder", "collection")
            if folder and folder.lower() != "none":
                name = folder.rstrip("/") + "/" + name if name else folder
            rec = {
                "name": name,
                "url": pick(r, "login_uri", "uri"),
                "username": pick(r, "login_username"),
                "password": pick(r, "login_password"),
                "totp": totp_secret(pick(r, "login_totp")),
                "note": pick(r, "notes"),
            }
        elif fmt == "1password":
            rec = {
                "name": pick(r, "title"),
                "url": pick(r, "url", "website", "urls"),
                "username": pick(r, "username"),
                "password": pick(r, "password"),
                "totp": totp_secret(pick(r, "otp", "totp", "one-time password")),
                "note": pick(r, "notes", "note"),
            }
        else:  # chrome / generic / 本库 export
            rec = {
                "name": pick(r, "name", "title", "system", "系统"),
                "url": pick(r, "url", "login_uri", "site", "入口地址"),
                "username": pick(r, "username", "user", "login", "用户名"),
                "password": pick(r, "password", "pass", "密码"),
                "totp": totp_secret(pick(r, "totp", "otp")),
                "note": pick(r, "note", "notes", "remark", "备注"),
            }
        rec = {k: v for k, v in rec.items() if k == "name" or v}
        if rec.get("name"):
            out.append(rec)

    for rec in out:
        print(json.dumps(rec, ensure_ascii=False))
    print(f"format={fmt} entries={len(out)}", file=sys.stderr)


if __name__ == "__main__":
    main()
