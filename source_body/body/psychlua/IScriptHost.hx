package psychlua;

/**
 * Common contract for the three script channels (Lua / HScript / QuickJS).
 *
 * Why it exists: PlayState used to walk three separate lists - luaArray, hscriptArray
 * and JSPlayer's parallel handle/path arrays. Every new event callback had to remember
 * all three, and missing one looked like "this event only reaches Lua".
 * The interface funnels "send one callback to one script" into a single method.
 *
 * Channel differences are not flattened; each stays inside its own emit:
 *   - Lua     : call directly; a missing callback is reported by call via luaTrace
 *   - HScript : exists() then call(), reading IrisCall.returnValue
 *   - QuickJS : callGlobal; undefined callbacks are swallowed by QuickJS itself
 *
 * Stop semantics (Function_StopLua / StopHScript / StopAll) are not part of the interface:
 * which sentinel stops which channel is a channel property, decided by the dispatcher.
 *
 * Methods rather than fields on purpose: the three implementations already expose
 * scriptName / origin / modFolder / closed, and a property interface would fight their
 * ownership and mutability. The prefixed names (scriptId / scriptMod) avoid clashes.
 */
interface IScriptHost
{
	/** Stable id for logs and exclusions, usually the full script path. */
	public function scriptId():String;

	/** Owning mod, null when not in a mod (mods root, shared, assets). */
	public function scriptMod():String;

	/** Closed: dispatch skips it. */
	public function isClosed():Bool;

	/** Fires a callback. Returns null when the script does not define it, never throws. */
	public function emit(func:String, args:Array<Dynamic>):Dynamic;

	/** Assigns a global in the script. */
	public function setVar(name:String, value:Dynamic):Void;

	/** Reads a global from the script, null when missing. */
	public function getVar(name:String):Dynamic;

	/** Ends and releases resources; isClosed() is true afterwards. */
	public function shutdown():Void;
}
