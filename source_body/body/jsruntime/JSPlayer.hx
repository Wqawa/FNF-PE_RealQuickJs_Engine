package jsruntime;

import haxe.Log;
import backend.Conductor;
import flixel.FlxG;
import psychlua.LuaUtils;

/**
 * Runtime state for .js scripts. One context per file, mirroring one interpreter per Lua file.
 *
 * Loading starts at psychlua.FunkinJS.start() (PlayState calls it for every .js it finds),
 * which branches on Gameplay -> JS Engine: QuickJS goes to loadFile() here,
 * otherwise the old transpile-to-Lua path is used.
 *
 * Callbacks ride PlayState.callOnScripts(), the one place every event already goes through,
 * and are forwarded to each context here; no hooks scattered around PlayState.
 *
 * Contexts are isolated: one script defining onCreatePost does not shadow another's,
 * and globals are per script (getGlobalFromScript / setGlobalFromScript locate by handleOf).
 * Everything is disposed on beginSong() and rebuilt for the next song.
 *
 * 2026-11 rework: handle and path were two parallel arrays; now one Array<JSScriptHost>,
 * each entry carrying its owning mod, so PlayState sends events through IScriptHost.
 */
class JSPlayer
{
	public static var active:Bool = false;
	public static var loadedAny:Bool = false;

	/** One per .js file, in load order. */
	static var scripts:Array<JSScriptHost> = [];

	/** timer_xxx / tween_xxx -> the script that created it; callbacks go to it only. */
	static var owners:Map<String, JSScriptHost> = [];

	/**
	 * Handles waiting for JS_FreeContext on the next frame.
	 * When a script unloads another (or itself) from a callback, that context is still on
	 * the C stack; freeing it there is a use-after-free and did crash. Defer one frame.
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
			QuickJSHandler.log('[error] could not create a context (more than 32 scripts?): ' + path);
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
	/**
	 * Events forwarded from PlayState.callOnScripts(), sent to every script.
	 * Returns the first non-Continue value so callers see Function_Stop - otherwise
	 * "JS asked to stop" never worked (this used to be dropped).
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
			// One script stopping also stops the rest of this channel, same as Lua's break.
			if (v == LuaUtils.Function_Stop || v == LuaUtils.Function_StopLua || v == LuaUtils.Function_StopAll) break;
		}
		return ret;
	}

	/**
	 * Sends to a single script. Arguments are dispatched as zero args / number / string.
	 * The return value is whatever the script returned: sentinels come back as strings,
	 * true/false/numbers are coerced back, and no return means null.
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

	/**
	 * Unloads a .js (removeLuaScript / removeHScript).
	 * One context per file makes this possible: unbind, drop timer/tween ownership, free it.
	 * The one trap is unloading yourself from a callback; hand it to pendingFree for a frame.
	 */
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
