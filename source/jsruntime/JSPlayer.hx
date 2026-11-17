package jsruntime;

import haxe.Log;
import backend.Conductor;
import flixel.FlxG;
import psychlua.LuaUtils;

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
 *
 * 2026-11 改造：handle / path 原来是两个平行数组，现在收成 Array<JSScriptHost>，
 * 每个脚本自带归属 mod，PlayState 那边通过 IScriptHost 统一发事件。
 */
class JSPlayer
{
	public static var active:Bool = false;
	public static var loadedAny:Bool = false;

	/** 每个 .js 文件一个，顺序就是加载顺序 */
	static var scripts:Array<JSScriptHost> = [];

	/** timer_xxx / tween_xxx → 创建它的脚本，回调用它只发给本人 */
	static var owners:Map<String, JSScriptHost> = [];

	/**
	 * 等下一帧再 JS_FreeContext 的句柄。
	 * 脚本在回调里把某个脚本卸掉（包括卸自己）时，C 栈上还压着那个 context，
	 * 当场 free 是 use-after-free，实测直接崩。推进一帧再释放。
	 */
	static var pendingFree:Array<Int> = [];

	public static function beginSong():Void
	{
		disposeAll();
		QuickJSHandler.truncateLog('[js] song start, engine=' + ClientPrefs.data.jsEngine);
		active = (ClientPrefs.data.jsEngine == 'QuickJS');
	}

	static function disposeAll():Void
	{
		// 上一首里「自己卸自己」还没来得及释放的，趁现在不在任何回调里直接放掉
		for (h in pendingFree) QuickJSHandler.dispose(h);
		pendingFree = [];
		for (s in scripts) s.shutdown();
		scripts = [];
		owners = [];
		loadedAny = false;
	}

