package backend;

#if sys
import sys.FileSystem;
#end

// Writable cwd for all three trees: saves/mods/logs land in the same folder.
// Android: public /sdcard/RealQuickJS when the player granted all-files access,
// otherwise the app's own external dir (no permission needed, still reachable over USB).
class MobileStorage
{
	// dot folder, stays out of the way (app-private dirs only)
	public static inline var FOLDER:String = '.realQuickJSEngine';
	// visible name, used under /sdcard so players can find it in any file manager
	public static inline var PUBLIC_NAME:String = 'RealQuickJS';

	static var resolved:String;

	// sets cwd, returns it with a trailing slash
	public static function init():String
	{if sys
		return Sys.getCwd();
		return '';
	}


	static inline function withSlash(path:String):String
	{
		if (path == null || path.length == 0)
			return '';

		var last:String = path.charAt(path.length - 1);
		return (last == '/' || last == '\\') ? path : path + '/';
	}
}
