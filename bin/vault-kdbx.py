#!/usr/bin/env python3
"""vault-kdbx.py —— 解密后的库 JSON（stdin）→ KeePassXML 2.x（stdout）。

用途：`vault kdbx out.xml` 的内部实现；导出的 XML 可直接被
KeePassXC（数据库 → 导入 → KeePassXML）和 KeePassium（iPhone）读入，
让手机和桌面 GUI 用上同一个库的快照。

只用标准库。输出是明文 XML（含全部密码），由调用方负责落盘权限与提醒删除。
分组规则：条目名 `前缀/名称` 的"前缀"成为 KeePass 分组，无前缀的进根目录。
TOTP 种子按 KeePassXC 约定写成 otpauth:// URI（键名 otp），导入后动态码直接可用。
"""
import json
import sys
import uuid
from datetime import datetime, timezone
from xml.etree.ElementTree import Element, SubElement, tostring


def uid():
    return str(uuid.uuid4())


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def time_block(parent):
    t = SubElement(parent, "Times")
    for tag in ("CreationTime", "LastModificationTime", "LastAccessTime"):
        SubElement(t, tag).text = now()
    SubElement(t, "Expires").text = "False"


def add_string(entry, key, value, protect=False):
    if value is None or value == "":
        return
    s = SubElement(entry, "String")
    SubElement(s, "Key").text = key
    v = SubElement(s, "Value")
    if protect:
        v.set("ProtectInMemory", "True")
    v.text = value


def main():
    data = json.load(sys.stdin).get("systems", {})

    root = Element("KeePassFile")
    meta = SubElement(root, "Meta")
    SubElement(meta, "Generator").text = "sops-vault-kit"
    time_block(meta)
    r = SubElement(root, "Root")

    def make_group(parent, title):
        g = SubElement(parent, "Group")
        SubElement(g, "UUID").text = uid()
        SubElement(g, "Name").text = title
        time_block(g)
        return g

    groups = {}
    for name in sorted(data):
        prefix = name.split("/")[0] if "/" in name else ""
        groups.setdefault(prefix, []).append(name)

    gmap = {}
    for gname in sorted(groups):
        parent = r if gname == "" else gmap.setdefault(gname, make_group(r, gname))
        for full in groups[gname]:
            fields = data[full]
            if not isinstance(fields, dict):
                continue
            e = SubElement(parent, "Entry")
            SubElement(e, "UUID").text = uid()
            time_block(e)
            short = full.split("/", 1)[1] if "/" in full else full

            def fv(k):
                x = fields.get(k)
                return x if isinstance(x, str) else ""

            add_string(e, "Title", short)
            add_string(e, "URL", fv("url") or fv("endpoint") or fv("restapi"))
            add_string(e, "UserName", fv("username") or fv("account"))
            add_string(e, "Password", fv("password"), protect=True)

            notes = []
            if fv("env"):
                notes.append("env: " + fv("env"))
            if fv("owner"):
                notes.append("owner: " + fv("owner"))
            body = fv("note") or fv("remark")
            if body:
                notes.append(body)
            add_string(e, "Notes", "\n".join(notes))

            seed = fv("totp")
            if seed:
                add_string(
                    e, "otp",
                    "otpauth://totp/{}?secret={}&period=30&digits=6".format(short, seed),
                    protect=True,
                )

            handled = {"url", "endpoint", "restapi", "username", "account",
                       "password", "note", "remark", "env", "owner", "totp"}
            for k in sorted(fields):
                if k in handled:
                    continue
                v = fields.get(k)
                if isinstance(v, str) and v:
                    # 白名单外的字段默认按敏感处理（ProtectInMemory）
                    add_string(e, k, v, protect=True)

    sys.stdout.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                     + tostring(root, encoding="unicode") + "\n")


if __name__ == "__main__":
    main()
