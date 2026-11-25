#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
convert_kicad10_to_kicanvas.py
==============================

把 KiCad 10（含嘉立创 EDA 专业版导入）生成的 .kicad_pcb 文件转换成
电子森林/硬禾学堂网页端 KiCad 查看器（KiCanvas，内置的是 KiCad 6/7 时代的解析器）
能够正确识别"网络（NET）"的格式。

背景
----
KiCad 10 的新 PCB 文件格式里，网络只在对象内部以"名称"形式出现：
    (segment ... (net "GND"))
    (pad "1" ... (net "GND"))
    (zone (net "GND") ...)
文件里**没有**顶层网络表。而 eetree 网页端使用的旧版 KiCanvas 解析器要求：
    1) 顶层有网络表：(net 0 "") (net 1 "GND") (net 2 "3V3") ...
    2) 走线/过孔：(net N)               —— 数字编号
    3) 焊盘：    (net N "NAME")        —— 数字 + 名称
    4) 覆铜：    (net N) + (net_name "NAME")
因此旧查看器解析出来 nets = 0，所有走线的 net 都是 undefined，
于是"所有走线看起来都是同一种走线"。

另外，KiCad 9/10 允许在 polygon 的 (pts ...) 里写圆弧：
    (pts (arc (start ...) (mid ...) (end ...)) (xy ...) ...)
旧版 KiCanvas 的 pts 解析器只认 (xy x y)，遇到 arc 会把 "start" 当成 x 坐标，
得到 NaN，渲染时抛异常，整个查看器白屏/蓝屏（aqua 背景）。
本脚本将 pts 中的 arc 按 12° 步长采样成折线点，保持形状不变。

做法
----
1. 解析 S 表达式（保留原始原子文本，浮点数格式不变）；
2. 把所有 (pts ...) 内的 (arc ...) 展开成 (xy x y) 折线；
3. 按首次出现顺序给所有网络名编号（1..N，0 保留给空网络），在 (setup) 之后
   插入顶层网络表，并把 pad / segment / via / zone 的 net 引用改成旧格式；
4. 原样输出（仅改动上述部分），UTF-8。

用法
----
    python convert_kicad10_to_kicanvas.py 输入.kicad_pcb 输出.kicad_pcb

注意
----
* 脚本只读输入文件，写入输出文件，不会修改原文件；
* 输出文件同时可被 KiCad 10 正常打开（已验证 LoadBoard 通过）；
* 如果用 KiCad 10 打开输出文件后再"保存"，会写回 KiCad 10 的新格式（网络又变回
  只有名称），所以**在重新生成/重新上传之前不要用 KiCad 再保存它**；
* 网页端（eetree/硬禾学堂）"设计资源 - KiCad文件"上传的是一个 zip（≤30MB），
  zip 里必须包含 .kicad_sch 和 .kicad_pcb（本目录的 _upload.zip 已按此打包）。
