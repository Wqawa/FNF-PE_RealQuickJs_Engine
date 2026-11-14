package jsruntime;

import haxe.Log;
import backend.Conductor;
import flixel.FlxG;

/**
 * .js 脚本的运行期状态。**一个文件一个 context**，跟 Lua「一个文件一个解释器」对齐。
 *
 * 装载入口在 psychlua.FunkinJS.start()（PlayState 扫到 .js 就调它），
 * 它按 Gameplay → JS Engine 分流：QuickJS 就交给这里的 loadFile()，
 * 否则还是原来那套转译成 Lua 的玩笑解释器。
 *
 * 回调走 PlayState.callOnScripts() 那条主路 —— 那边每处事件都已经在调它，
 * 在这里转发给每个脚本的 context，就不用往 PlayState 里到处插钩子，也不会漏。
 *
 * 每个 context 独立：A 脚本定义 onCreatePost 不会顶掉 B 脚本的同名函数，
 * 全局变量也各是各的（`getGlobalFromScript` / `setGlobalFromScript` 靠 handleOf 定位）。
 * 整首歌结束（beginSong）时全部 dispose，下一次重新建。
 */
class JSPlayer
{
	public static var active:Bool = false;
	public static var loadedAny:Bool = false;

	/** 句柄 + 文件路径 */
	static var handles:Array<Int> = [];
	static var paths:Array<String> = [];

	/** timer_xxx / tween_xxx → 创建它的 context，回调用它只发给本人 */
	static var owners:Map<String, Int> = [];

	public static function beginSong():Void
	{
		disposeAll();
		QuickJSHandler.truncateLog('[js] song start, engine=' + ClientPrefs.data.jsEngine);
		active = (ClientPrefs.data.jsEngine == 'QuickJS');
	}

	static function disposeAll():Void
	{
		for (h in handles) QuickJSHandler.dispose(h);
		handles = [];
		paths = [];
		owners = [];
		loadedAny = false;
	}

	/** 装一个 .js 文件：给它建一个独立 context，装宿主函数、预置全局，再 eval。 */
	public static function loadFile(path:String):Bool
	{
		if (!active) return false;
		for (i in 0...paths.length)
			if (paths[i] == path) return true;

		// 256MB 是整个 runtime 的上限，所有 context 共用；单个 context 不会吃这么多
		var h:Int = QuickJSHandler.newContext(256);
		if (h < 0)
		{
			QuickJSHandler.log('[error] 建不出新 context（超过 32 个脚本？）: ' + path);
			return false;
		}

		QuickJSHandler.installHostFunctions(h);
		seedGlobals(h);
		if (!QuickJSHandler.evalFile(h, path))
		{
			QuickJSHandler.log('[error] load failed: ' + path + ' -- ' + QuickJSHandler.lastError());
			QuickJSHandler.dispose(h);
			return false;
		}

		handles.push(h);
		paths.push(path);
		loadedAny = true;
		Log.trace('[js] loaded $path (ctx=$h)', null);
		var owner:String = backend.Paths.modFromScriptPath(path);
		QuickJSHandler.log('[script] js/qjs  mod=' + (owner == null ? '<global>' : owner) + '  ' + path + ' (ctx=' + h + ')');
		return true;
	}

	/** 脚本开局就能读到的那些量（Lua 在 FunkinLua.create 里塞过一份） */
	static function seedGlobals(h:Int):Void
	{
		QuickJSHandler.setGlobal(h, 'curBeat', 0);
		QuickJSHandler.setGlobal(h, 'curStep', 0);
		QuickJSHandler.setGlobal(h, 'curSection', 0);
		QuickJSHandler.setGlobal(h, 'curBpm', Conductor.bpm);
		QuickJSHandler.setGlobal(h, 'bpm', Conductor.bpm);
		QuickJSHandler.setGlobal(h, 'crochet', Conductor.crochet);
		QuickJSHandler.setGlobal(h, 'stepCrochet', Conductor.stepCrochet);
		QuickJSHandler.setGlobal(h, 'songLength', (FlxG.sound.music != null) ? FlxG.sound.music.length : 0);
		QuickJSHandler.setGlobal(h, 'score', 0);
		QuickJSHandler.setGlobal(h, 'misses', 0);
		QuickJSHandler.setGlobal(h, 'hits', 0);
		QuickJSHandler.setGlobal(h, 'rating', 0);
		QuickJSHandler.setGlobal(h, 'ratingName', '');
		QuickJSHandler.setGlobal(h, 'ratingFC', '');
		QuickJSHandler.setGlobal(h, 'mustHitSection', false);
		QuickJSHandler.setGlobal(h, 'altAnim', false);
		QuickJSHandler.setGlobal(h, 'gfSection', false);
	}

