package jsruntime;

import haxe.Log;
import backend.Conductor;

/**
 * .js 脚本的运行期状态：每首歌一个干净的 QuickJS context。
 *
 * 装载入口在 psychlua.FunkinJS.start()（PlayState 扫到 .js 就调它），
 * 它按 Gameplay → JS Engine 分流：QuickJS 就交给这里的 loadFile()，
 * 否则还是原来那套转译成 Lua 的玩笑解释器。
 *
 * 回调走 PlayState.callOnScripts() 那条主路 —— 那边每处事件都已经在调它，
 * 在这里转发一份给 JS，就不用往 PlayState 里到处插钩子，也不会漏。
 *
 * context 一首歌一换：上一首的 onCreatePost / 全局变量留着的话，
 * 下一首会被莫名其妙地再调一遍，所以 beginSong() 先 dispose 再重建。
 */
class JSPlayer
{
	public static var active:Bool = false;
	public static var loadedAny:Bool = false;

	static var loadedFiles:Array<String> = [];

	/** PlayState.create() 里、扫脚本之前调一次。 */
	public static function beginSong():Void
	{
		QuickJSHandler.dispose();
		active = false;
		loadedAny = false;
		loadedFiles = [];

		QuickJSHandler.truncateLog('[js] song start, engine=' + ClientPrefs.data.jsEngine);
		if (ClientPrefs.data.jsEngine != 'QuickJS') return;
		// 128MB 上限：mod 脚本正常用不到，跑飞的分配会在这里被掐掉
		if (!QuickJSHandler.init(128)) return;
		QuickJSHandler.installHostFunctions();

		// Lua 脚本创建时就能读这些（FunkinLua 在 create 里塞了一份），
		// JS 侧不预置的话，onCreatePost / onSongStart 里读 curBeat 会直接 ReferenceError
		QuickJSHandler.setGlobal('curBeat', 0);
		QuickJSHandler.setGlobal('curStep', 0);
		QuickJSHandler.setGlobal('curSection', 0);
		QuickJSHandler.setGlobal('curBpm', Conductor.bpm);
		QuickJSHandler.setGlobal('bpm', Conductor.bpm);
		QuickJSHandler.setGlobal('crochet', Conductor.crochet);
		QuickJSHandler.setGlobal('stepCrochet', Conductor.stepCrochet);
		QuickJSHandler.setGlobal('songLength', (FlxG.sound.music != null) ? FlxG.sound.music.length : 0);
		QuickJSHandler.setGlobal('score', 0);
		QuickJSHandler.setGlobal('misses', 0);
		QuickJSHandler.setGlobal('hits', 0);
		QuickJSHandler.setGlobal('rating', 0);
		QuickJSHandler.setGlobal('ratingName', '');
		QuickJSHandler.setGlobal('ratingFC', '');
		QuickJSHandler.setGlobal('mustHitSection', false);
		QuickJSHandler.setGlobal('altAnim', false);
		QuickJSHandler.setGlobal('gfSection', false);

		active = true;
	}

	/** 装一个 .js 文件。同一份脚本不会重复 eval。 */
	public static function loadFile(path:String):Bool
	{
		if (!active) return false;
		if (loadedFiles.contains(path)) return true;
		if (!QuickJSHandler.evalFile(path))
		{
			QuickJSHandler.log('[error] load failed: ' + path + ' -- ' + QuickJSHandler.lastError());
			return false;
		}
		loadedFiles.push(path);
		loadedAny = true;
		Log.trace('[js] loaded $path', null);
		QuickJSHandler.log('[load] ' + path);
		return true;
	}

	/** 每帧调一次：只推 Promise / microtask，回调本身由 callOnScripts 转过来。 */
	public static function update():Void
	{
		if (!active) return;
		QuickJSHandler.pump();
	}

	/**
	 * PlayState.callOnScripts() 转发过来的事件。
	 * 脚本里没定义这个函数时是空转（callGlobal 会先查是不是函数）。
	 */
	public static function forward(name:String, args:Array<Dynamic>):Void
	{
		if (!active) return;

		if (args == null || args.length == 0)
		{
			QuickJSHandler.callGlobal(name);
			return;
		}

		var a:Dynamic = args[0];
		if (a == null)
		{
			QuickJSHandler.callGlobal(name);
			return;
		}

		if (Std.isOfType(a, Int) || Std.isOfType(a, Float))
			QuickJSHandler.callGlobalNum(name, cast a);
		else
			QuickJSHandler.callGlobalStr(name, Std.string(a));
	}

	/** runTimer 的回调：onTimerCompleted(tag, loops, loopsLeft)，参数跟 Lua 一致 */
	public static function onTimerCompleted(tag:String, loops:Int, loopsLeft:Int):Void
	{
		if (!active) return;
		QuickJSHandler.callGlobalStrNumNum('onTimerCompleted', tag, loops, loopsLeft);
	}

	/** setOnScripts 同步：Lua 脚本能直接读 curBeat / score 这些，JS 也得有 */
	public static function setGlobal(name:String, v:Dynamic):Void
	{
		if (!active) return;
		QuickJSHandler.setGlobal(name, v);
	}

	/** doTween* 的回调：onTweenCompleted(tag, vars) */
	public static function onTweenCompleted(tag:String, vars:String):Void
	{
		if (!active) return;
		QuickJSHandler.callGlobalStrStr('onTweenCompleted', tag, vars);
	}
}
