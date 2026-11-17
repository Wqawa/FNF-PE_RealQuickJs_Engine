package jsruntime;

import psychlua.IScriptHost;

/**
 * Where a .js file lives inside QuickJS.
 *
 * JSPlayer used to keep handle and path in two parallel arrays, with ownership,
 * dedupe and dispatch all index-aligned: adding a script meant touching three arrays.
 * As an object each script carries its own handle, path and owning mod, matching
 * the one-file-one-lua_State shape on the Lua side.
 */
class JSScriptHost implements IScriptHost
{
	public var handle:Int;
	public var path:String;
	public var modFolder:String;
	public var closed:Bool = false;

	public function new(handle:Int, path:String, ?mod:String)
	{
		this.handle = handle;
		this.path = path;
		this.modFolder = mod;
	}

	// ------------------------------------------------------------- IScriptHost
	public function scriptId():String return path;
	public function scriptMod():String return modFolder;
	public function isClosed():Bool return closed;

	public function emit(func:String, args:Array<Dynamic>):Dynamic
		return JSPlayer.emitTo(this, func, args);

	public function setVar(name:String, value:Dynamic):Void
	{
		if (!closed) QuickJSHandler.setGlobal(handle, name, value);
	}

	/**
	 * Reads a global of this script. Numbers/booleans/strings come back typed; undefined is null.
	 * Like Lua, this is script-local state, not MusicBeatState.variables
	 * (that is the shared setVar/getVar space the host functions use).
	 */
	public function getVar(name:String):Dynamic
	{
		if (closed || !QuickJSHandler.isReady(handle)) return null;
		return QuickJSHandler.getGlobal(handle, name);
	}

	public function shutdown():Void
	{
		if (closed) return;
		closed = true;
		QuickJSHandler.dispose(handle);
	}
}