"""

import math
import sys

sys.stdout.reconfigure(encoding="utf-8")


# ---------------------------------------------------------------- S 表达式
class Atom:
    """词法原子。raw 保留原始文本（字符串含引号）。"""

    __slots__ = ("raw", "is_str")

    def __init__(self, raw, is_str=False):
        self.raw = raw
        self.is_str = is_str


class Node:
    """一个括号节点：tag 为第一个原子，items 为子节点/原子列表。"""

    __slots__ = ("tag", "items")

    def __init__(self, tag, items):
        self.tag = tag
        self.items = items


def tokenize(s):
    i, n, out = 0, len(s), []
    while i < n:
        c = s[i]
        if c in " \t\r\n":
            i += 1
        elif c in "()":
            out.append(c)
            i += 1
        elif c == '"':
            j = i + 1
            while j < n:
                if s[j] == "\\":
                    j += 2
                    continue
                if s[j] == '"':
                    break
                j += 1
            out.append(Atom(s[i : j + 1], True))
            i = j + 1
        else:
            j = i
            while j < n and s[j] not in ' \t\r\n()"':
                j += 1
            out.append(Atom(s[i:j], False))
            i = j
    return out


def parse(tokens):
    pos = 0

    def node():
        nonlocal pos
        pos += 1
        tag = tokens[pos].raw
        pos += 1
        items = []
        while tokens[pos] != ")":
            if tokens[pos] == "(":
                items.append(node())
            else:
                items.append(tokens[pos])
                pos += 1
        pos += 1
        return Node(tag, items)

    items = []
    while pos < len(tokens):
        if tokens[pos] == "(":
            items.append(node())
        else:
            items.append(tokens[pos])
            pos += 1
    return items


def fmt(x):
    """输出坐标数字，保持 KiCad 常见的小数写法。"""
    if abs(x) < 1e-9:
        x = 0.0
    s = ("%.6f" % x).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def serialize(n, indent=0):
    pad = "  " * indent
    if isinstance(n, Atom):
        return pad + n.raw
    line = pad + "(" + n.tag
    out = []
    for it in n.items:
        if isinstance(it, Atom):
            line += " " + it.raw
        else:
            if line:
                out.append(line)
                line = ""
            out.append(serialize(it, indent + 1))
    if line:
        out.append(line + ")")
    else:
        out[-1] = out[-1] + ")" if out else pad + ")"
    return "\n".join(out)


def unquote(a):
    if isinstance(a, Atom) and a.is_str:
        return a.raw[1:-1]
    return None


def numval(a):
    try:
        return float(a.raw)
    except (TypeError, ValueError):
        return None


# ------------------------------------------------------- (pts) 内圆弧展开
def arc_points(arc, step_deg=12.0):
    """把 (arc (start x y) (mid x y) (end x y)) 采样为折线点列表。"""
    vals = {}
    for it in arc.items:
        if isinstance(it, Node) and it.tag in ("start", "mid", "end"):
            xs = [numval(x) for x in it.items if isinstance(x, Atom)]
            if len(xs) >= 2 and xs[0] is not None and xs[1] is not None:
                vals[it.tag] = xs[:2]
    if len(vals) < 3:
        return None
    (x1, y1), (x2, y2), (x3, y3) = vals["start"], vals["mid"], vals["end"]
    d = 2.0 * (x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2))
    if abs(d) < 1e-12:  # 三点共线：退化成线段
        return [vals["start"], vals["end"]]
    s1, s2, s3 = x1 * x1 + y1 * y1, x2 * x2 + y2 * y2, x3 * x3 + y3 * y3
    ux = (s1 * (y2 - y3) + s2 * (y3 - y1) + s3 * (y1 - y2)) / d
    uy = (s1 * (x3 - x2) + s2 * (x1 - x3) + s3 * (x2 - x1)) / d
    r = math.hypot(x1 - ux, y1 - uy)
    a0 = math.atan2(y1 - uy, x1 - ux)
    a1 = math.atan2(y3 - uy, x3 - ux)
    am = math.atan2(y2 - uy, x2 - ux)

    def norm(a):
        return a % (2 * math.pi)

    ccw = norm(a1 - a0)
    sweep = ccw if norm(am - a0) <= ccw else ccw - 2 * math.pi
    n = max(2, int(math.ceil(abs(sweep) / math.radians(step_deg))))
    pts = [(x1, y1)]
    for i in range(1, n):
        a = a0 + sweep * i / n
        pts.append((ux + r * math.cos(a), uy + r * math.sin(a)))
    pts.append((x3, y3))
    return pts


def expand_arcs(node, stats):
    """递归把所有 (pts ...) 内的 (arc ...) 替换为 (xy x y)。"""
    if not isinstance(node, Node):
        return
    if node.tag == "pts":
        new_items = []
        for it in node.items:
            if isinstance(it, Node) and it.tag == "arc":
                pts = arc_points(it)
                if pts:
                    for x, y in pts:
                        new_items.append(Node("xy", [Atom(fmt(x)), Atom(fmt(y))]))
                    stats["arcs"] += 1
                    continue
            new_items.append(it)
        node.items = new_items
        return
    for it in node.items:
        expand_arcs(it, stats)


# ------------------------------------------------------------- 网络表修复
NET_PARENTS = ("pad", "segment", "via", "zone")


def net_name_of(net_node):
    return unquote(net_node.items[0])


def fix_nets(board):
    """收集网络名并改写为旧版 KiCanvas 需要的数字网络格式。"""
    order, seen = [], set()

    def collect(n, parent=None):
        if isinstance(n, Node):
            if n.tag == "net" and parent in NET_PARENTS:
                name = net_name_of(n)
                if name is not None and name not in seen:
                    seen.add(name)
                    order.append(name)
            for it in n.items:
                collect(it, n.tag)

    collect(board)

    num, nxt = {}, 1
    for name in order:
        if name == "":
            num[name] = 0
        else:
            num[name] = nxt
            nxt += 1

    def apply(n):
        if not isinstance(n, Node):
            return
        if n.tag in ("segment", "via"):
            for i, it in enumerate(n.items):
                if isinstance(it, Node) and it.tag == "net":
                    n.items[i] = Node("net", [Atom(str(num[net_name_of(it)]))])
        elif n.tag == "pad":
            for i, it in enumerate(n.items):
                if isinstance(it, Node) and it.tag == "net":
                    name = net_name_of(it)
                    n.items[i] = Node(
                        "net", [Atom(str(num[name])), Atom('"' + name + '"', True)]
                    )
        elif n.tag == "zone":
            idx = next(
                (i for i, it in enumerate(n.items) if isinstance(it, Node) and it.tag == "net"),
                None,
            )
            if idx is not None:
                name = net_name_of(n.items[idx])
                n.items[idx] = Node("net", [Atom(str(num[name]))])
                n.items.insert(idx + 1, Node("net_name", [Atom('"' + name + '"', True)]))
        for it in n.items:
            apply(it)

    apply(board)
    return num


def convert(src, dst):
    with open(src, encoding="utf-8") as f:
        text = f.read()
    roots = parse(tokenize(text))
    if not roots or not isinstance(roots[0], Node) or roots[0].tag != "kicad_pcb":
        raise SystemExit("输入文件不是 .kicad_pcb（根节点不是 kicad_pcb）")
    board = roots[0]

    stats = {"arcs": 0}
    expand_arcs(board, stats)

    num = fix_nets(board)

    setup_idx = next(
        (i for i, it in enumerate(board.items) if isinstance(it, Node) and it.tag == "setup"),
        None,
    )
    if setup_idx is None:
        raise SystemExit("文件里找不到 (setup ...)，无法插入网络表")

    net_nodes = [Node("net", [Atom("0"), Atom('""', True)])]
    for name, code in num.items():
        if code == 0:
            continue
        net_nodes.append(Node("net", [Atom(str(code)), Atom('"' + name + '"', True)]))
    board.items[setup_idx + 1 : setup_idx + 1] = net_nodes

    out = serialize(board) + "\n"
    with open(dst, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)

    names = [n for n in num if n != ""]
    print("输入 : %s" % src)
    print("输出 : %s" % dst)
    print("展开 polygon 内圆弧 : %d 处" % stats["arcs"])
    print("网络表 : %d 个（含 net 0 空网络）" % len(net_nodes))
    print("网络名 : %s" % ", ".join(names))
    print("输出大小 : %d 字节" % len(out.encode("utf-8")))


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        print("用法: python convert_kicad10_to_kicanvas.py 输入.kicad_pcb 输出.kicad_pcb")
        raise SystemExit(2)
    convert(argv[1], argv[2])


if __name__ == "__main__":
    main(sys.argv)