	/** 装一个 .js 文件：给它建一个独立 context，装宿主函数、预置全局，再 eval。 */
	public static function loadFile(path:String):Bool
	{
		if (!active) return false;
		// 路径判重走 Paths.sameScript（大小写 + 斜杠），和 Lua/HScript 两条通道同口径
		for (s in scripts)
			if (backend.Paths.sameScript(s.path, path)) return true;

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

		var modName:String = backend.Paths.modFromScriptPath(path);
		scripts.push(new JSScriptHost(h, path, modName));
		loadedAny = true;
		Log.trace('[js] loaded $path (ctx=$h)', null);
		QuickJSHandler.log('[script] js/qjs  mod=' + (modName == null ? '<global>' : modName) + '  ' + path + ' (ctx=' + h + ')');

		// onCreate 不在 callOnScripts 的队列里 —— Lua 是在 FunkinLua 构造末尾自己调的
		// （FunkinLua.hx:1714），HScript 是 PlayState 建实例时调的。JS 这边照 Lua 的做法，
		// 装载完成就发一次，运行时 addLuaScript 进来的脚本也能立刻拿到。
		QuickJSHandler.callGlobal(h, 'onCreate');
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

	/** 每帧调一次：先放掉上一帧排队等释放的 context，再推 Promise / microtask */
	public static function update():Void
	{
		// 放在 active 判断之前：换歌关掉 QuickJS 之后，上一帧遗留的还得放掉
		if (pendingFree.length > 0)
		{
			for (h in pendingFree) QuickJSHandler.dispose(h);
			pendingFree = [];
		}
		if (!active) return;
		QuickJSHandler.pump();
	}

	// ---------------------------------------------------------------- 回调分发
	/**
	 * PlayState.callOnScripts() 转过来的事件，发给每个脚本。
	 * 返回第一个非 Continue 的返回值：脚本 return Function_Stop 之类要让调用方看见，
	 * 否则「JS 喊停」永远无效（以前这里正是丢掉的）。
	 */
	public static function forward(name:String, args:Array<Dynamic>):Dynamic
	{
		if (!active) return null;
		var ret:Dynamic = null;
		for (s in scripts)
		{
			var v:Dynamic = emitTo(s, name, args);
			if (v == null || v == LuaUtils.Function_Continue) continue;
			ret = v;
			// 一个脚本喊停，后面那些同通道的也不发了（和 Lua 那边 break 一致）
			if (v == LuaUtils.Function_Stop || v == LuaUtils.Function_StopLua || v == LuaUtils.Function_StopAll) break;
		}
		return ret;
	}

	/**
	 * 发给单个脚本。参数分派还是零参 / 数字 / 字符串三种。
	 * 返回值是脚本 return 的东西：字符串化的哨兵（Function_Stop 等）原样返回，
	 * true/false/数字会被还原成对应类型（coerce），没 return 就是 null。
	 */
	public static function emitTo(host:JSScriptHost, name:String, args:Array<Dynamic>):Dynamic
	{
		if (!active || host == null || host.closed || !QuickJSHandler.isReady(host.handle)) return null;

		var hasArg:Bool = (args != null && args.length > 0 && args[0] != null);
		var a:Dynamic = hasArg ? args[0] : null;
		var isNum:Bool = hasArg && (Std.isOfType(a, Int) || Std.isOfType(a, Float));

		if (!hasArg) QuickJSHandler.callGlobal(host.handle, name);
		else if (isNum) QuickJSHandler.callGlobalNum(host.handle, name, cast a);
		else QuickJSHandler.callGlobalStr(host.handle, name, Std.string(a));

		var ret:String = QuickJSHandler.lastReturn();
		if (ret == null || ret.length == 0) return null;
		return QuickJSHandler.coerce(ret);
	}

	/** runTimer 的回调：只发给创建这个 timer 的脚本；找不到就全发 */
	public static function onTimerCompleted(tag:String, loops:Int, loopsLeft:Int):Void
	{
		if (!active) return;
		var host:JSScriptHost = owners.exists('timer_' + tag) ? owners.get('timer_' + tag) : null;
		if (host != null && !host.closed && QuickJSHandler.isReady(host.handle))
		{
			QuickJSHandler.callGlobalStrNumNum(host.handle, 'onTimerCompleted', tag, loops, loopsLeft);
			return;
		}
		for (s in scripts)
			if (!s.closed && QuickJSHandler.isReady(s.handle))
				QuickJSHandler.callGlobalStrNumNum(s.handle, 'onTimerCompleted', tag, loops, loopsLeft);
	}

	/** tween 完成回调：同样的规则 */
	public static function onTweenCompleted(tag:String, vars:String):Void
	{
		if (!active) return;
		var host:JSScriptHost = owners.exists('tween_' + tag) ? owners.get('tween_' + tag) : null;
		if (host != null && !host.closed && QuickJSHandler.isReady(host.handle))
		{
			QuickJSHandler.callGlobalStrStr(host.handle, 'onTweenCompleted', tag, vars);
			return;
		}
		for (s in scripts)
			if (!s.closed && QuickJSHandler.isReady(s.handle))
				QuickJSHandler.callGlobalStrStr(s.handle, 'onTweenCompleted', tag, vars);
	}

	/** 记录某个 timer/tween 是哪个脚本建的 */
	public static function registerOwner(key:String, h:Int):Void
	{
		var host:JSScriptHost = hostOf(h);
		if (host != null) owners.set(key, host);
	}

	/**
	 * 卸掉一个 .js（removeLuaScript / removeHScript）。
	 * 一文件一 context 之后这事能做了：解绑、清掉它的 timer/tween 归属、放掉 context。
	 * 唯一要小心的就是「卸自己在回调里」—— 那时 C 栈还用着这个 ctx，交给 pendingFree 延一帧。
	 */
	public static function unloadFile(name:String):Bool
	{
		var host:JSScriptHost = find(name);
		if (host == null) return false;

		scripts.remove(host);
		host.closed = true;
		if (scripts.length == 0) loadedAny = false;

		// 它建的 timer / tween 归属一起断掉，不然回调还会发给一个死掉的 host
		var dead:Array<String> = [];
		for (k in owners.keys())
			if (owners.get(k) == host) dead.push(k);
		for (k in dead) owners.remove(k);

		if (host.handle == QuickJSHandler.current())
		{
			pendingFree.push(host.handle);
			QuickJSHandler.log('[script] 延迟卸载（正在回调里）' + host.path);
		}
		else QuickJSHandler.dispose(host.handle);

		QuickJSHandler.log('[script] 卸载 ' + host.path + ' (ctx=' + host.handle + ')');
		return true;
	}

	/** 路径 / 文件名 → 脚本。先精确（忽略大小写和斜杠方向），再按尾部匹配。 */
	static function find(name:String):JSScriptHost
	{
		if (name == null || name.length == 0) return null;
		var want:String = normPath(name);
		for (s in scripts)
			if (normPath(s.path) == want) return s;
		for (s in scripts)
			if (normPath(s.path).endsWith('/' + want)) return s;
		return null;
	}

	static inline function normPath(p:String):String
		return p.split('\\').join('/').toLowerCase();

	// ---------------------------------------------------------------- 查询
	static function hostOf(h:Int):JSScriptHost
	{
		for (s in scripts)
			if (s.handle == h) return s;
		return null;
	}

	/** 句柄 → 脚本。宿主函数里要用它判断「谁在调我」（getModSetting / close / setOnScripts 的 ignoreSelf）。 */
	public static function hostOfHandle(h:Int):JSScriptHost
		return hostOf(h);

	/** 脚本路径/文件名 → context 句柄（-1 表示没在跑） */
	public static function handleOf(name:String):Int
	{
		var host:JSScriptHost = find(name);
		return (host != null) ? host.handle : -1;
	}

	public static function isLoaded(path:String):Bool
	{
		if (path == null) return false;
		for (s in scripts)
			if (backend.Paths.sameScript(s.path, path)) return true;
		return false;
	}

	public static function getLoadedFiles():Array<String>
	{
		var out:Array<String> = [];
		for (s in scripts) out.push(s.path);
		return out;
	}

	/** 给 PlayState 拼统一脚本列表用。直接返回内部数组，调用方只读，不要改。 */
	public static function hosts():Array<JSScriptHost>
		return scripts;
}
