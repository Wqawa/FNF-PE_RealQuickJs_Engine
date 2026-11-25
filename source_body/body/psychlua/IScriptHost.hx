package psychlua;

// One emit per callback so PlayState walks a single script list instead of three.
// Each channel keeps its own call style inside emit; stop sentinels stay with the dispatcher.
interface IScriptHost
{
	// Stable id for logs and exclusions, usually the full script path.
	public function scriptId():String;

	// Owning mod, null when not in a mod (mods root, shared, assets).
	public function scriptMod():String;

	// Closed: dispatch skips it.
	public function isClosed():Bool;

	// Fires a callback. Returns null when the script does not define it, never throws.
	public function emit(func:String, args:Array<Dynamic>):Dynamic;

	// Assigns a global in the script.
	public function setVar(name:String, value:Dynamic):Void;

	// Reads a global from the script, null when missing.
	public function getVar(name:String):Dynamic;

	// Bytes this script's own runtime is holding. 0 when it can't be measured.
	public function scriptBytes():Float;

	// Ends and releases resources; isClosed() is true afterwards.
	public function shutdown():Void;
}
