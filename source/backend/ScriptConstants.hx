package backend;

/**
 * Constants shared by every script host (Lua / HScript / JS) across all three trees.
 *
 * This lives in the shared layer on purpose: `source/` may only depend on flixel / lime /
 * std, never on a tree's own classes. So this file holds plain strings and arrays only -
 * no references to PlayState, Paths, ClientPrefs, or any tree-private type.
 *
 * Values here are read at compile time where possible (`static inline`), so there is no
 * runtime cost and no risk of three copies drifting apart.
 */
class ScriptConstants
{
	// ------------------------------------------------------------ stop sentinels
	// A script returns one of these to stop callback dispatch. LuaUtils (both 1.0 trees)
	// and the QuickJS bridge all compare against the same strings; PlayState compares
	// the raw string. Keep the JS wrapper below in sync via interpolation - never retype.
	public static inline var Function_Stop:String = "##PSYCHLUA_FUNCTIONSTOP";
	public static inline var Function_Continue:String = "##PSYCHLUA_FUNCTIONCONTINUE";
	public static inline var Function_StopLua:String = "##PSYCHLUA_FUNCTIONSTOPLUA";
	public static inline var Function_StopHScript:String = "##PSYCHLUA_FUNCTIONSTOPHSCRIPT";
	public static inline var Function_StopAll:String = "##PSYCHLUA_FUNCTIONSTOPALL";

	// The 0.6.3 tree deliberately does NOT use these: it kept the original numeric
	// sentinels (Stop=1 / Continue=0 / StopLua=2) that its PlayState compares as Ints.
	// Changing that would break every 0.6.3 mod, so it stays self-contained.

	// ------------------------------------------------------- body engine packages
	// Prefixes of classes owned by the modified 1.0.4 tree. When vanilla / 0.6.3
	// resolve a bare name and land on one of these, they must return null instead -
	// the body class's hardcoded Paths would silently pull assets/body.
	// This is the one list all three trees agree on, so it has one home here.
	public static final ENGINE_PACKAGE_PREFIXES:Array<String> = [
		'backend.', 'states.', 'objects.', 'options.', 'substates.', 'psychlua.',
		'shaders.', 'cutscenes.', 'flxanimate.', 'debug.', 'unused.',
		'mobile.', 'hxcodec.', 'vlc.'
	];

	/** True when a fully-qualified class name belongs to another tree's engine family. */
	public static function isEngineClass(fqn:String):Bool
	{
		if (fqn == null) return false;
		for (pkg in ENGINE_PACKAGE_PREFIXES)
			if (fqn.indexOf(pkg) == 0) return true;
		return false;
	}

	// ------------------------------------------------------------- log locations
	// All three hosts write callback/script logs to the same place. Centralised so a
	// test harness change only needs one edit.
	public static inline var LOG_DIR:String = './testout';
	public static inline var SCRIPT_LOG:String = './testout/js_log.txt';
	public static inline var STAGE_DEBUG_LOG:String = './testout/stage_dbg.txt';
}
