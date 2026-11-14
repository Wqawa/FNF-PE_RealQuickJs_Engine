package jsruntime;

import haxe.Log;

/**
 * .js 脚本的运行期状态：每首歌一个干净的 QuickJS context。
 *
 * 装载入口在 psychlua.FunkinJS.start()（PlayState 扫到 .js 就调它），
 * 它按 Gameplay → JS Engine 分流：QuickJS 就交给这里的 loadFile()，
 * 否则还是原来那套转译成 Lua 的玩笑解释器。
 *
 * context 一首歌一换：上一首的 onCreatePost / 全局变量留着的话，
 * 下一首会被莫名其妙地再调一遍，所以 beginSong() 先 dispose 再重建。
 */
class JSPlayer
{
	public static var active:Bool = false;
	public static var loadedAny:Bool = false;

	static var posted:Bool = false;
	static var loadedFiles:Array<String> = [];

	/** PlayState.create() 里、扫脚本之前调一次。 */
	public static function beginSong():Void
	{
		QuickJSHandler.dispose();
		active = false;
		loadedAny = false;
		posted = false;
		loadedFiles = [];

		if (ClientPrefs.data.jsEngine != 'QuickJS') return;
		// 128MB 上限：mod 脚本正常用不到，跑飞的分配会在这里被掐掉
		if (!QuickJSHandler.init(128)) return;
		QuickJSHandler.installHostFunctions();
		active = true;
	}

	/** 装一个 .js 文件。同一份脚本不会重复 eval。 */
	public static function loadFile(path:String):Bool
	{
		if (!active) return false;
		if (loadedFiles.contains(path)) return true;
		if (!QuickJSHandler.evalFile(path)) return false;
		loadedFiles.push(path);
		loadedAny = true;
		Log.trace('[js] loaded $path', null);
		return true;
	}

	/** 每帧调一次。第一个 update 才发 onCreatePost，保证所有脚本都 eval 完。 */
	public static function update():Void
	{
		if (!active) return;
		if (!posted)
		{
			posted = true;
			QuickJSHandler.callGlobal('onCreatePost');
		}
		QuickJSHandler.callGlobal('onUpdatePost');
		QuickJSHandler.pump();
	}
}
