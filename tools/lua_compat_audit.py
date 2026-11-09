#!/usr/bin/env python3
"""
Lua 兼容层审计：拿上游某个版本（0.6.3 / 0.7.3 / 1.0.4）的源码树当基准，
跟本仓库的注册表对一遍，输出 markdown 报告。

只做静态比对，不跑游戏。跑法：

    python tools/lua_compat_audit.py --ref .workbuddy/upstream/pe063/source

基准树不存在时直接报错退出，不会拿空气当基准。
"""

import argparse
import os
import re
import sys

# --------------------------------------------------------------------------- 解析

def strip_comments(src: str) -> str:
    """去掉 // 和 /* */ 注释，字符串里的内容原样保留。"""
    out = []
    i, n = 0, len(src)
    quote = None
    while i < n:
        ch = src[i]
        if quote:
            out.append(ch)
            if ch == '\\' and i + 1 < n:
                out.append(src[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in '"\'':
            quote = ch
            out.append(ch)
            i += 1
            continue
        if ch == '/' and i + 1 < n:
            nxt = src[i + 1]
            if nxt == '/':
                while i < n and src[i] != '\n':
                    i += 1
                continue
            if nxt == '*':
                i += 2
                while i + 1 < n and not (src[i] == '*' and src[i + 1] == '/'):
                    i += 1
                i += 2
                continue
        out.append(ch)
        i += 1
    return ''.join(out)


CALLBACK_PATTERNS = [
    # Lua_helper.add_callback(lua, "name", function(...)
    re.compile(r'add_callback\(\s*\w+\s*,\s*["\']([^"\']+)["\']\s*,\s*function\s*\(([^)]*)\)'),
    # add_callback(lua, "name", someFunction)  —— 传函数引用
    re.compile(r'add_callback\(\s*\w+\s*,\s*["\']([^"\']+)["\']\s*,'),
    # addLocalCallback("name", function(...)
    re.compile(r'addLocalCallback\(\s*["\']([^"\']+)["\']\s*,\s*function\s*\(([^)]*)\)'),
    re.compile(r'addLocalCallback\(\s*["\']([^"\']+)["\']\s*,'),
    # NovaFlare 那套：set("name", function(...)  —— 注意 set('x', 123) 那种是变量，不算
    re.compile(r'(?<![\w.])set\(\s*["\']([^"\']+)["\']\s*,\s*function\s*\(([^)]*)\)'),
]


def scan_callbacks(root: str) -> dict:
    """name -> {'params': str, 'file': str, 'line': int}"""
    found = {}
    for dirpath, _, files in os.walk(root):
        for fname in files:
            if not fname.endswith('.hx'):
                continue
            path = os.path.join(dirpath, fname)
            raw = open(path, encoding='utf-8', errors='ignore').read()
            src = strip_comments(raw)
            for pat in CALLBACK_PATTERNS:
                for m in pat.finditer(src):
                    name = m.group(1)
                    params = ''
                    if m.lastindex and m.lastindex >= 2:
                        params = ' '.join(m.group(2).split())
                    if name in found and found[name]['params']:
                        continue
                    if name in found and not params:
                        continue
                    line = src.count('\n', 0, m.start()) + 1
                    found[name] = {
                        'params': params,
                        'file': os.path.relpath(path, root).replace('\\', '/'),
                        'line': line,
                    }
    return found


CLASS_RE = re.compile(r'^\s*(?:@:.*\s*)?class\s+([A-Za-z_]\w*)', re.M)


def scan_classes(root: str, shallow: bool = True) -> set:
    names = set()
    for dirpath, dirs, files in os.walk(root):
        depth = os.path.relpath(dirpath, root).count(os.sep)
        if shallow and depth > 0:
            dirs[:] = []
            continue
        for fname in files:
            if fname.endswith('.hx'):
                src = strip_comments(open(os.path.join(dirpath, fname), encoding='utf-8', errors='ignore').read())
                names.update(CLASS_RE.findall(src))
    return names


STATIC_VAR_RE = re.compile(r'^\s*public\s+static\s+(?:var|final)\s+([A-Za-z_]\w*)', re.M)

# 只认 FunkinLua 自己的 set('x', ...)，前面带点的是 Map/Interp 的 set，不算
GLOBAL_SET_RE = re.compile(r'(?<![\w.])set\(\s*["\']([A-Za-z_]\w*)["\']')


def scan_globals(root: str) -> set:
    """FunkinLua 构造函数里 set('x', ...) 塞给 Lua 的全局变量（curBpm / songName 这类）。

    只扫 FunkinLua.hx —— 扫整棵树会把 Map.set('key', v) 也当进来，结果全是噪音。
    """
    names = set()
    for dirpath, _, files in os.walk(root):
        for fname in files:
            if fname != 'FunkinLua.hx':
                continue
            src = strip_comments(open(os.path.join(dirpath, fname), encoding='utf-8', errors='ignore').read())
            names.update(GLOBAL_SET_RE.findall(src))
    return names


def scan_static_fields(path: str) -> set:
    if not os.path.exists(path):
        return set()
    src = strip_comments(open(path, encoding='utf-8', errors='ignore').read())
    return set(STATIC_VAR_RE.findall(src))


def scan_aliases(path: str) -> dict:
    if not os.path.exists(path):
        return {}
    src = strip_comments(open(path, encoding='utf-8', errors='ignore').read())
    return dict(re.findall(r"bind\(\s*'([^']+)'\s*,\s*([^)]+)\)", src))


# --------------------------------------------------------------------------- 报告

def params_shape(params: str):
    """把签名压成 (必填数, 总参数数, 是否含默认值)，够判断"少传/多传会不会炸"。"""
    if not params.strip():
        return (0, 0, False)
    parts = [p.strip() for p in params.split(',') if p.strip()]
    required = 0
    has_default = False
    for p in parts:
        if p.startswith('?') or '=' in p:
            has_default = True
        else:
            required += 1
    return (required, len(parts), has_default)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--ref', required=True, help='基准源码目录，例如 .workbuddy/upstream/pe063/source')
    ap.add_argument('--ours', default='source')
    ap.add_argument('--clientprefs', default='source/backend/ClientPrefs.hx')
    ap.add_argument('--aliases', default='source/backend/ScriptClassAliases.hx')
    ap.add_argument('--label', default='')
    args = ap.parse_args()

    if not os.path.isdir(args.ref):
        print(f'基准目录不存在: {args.ref}', file=sys.stderr)
        return 2

    ref = scan_callbacks(args.ref)
    ours = scan_callbacks(args.ours)
    label = args.label or os.path.basename(os.path.dirname(args.ref))

    print(f'# Lua 兼容审计：{label} → 本仓库\n')
    print(f'- 基准注册回调 {len(ref)} 个，本仓库 {len(ours)} 个\n')

    missing = sorted(set(ref) - set(ours))
    print(f'## 缺失回调（{len(missing)}）\n')
    if missing:
        print('| 名字 | 基准签名 | 位置 |')
        print('|---|---|---|')
        for name in missing:
            info = ref[name]
            print(f'| `{name}` | `{info["params"] or "<函数引用>"}` | {info["file"]}:{info["line"]} |')
    else:
        print('无。\n')

    diffs = []
    for name in sorted(set(ref) & set(ours)):
        a, b = ref[name]['params'], ours[name]['params']
        if not a or not b or a == b:
            continue
        ra, rb = params_shape(a), params_shape(b)
        # 只有真会炸的才报：
        #   rb[0] > ra[0]  —— 我们要求传的参数比老 mod 会传的还多
        #   rb[1] < ra[0]  —— 我们根本接不住老 mod 传的参数个数
        if rb[0] > ra[0] or rb[1] < ra[0]:
            diffs.append((name, a, b, ref[name]['file'], ref[name]['line']))
    print(f'## 可能不兼容的签名（{len(diffs)}）\n')
    if diffs:
        print('| 名字 | 基准 | 本仓库 | 位置 |')
        print('|---|---|---|---|')
        for name, a, b, f, l in diffs:
            print(f'| `{name}` | `{a}` | `{b}` | {f}:{l} |')
    else:
        print('无。\n')

    # 0.6.3 的扁平类名
    ref_classes = scan_classes(args.ref)
    if ref_classes:
        ours_classes = scan_classes(args.ours, shallow=False)
        aliases = scan_aliases(args.aliases)
        unhandled = sorted(c for c in ref_classes if c not in aliases and c not in ours_classes)
        print(f'## 裸类名没有映射（{len(unhandled)}/{len(ref_classes)}）\n')
        if unhandled:
            print('这些在基准版本里是 `source/` 根目录下的类，脚本会 `import X;` 直接用，')
            print('现在既没有别名、也没有同名类：\n')
            print(', '.join(f'`{c}`' for c in unhandled))
        else:
            print('全部有映射或同名类。')
        print()

    # 全局变量（curBpm / songName / curStep 这些杂项）
    ref_globals = scan_globals(args.ref)
    our_globals = scan_globals(args.ours)
    missing_globals = sorted(ref_globals - our_globals)
    print(f'## 缺失的 Lua 全局变量（基准 {len(ref_globals)}，缺 {len(missing_globals)}）\n')
    if missing_globals:
        print(', '.join(f'`{g}`' for g in missing_globals))
    else:
        print('无缺失。')
    print()

    # ClientPrefs 静态字段
    ref_cp = os.path.join(args.ref, 'ClientPrefs.hx')
    if os.path.exists(ref_cp):
        ref_fields = scan_static_fields(ref_cp)
        our_fields = scan_static_fields(args.clientprefs)
        missing_fields = sorted(ref_fields - our_fields)
        print(f'## ClientPrefs 静态字段（基准 {len(ref_fields)}，缺 {len(missing_fields)}）\n')
        if missing_fields:
            print(', '.join(f'`{f}`' for f in missing_fields))
        else:
            print('无缺失。')
        print()

    return 0


if __name__ == '__main__':
    sys.exit(main())