	/** 每帧调一次：只推 Promise / microtask */
	public static function update():Void
	{
		if (!active) return;
		QuickJSHandler.pump();
	}

	// ---------------------------------------------------------------- 回调分发
	/** PlayState.callOnScripts() 转过来的事件，发给每个脚本 */
	public static function forward(name:String, args:Array<Dynamic>):Void
	{
		if (!active) return;
		var hasArg:Bool = (args != null && args.length > 0 && args[0] != null);
		var a:Dynamic = hasArg ? args[0] : null;
		var isNum:Bool = hasArg && (Std.isOfType(a, Int) || Std.isOfType(a, Float));

		for (h in handles)
		{
			if (!hasArg) QuickJSHandler.callGlobal(h, name);
			else if (isNum) QuickJSHandler.callGlobalNum(h, name, cast a);
			else QuickJSHandler.callGlobalStr(h, name, Std.string(a));
		}
	}

	/** setOnScripts 同步：每个脚本的上下文都写一份 */
	public static function setGlobal(name:String, v:Dynamic):Void
	{
		if (!active) return;
		for (h in handles) QuickJSHandler.setGlobal(h, name, v);
	}

	/** runTimer 的回调：只发给创建这个 timer 的脚本；找不到就全发 */
	public static function onTimerCompleted(tag:String, loops:Int, loopsLeft:Int):Void
	{
		if (!active) return;
		var key:String = 'timer_' + tag;
		var h:Int = owners.exists(key) ? owners.get(key) : -1;
		if (h >= 0 && QuickJSHandler.isReady(h))
		{
			QuickJSHandler.callGlobalStrNumNum(h, 'onTimerCompleted', tag, loops, loopsLeft);
			return;
		}
		for (hh in handles) QuickJSHandler.callGlobalStrNumNum(hh, 'onTimerCompleted', tag, loops, loopsLeft);
	}

	/** tween 完成回调：同样的规则 */
	public static function onTweenCompleted(tag:String, vars:String):Void
	{
		if (!active) return;
		var h:Int = owners.exists('tween_' + tag) ? owners.get('tween_' + tag) : -1;
		if (h >= 0 && QuickJSHandler.isReady(h))
		{
			QuickJSHandler.callGlobalStrStr(h, 'onTweenCompleted', tag, vars);
			return;
		}
		for (hh in handles) QuickJSHandler.callGlobalStrStr(hh, 'onTweenCompleted', tag, vars);
	}

	/** 记录某个 timer/tween 是哪个脚本建的 */
	public static function registerOwner(key:String, h:Int):Void
	{
		if (h >= 0) owners.set(key, h);
	}

	// ---------------------------------------------------------------- 查询
	/** 脚本路径/文件名 → context 句柄（-1 表示没在跑） */
	public static function handleOf(name:String):Int
	{
		if (name == null || name.length == 0) return -1;
		var lower:String = name.toLowerCase();
		for (i in 0...paths.length)
		{
			var p:String = paths[i];
			var pl:String = p.toLowerCase();
			if (pl == lower || pl.endsWith('/' + lower) || pl.endsWith('\\' + lower)) return handles[i];
		}
		return -1;
	}

	public static function isLoaded(path:String):Bool
	{
		if (path == null) return false;
		if (handleOf(path) >= 0) return true;
		for (p in paths)
			if (p.toLowerCase() == path.toLowerCase()) return true;
		return false;
	}

	public static function getLoadedFiles():Array<String>
		return paths.copy();
}
