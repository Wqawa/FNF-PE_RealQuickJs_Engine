package jsruntime;

import haxe.Log;
import backend.Conductor;
import flixel.FlxG;
import psychlua.LuaUtils;

// One context per .js file. PlayState calls FunkinJS.start(), which picks QuickJS here
// or the old transpile-to-Lua path. Events come through callOnScripts, globals stay per script,
// and beginSong() rebuilds every context for the next song.
class JSPlayer
{
	public static var active:Bool = false;
	public static var loadedAny:Bool = false;

	/** One per .js file, in load order. */
	static var scripts:Array<JSScriptHost> = [];

	/** timer_xxx / tween_xxx -> the script that created it; callbacks go to it only. */
	static var owners:Map<String, JSScriptHost> = [];

		// Free a context one frame late: unloading from a callback still has it on the C stack.
	static var pendingFree:Array<Int> = [];

	public static function beginSong():Void
	{
		disposeAll();
		QuickJSHandler.truncateLog('[js] song start, engine=' + ClientPrefs.data.jsEngine);
		active = (ClientPrefs.data.jsEngine == 'QuickJS');
	}

	static function disposeAll():Void
	{
		// Leftovers from last song's self-unload can be freed here, outside any callback.
		for (h in pendingFree) QuickJSHandler.dispose(h);
		pendingFree = [];
		for (s in scripts) s.shutdown();
		scripts = [];
		owners = [];
		loadedAny = false;
	}

	/** Loads a .js file: new context, host functions, seeded globals, then eval. */
	public static function loadFile(path:String):Bool
	{
		if (!active) return false;
		// Path dedupe goes through Paths.sameScript, same rule as the Lua and HScript channels.
		for (s in scripts)
			if (backend.Paths.sameScript(s.path, path)) return true;

		// 256MB is the whole runtime's budget shared by all contexts; one context never needs that.
		var h:Int = QuickJSHandler.newContext(256);
		if (h < 0)
		{
			QuickJSHandler.log('[error] could not create a context (more than 64 scripts?): ' + path);
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

		// onCreate is not in callOnScripts' queue: Lua calls it at the end of the FunkinLua
		// constructor, HScript when PlayState builds the instance. JS follows Lua: fire once
		// after loading, so scripts added at runtime get it too.
		QuickJSHandler.callGlobal(h, 'onCreate');
		return true;
	}

	/** Values a script can read from the start (Lua seeds the same set in FunkinLua). */
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

	/** Once per frame: release contexts queued last frame, then pump promises/microtasks. */
	public static function update():Void
	{
		// Before the active check: after switching the engine off, last frame's queue still frees.
		if (pendingFree.length > 0)
		{
			for (h in pendingFree) QuickJSHandler.dispose(h);
			pendingFree = [];
		}
		if (!active) return;
		QuickJSHandler.pump();
	}

	// ---------------------------------------------------------------- dispatch
		// Events from callOnScripts. Returns the first non-Continue so Function_Stop still works.
	public static function forward(name:String, args:Array<Dynamic>):Dynamic
	{
		if (!active) return null;
		var ret:Dynamic = null;
		for (s in scripts)
		{
			var v:Dynamic = emitTo(s, name, args);
			if (v == null || v == LuaUtils.Function_Continue) continue;
			ret = v;
			// One script stopping also stops the rest of this channel, same as Lua's break.
			if (v == LuaUtils.Function_Stop || v == LuaUtils.Function_StopLua || v == LuaUtils.Function_StopAll) break;
		}
		return ret;
	}

		// One script: args go over the string/number bridge in a few fixed shapes, max three.
	// Sentinels come back as strings; no return is null.
	public static function emitTo(host:JSScriptHost, name:String, args:Array<Dynamic>):Dynamic
	{
		if (!active || host == null || host.closed || !QuickJSHandler.isReady(host.handle)) return null;

		// timed here rather than in JSScriptHost.emit: forward() comes straight in too
		var t0:Float = debug.Perf.begin();

		var n:Int = (args == null) ? 0 : args.length;
		if (n == 0 || args[0] == null)
		{
			QuickJSHandler.callGlobal(host.handle, name);
		}
		else if (n >= 2 && isNumArg(args[1]))
		{
			if (n >= 3 && isNumArg(args[2]))
				QuickJSHandler.callGlobalStrNumNum(host.handle, name, Std.string(args[0]), numArg(args[1]), numArg(args[2]));
			else
				QuickJSHandler.callGlobalStrNum(host.handle, name, Std.string(args[0]), numArg(args[1]));
		}
		else if (n >= 2)
		{
			QuickJSHandler.callGlobalStrStr(host.handle, name, Std.string(args[0]), Std.string(args[1]));
		}
		else if (isNumArg(args[0]))
		{
			QuickJSHandler.callGlobalNum(host.handle, name, numArg(args[0]));
		}
		else
		{
			QuickJSHandler.callGlobalStr(host.handle, name, Std.string(args[0]));
		}

		var ret:String = QuickJSHandler.lastReturn();
		var out:Dynamic = (ret == null || ret.length == 0) ? null : QuickJSHandler.coerce(ret);
		debug.Perf.end(host, t0);
		return out;
	}

	static inline function isNumArg(v:Dynamic):Bool
		return v != null && (Std.isOfType(v, Int) || Std.isOfType(v, Float));

	static inline function numArg(v:Dynamic):Float
		return cast v;

	/** runTimer callback: only to the script that created it, or everyone if unknown. */
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

	/** Tween completion: same rule. */
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

	/** Records which script owns a timer/tween. */
	public static function registerOwner(key:String, h:Int):Void
	{
		var host:JSScriptHost = hostOf(h);
		if (host != null) owners.set(key, host);
	}

		// Unload: unbind, drop ownership, free. Self-unload waits a frame via pendingFree.
	public static function unloadFile(name:String):Bool
	{
		var host:JSScriptHost = find(name);
		if (host == null) return false;

		scripts.remove(host);
		host.closed = true;
		if (scripts.length == 0) loadedAny = false;

		// Drop its timer/tween ownership too, otherwise callbacks reach a dead host.
		var dead:Array<String> = [];
		for (k in owners.keys())
			if (owners.get(k) == host) dead.push(k);
		for (k in dead) owners.remove(k);

		if (host.handle == QuickJSHandler.current())
		{
			pendingFree.push(host.handle);
			QuickJSHandler.log('[script] deferred unload (inside a callback) ' + host.path);
		}
		else QuickJSHandler.dispose(host.handle);

		QuickJSHandler.log('[script] unload ' + host.path + ' (ctx=' + host.handle + ')');
		return true;
	}

	/** Path or file name -> script. Exact first (case and slashes ignored), then tail match. */
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

	// ---------------------------------------------------------------- queries
	static function hostOf(h:Int):JSScriptHost
	{
		for (s in scripts)
			if (s.handle == h) return s;
		return null;
	}

	/** Handle -> script, so host functions know who is calling (getModSetting / close / ignoreSelf). */
	public static function hostOfHandle(h:Int):JSScriptHost
		return hostOf(h);

	/** Script path or name -> context handle (-1 when not running). */
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

	/** For PlayState's unified script list. Returns the internal array: read only. */
	public static function hosts():Array<JSScriptHost>
		return scripts;
}
