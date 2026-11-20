package backend;

#if sys
import sys.FileSystem;
#end

// Writable cwd for all three trees: saves/mods/logs land in the same folder.
// Android: prefer external app files so players can drop mods in over USB; desktop does nothing.
class MobileStorage
{
	// dot folder, stays out of the way
	public static inline var FOLDER:String = '.realQuickJSEngine';

	static var resolved:String;

	// sets cwd, returns it with a trailing slash
	public static function init():String
	{
		#if (android || ios)
		if (resolved != null)
			return resolved;

		var base:String = pickBase();
		var root:String = withSlash(base) + FOLDER + '/';

		try
		{
			if (!FileSystem.exists(root))
				FileSystem.createDirectory(root);
		}
		catch (e:Dynamic)
		{
			// can't create it? fall back to the base dir, just keep the game running
			trace('MobileStorage: cannot create "$root" ($e), falling back to "$base"');
			root = withSlash(base);
		}

		Sys.setCwd(root);
		resolved = root;
		trace('MobileStorage: cwd = $root');
		return root;
		#elseif sys
		return Sys.getCwd();
		#else
		return '';
		#end
	}

	#if (android || ios)
	static function pickBase():String
	{
		#if android
		// lime's documentsDirectory is usually getExternalFilesDir() on Android, but it
		// can point at public Documents - check the path itself, else use internal storage.
		try
		{
			var ext:String = lime.system.System.documentsDirectory;
			if (ext != null && ext.indexOf('/Android/data/') >= 0)
				return ext;
		}
		catch (e:Dynamic) {}
		#end

		return lime.system.System.applicationStorageDirectory;
	}

	static inline function withSlash(path:String):String
	{
		if (path == null || path.length == 0)
			return '';

		var last:String = path.charAt(path.length - 1);
		return (last == '/' || last == '\\') ? path : path + '/';
	}
	#end
}
