package;

import openfl.Lib;

/**
 * 进程入口（`Project.xml` 的 `<app main="Main">` 指这里）：初始化 → 按 engine.txt 导航。
 *
 * 这里只干三件事：装崩溃拦截、读 engine.txt 决定走哪棵树、把那一棵的 Sprite 挂上去。
 * **不要往这个文件里加业务代码** —— 它属于公共层（`source/`），三棵树共用同一份；
 * 一旦它 import 了 `backend.*` / `states.*` / `objects.*`，切到原版或 0.6.3 之后就会
 * 变成「本体的代码在别的树里跑」，资源路径也会跟着跑到 `assets/body`。
 *
 * 目录约定：`source/` = 公共层，`source_body/body/` = 改版 1.0.4，`source_vanilla/vanilla/`、
 * `source_063/pe063/` = 另外两棵树。公共层只允许依赖 flixel / lime / std。
 */
class Main
{
	public static function main():Void
	{
		// 崩溃拦截必须在分叉之前装：三棵树共用同一个入口，装在这儿三边都覆盖到。
		backend.EngineCrash.install();

		// engine.txt 在 bin 根目录：vanilla 走原版 1.0.4，pe063 走 0.6.3，其他一律走本体
		if (Engine.isVanilla())
		{
			Lib.current.addChild(new vanilla.Main());
			return;
		}

		if (Engine.isPe063())
		{
			#if desktop
			// 0.6.3 树的路径探针：不进游戏、不建 state，跑完直接退。用法见 pe063/debug/Probe.hx
			var probe:Null<String> = Sys.getEnv('PE_063_PROBE');
			if (probe != null && probe == '1')
			{
				pe063.debug.Probe.run();
				return;
			}
			#end
			Lib.current.addChild(new pe063.Main());
			return;
		}

		Lib.current.addChild(new body.Main());
	}
}
