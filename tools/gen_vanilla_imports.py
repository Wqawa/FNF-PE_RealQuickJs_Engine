#!/usr/bin/env python3
"""重新生成 source_vanilla/vanilla/psychlua/IsolatedImports.hx 里的类表。

vanilla 树是原版 1.0.4 整体加了 `vanilla.` 前缀搬过来的，所以「包名 + 类名」和本体
完全一样。hscript-iris 解析 `import backend.ClientPrefs` 时先查 Iris.proxyImports，
查不到就落到 Type.resolveClass —— 后者会命中本体的类，于是原版模式的脚本悄悄改到
本体状态上。这张表就是给 proxyImports 用的白名单：只放 vanilla.* 自己的类。

用法（仓库根目录）：
    python tools/gen_vanilla_imports.py

扫的是顶格的 class / enum / typedef / abstract 声明 + 文件里的 package 行，
嵌套类不算（脚本也不该 import 它们）。增删类之后重跑一次即可。
"""

import io
import os
import re

ROOT = 'source_vanilla/vanilla'
OUT = os.path.join(ROOT, 'psychlua', 'IsolatedImports.hx')
DECL = re.compile(r'^(?:final\s+|abstract\s+|class\s+|enum\s+|typedef\s+)([A-Za-z_][A-Za-z0-9_]*)')

TEMPLATE = '''package vanilla.psychlua;

import crowplexus.iris.Iris;

/**
 * vanilla 树的 import 隔离表。
 *
 * 三棵树编在一个 exe 里，`import backend.ClientPrefs` 和本体的全名一字不差，
 * 而 hscript-iris 解析 import 时先查 Iris.proxyImports、再落到 Type.resolveClass ——
 * 后者会命中**本体**的类。所以跑脚本之前先把这张表灌进 proxyImports，
 * 原版模式的脚本就只会看到 vanilla.* 的类。
 *
 * 表是扫 source_vanilla/vanilla/ 的包名 + 顶格类型声明生成的
 * （tools/gen_vanilla_imports.py），增删类之后重跑一次。
 */
class IsolatedImports
{
	/** 相对 vanilla 包的全名，例如 'backend.ClientPrefs'、'states.PlayState' */
	public static var CLASSES:Array<String> = [
%s
	];

	static var registered:Bool = false;

	public static function register():Void
	{
		if (registered) return;
		registered = true;

		var simpleCount:Map<String, Int> = [];

		for (fqn in CLASSES)
		{
			var cls:Dynamic = Type.resolveClass('vanilla.' + fqn);
			if (cls == null) continue;
			Iris.proxyImports.set(fqn, cls);

			var simple:String = fqn.split('.').pop();
			simpleCount[simple] = (simpleCount.exists(simple) ? simpleCount[simple] : 0) + 1;
		}

		// 简单名只在这棵树里唯一时才映射，避免撞名指错
		for (fqn in CLASSES)
		{
			var simple:String = fqn.split('.').pop();
			if (simpleCount[simple] != 1) continue;
			if (Iris.proxyImports.exists(simple)) continue;
			var cls:Dynamic = Type.resolveClass('vanilla.' + fqn);
			if (cls != null) Iris.proxyImports.set(simple, cls);
		}
	}
}
'''


def collect():
    found = set()
    for dirpath, _, files in os.walk(ROOT):
        for name in files:
            if not name.endswith('.hx'):
                continue
            path = os.path.join(dirpath, name)
            pkg = ''
            with io.open(path, encoding='utf-8', errors='replace') as fh:
                for line in fh:
                    stripped = line.strip()
                    if stripped.startswith('package '):
                        pkg = stripped[len('package '):].rstrip(';').strip()
                        if pkg == 'vanilla':
                            pkg = ''
                        elif pkg.startswith('vanilla.'):
                            pkg = pkg[len('vanilla.'):]
                        continue
                    if line[:1] and not line[:1].isspace():
                        m = DECL.match(line)
                        if m:
                            found.add((pkg + '.' + m.group(1)) if pkg else m.group(1))
    return sorted(found)


def main():
    entries = collect()
    body = '\n'.join("\t\t'%s'," % e for e in entries)
    with io.open(OUT, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(TEMPLATE % body)
    print('%s: %d 个类/枚举' % (OUT, len(entries)))


if __name__ == '__main__':
    main()
