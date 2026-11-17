package pe063.debug;

import openfl.utils.AssetType;
import pe063.Paths;
import pe063.animateatlas.AtlasFrameMaker;
import sys.FileSystem;
import sys.io.File;

/**
 * 0.6.3 树的路径探针。
 *
 * `PE_063_PROBE=1` 时 `Main.main()` 不进游戏，只跑这里：把 lua `texture` 模式
 * （AtlasFrameMaker）用到的几组路径算出来、真的构造一次图集，结果写到
 * `.workbuddy/testout/pe063_probe.txt` 然后退出。
 *
 * 为什么要它：这棵树没有自动测试入口（测试补丁挂在 body 的 Main.main 分支上），
 * 改完 Paths / 图集之后没法验证，只能靠这个探针。它不建窗口、不出声。
 */
class Probe
{
	static var out:StringBuf;

	static function log(s:String)
	{
		out.add(s + '\n');
		Sys.println('[probe] ' + s);
	}

	static final OUT_PATH:String = 'D:/FNF/FNF-PE_RealQuickJs_Engine/.workbuddy/testout/pe063_probe.txt';

	public static function run():Void
	{
		// lime 的窗口在 main() 之前就建好了，先藏起来再干活，别在桌面上闪一下
		try lime.app.Application.current.window.visible = false catch (e:Dynamic) {}

		out = new StringBuf();
		var oldLevel:String = Paths.currentLevel;
		var oldMod:String = Paths.currentModDirectory;

		// 1. 官方图集，靠 week 目录找（0.6.3 自己的调用方式）
		Paths.setCurrentLevel('week7');
		probeAtlas('cutscenes/stressPico');

		// 2. mod 里的图集（lua texture 模式的实际用法）：复制一份到 mods/0.6.3/probe
		var src:String = 'assets/0.6.3/week7/images/cutscenes/stressPico';
		var dst:String = 'mods/0.6.3/probe/images/characters/stressPico';
		try
		{
			FileSystem.createDirectory(dst);
			for (f in ['Animation.json', 'spritemap.json', 'spritemap.png'])
				File.saveBytes('$dst/$f', File.getBytes('$src/$f'));

			Paths.currentModDirectory = 'probe';
			Paths.setCurrentLevel('shared');
			probeAtlas('characters/stressPico');
		}
		catch (e:Dynamic)
			log('mod 场景准备失败: ' + e);

		// 3. 收尾：把探针造出来的 mod 删掉，别留在玩家的 mods 目录里
		Paths.currentModDirectory = oldMod;
		Paths.currentLevel = oldLevel;
		try
		{
			for (f in ['Animation.json', 'spritemap.json', 'spritemap.png'])
				FileSystem.deleteFile('$dst/$f');
			FileSystem.deleteDirectory(dst);
			FileSystem.deleteDirectory('mods/0.6.3/probe/images/characters');
			FileSystem.deleteDirectory('mods/0.6.3/probe/images');
			FileSystem.deleteDirectory('mods/0.6.3/probe');
		}
		catch (e:Dynamic)
			log('清理失败（不影响结论）: ' + e);

		File.saveContent(OUT_PATH, out.toString());
		Sys.exit(0);
	}

	static function probeAtlas(key:String):Void
	{
		log('--- key=' + key + '  level=' + Paths.currentLevel + '  mod=' + Paths.currentModDirectory);
		log('  fileExists(images/$key/spritemap.json) = ' + Paths.fileExists('images/$key/spritemap.json', AssetType.TEXT));
		log('  getTextFromFile(images/$key/Animation.json) != null = ' + (Paths.getTextFromFile('images/$key/Animation.json') != null));
		log('  getPath(images/$key/spritemap.png) = ' + Paths.getPath('images/$key/spritemap.png', AssetType.IMAGE));

		try
		{
			var frames = AtlasFrameMaker.construct(key);
			log('  construct = ' + (frames == null ? 'null' : frames.numFrames + ' frames'));
		}
		catch (e:Dynamic)
			log('  construct ERROR: ' + e);
	}
}
