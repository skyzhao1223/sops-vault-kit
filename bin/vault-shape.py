#!/usr/bin/env python3
"""vault shape —— 只报告 stdin 内容的"形状"，绝不输出内容本身。

用途：入库前体检剪贴板（`pbpaste | vault shape`）。报告内容：
长度/行数、字符构成（数字/大小写/符号）、已知令牌前缀（sk-/ghp_/AKIA…，
前缀只是类型标识，不构成泄露）、SHA-256 指纹前 12 位（用于写入前后回环
校验，不可逆推），以及多行/含空格/过短/首尾空白等异常警告。

尾部换行的剥离语义与 `vault set ... -` 一致，保证"体检所见 = 入库所存"。
"""
import hashlib
import re
import sys

data = sys.stdin.buffer.read().decode("utf-8", "replace")
data = data.rstrip("\n")  # 与 vault set 的 stdin 语义一致

if not data:
    print("空")
    sys.exit(0)

lines = data.split("\n")

classes = []
if re.search(r"[0-9]", data):
    classes.append("数字")
if re.search(r"[a-z]", data):
    classes.append("小写")
if re.search(r"[A-Z]", data):
    classes.append("大写")
if re.search(r"[!-/:-@[-`{-~]", data):
    classes.append("符号")

# 已知令牌前缀：只报类型标识（如 "sk-test-"），不报后续内容
m = re.match(
    r"^(sk|pk|rk|ghp|gho|glpat|AKIA|ASIA|LTAI|xox[baprs]|AIza|age|ssh|wx)"
    r"[-_]?(?:live|test|prod|dev)?[-_]?",
    data,
)
prefix = m.group(0) if m else ""

warns = []
if len(lines) > 1:
    warns.append("多行!")
if " " in data:
    warns.append("含空格!")
if len(data) < 8:
    warns.append("过短!")
if data != data.strip():
    warns.append("首尾空白!")

sha = hashlib.sha256(data.encode()).hexdigest()[:12]
line = "长度 {} 字符 / {} 行 | 构成: {} | 已知前缀: {} | sha256:{}".format(
    len(data), len(lines), "+".join(classes) or "?", prefix or "无", sha
)
line += (" | ⚠️ " + " ".join(warns)) if warns else " | ✓ 形状正常"
print(line)
