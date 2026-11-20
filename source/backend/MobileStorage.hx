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
		// can point at public Documents - check the path itself, else ask the system
		// directly, else fall back to internal storage.
		try
		{
			var ext:String = lime.system.System.documentsDirectory;
			if (ext != null && ext.indexOf('/Android/data/') >= 0)
				return ext;
		}
		catch (e:Dynamic) {}

		var own:String = externalFilesDir();
		if (own != null)
			return own;
		#end

		return lime.system.System.applicationStorageDirectory;
	}

	#if android
	// Context.getExternalFilesDir(null) -> /storage/emulated/0/Android/data/<pkg>/files
	// That's the directory adb and file managers can reach, so mods and saves stay
	// copyable. It needs no runtime permission. Some ROMs hand back the internal dir
	// from lime's documentsDirectory, hence the JNI call.
	static function externalFilesDir():String
	{
		try
		{
			var getContext:Dynamic = lime.system.JNI.createStaticMethod("org/libsdl/app/SDLActivity", "getContext", "()Landroid/content/Context;");
			var ctx:Dynamic = getContext();
			if (ctx == null) return null;

			var getDir:Dynamic = lime.system.JNI.createMemberMethod("android/content/Context", "getExternalFilesDir", "(Ljava/lang/String;)Ljava/io/File;");
			var file:Dynamic = getDir(ctx, null);
			if (file == null) return null;

			var getPath:Dynamic = lime.system.JNI.createMemberMethod("java/io/File", "getAbsolutePath", "()Ljava/lang/String;");
			var path:String = getPath(file);
			return (path != null && path.length > 0) ? path : null;
		}
		catch (e:Dynamic)
			trace('MobileStorage: getExternalFilesDir failed ($e), using internal storage');

		return null;
	}
	#end
	#end

	static inline function withSlash(path:String):String
	{
		if (path == null || path.length == 0)
			return '';

		var last:String = path.charAt(path.length - 1);
		return (last == '/' || last == '\\') ? path : path + '/';
	}
}
