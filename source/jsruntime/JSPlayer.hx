package jsruntime;

import backend.Mods;
import backend.Paths;
import haxe.Log;

/**
 * 把 .js 脚本装进 PlayState。
 *
 * 只做三件事：
 *   1. 进歌时按当前 mod 找 data/<歌名>/*.js 和 scripts/*.js，逐个 eval
 *   2. 跑 onCreatePost / onUpdatePost 两个回调（其余回调走同一机制后补）
 *   3. 每帧 pump() 让 Promise 能动
 *
 * 不碰原来那套玩笑解释器：只有 ClientPrefs.data.jsEngine == 'QuickJS' 才会走到这里。
 */
class JSPlayer
{
	public static var active:Bool = false;
	static var loaded:Bool = false;

	public static function reset():Void
	{
		active = false;
		loaded = false;
	}

	/** 进歌时调一次。song 是 SONG.song（文件名不带扩展）。 */
	public static function load(song:String):Void
	{
		if (ClientPrefs.data.jsEngine != 'QuickJS') return;
		if (!QuickJSHandler.init(128)) return;
		QuickJSHandler.installHostFunctions();

		var root:String = Paths.mods(Mods.currentModDirectory + '/');
		var dirs:Array<String> = [
			root + 'data/' + song,
			root + 'scripts'
		];

		var count:Int = 0;
		for (dir in dirs)
		{
			if (!sys.FileSystem.exists(dir) || !sys.FileSystem.isDirectory(dir)) continue;
			for (f in sys.FileSystem.readDirectory(dir))
			{
				if (!f.endsWith('.js')) continue;
				if (QuickJSHandler.evalFile(dir + '/' + f)) count++;
			}
		}

		active = true;
		loaded = count > 0;
		if (loaded) Log.trace('[js] 已装载 $count 个脚本（$song）', null);
		QuickJSHandler.callGlobal('onCreatePost');
	}

	/** 每帧调一次 */
	public static function update():Void
	{
		if (!active) return;
		QuickJSHandler.callGlobal('onUpdatePost');
		QuickJSHandler.pump();
	}
}
