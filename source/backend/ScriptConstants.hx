package backend;

// Strings every script host uses. Keep this tree-free: source/ only sees flixel/std.
class ScriptConstants
{
	// stop sentinels, keep the JS wrapper in sync
	public static inline var Function_Stop:String = "##PSYCHLUA_FUNCTIONSTOP";
	public static inline var Function_Continue:String = "##PSYCHLUA_FUNCTIONCONTINUE";
	public static inline var Function_StopLua:String = "##PSYCHLUA_FUNCTIONSTOPLUA";
	public static inline var Function_StopHScript:String = "##PSYCHLUA_FUNCTIONSTOPHSCRIPT";
	public static inline var Function_StopAll:String = "##PSYCHLUA_FUNCTIONSTOPALL";

	// 0.6.3 keeps its own numeric sentinels, don't touch that tree

	// prefixes of the body engine classes, shared by all three trees
	public static final ENGINE_PACKAGE_PREFIXES:Array<String> = [
		'backend.', 'states.', 'objects.', 'options.', 'substates.', 'psychlua.',
		'shaders.', 'cutscenes.', 'flxanimate.', 'debug.', 'unused.',
		'mobile.', 'hxcodec.', 'vlc.'
	];

	public static function isEngineClass(fqn:String):Bool
	{
		if (fqn == null) return false;
		for (pkg in ENGINE_PACKAGE_PREFIXES)
			if (fqn.indexOf(pkg) == 0) return true;
		return false;
	}

	// log files, all hosts write to the same place
	public static inline var LOG_DIR:String = './testout';
	public static inline var SCRIPT_LOG:String = './testout/js_log.txt';
	public static inline var STAGE_DEBUG_LOG:String = './testout/stage_dbg.txt';
}
