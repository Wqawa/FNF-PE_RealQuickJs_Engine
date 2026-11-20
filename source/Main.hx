package;

import openfl.Lib;

// Entry point: install crash handler, read engine.txt, attach that tree's Sprite.
// Shared layer - only flixel/lime/std here, never a tree's classes.
class Main
{
	public static function main():Void
	{
		// The crash handler must be installed before the fork: one entry, all three trees.
		backend.EngineCrash.install();

		#if (android || ios)
		// 先把 cwd 定下来。Engine 读 engine.txt 用的是当前目录，而写入发生在游戏跑起来
		// 之后（那时 cwd 已经是 MobileStorage 设的），两边对不上就会「切了没反应」。
		backend.MobileStorage.init();

		// 兜底键盘的悬浮球。挂在 stage 上，跟树无关，所以三棵树都能用
		backend.DebugKeyboard.install();
		#end

		// engine.txt: vanilla = original 1.0.4, pe063 = 0.6.3, anything else = body
		// on Android the apk copy is read-only; Engine also tries the writable cwd
		if (Engine.isVanilla())
		{
			Lib.current.addChild(new vanilla.Main());
			return;
		}

		if (Engine.isPe063())
		{
			Lib.current.addChild(new pe063.Main());
			return;
		}

		Lib.current.addChild(new body.Main());
	}
}
