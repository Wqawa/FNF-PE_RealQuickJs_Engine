package jsruntime;

import psychlua.IScriptHost;

// One object per .js file: handle, path and owning mod together, like Lua's lua_State.
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

		// Global of this script: typed values, undefined = null. Script-local, not
	// MusicBeatState.variables (the shared setVar/getVar space).
	public function getVar(name:String):Dynamic
	{
		if (closed || !QuickJSHandler.isReady(handle)) return null;
		return QuickJSHandler.getGlobal(handle, name);
	}

	// QuickJS shares one heap across every context, so a single file can't own a number.
	public function scriptBytes():Float return 0;

	public function shutdown():Void
	{
		if (closed) return;
		closed = true;
		QuickJSHandler.dispose(handle);
	}
}
