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
	{
		#if (android || ios)
		if (resolved != null)
			return resolved;

		var root:String = withSlash(pickBase());

		try
		{
			if (!FileSystem.exists(root))
				FileSystem.createDirectory(root);
		}
		catch (e:Dynamic)
		{
			// can't create it? drop to internal storage, just keep the game running
			trace('MobileStorage: cannot create "$root" ($e), backing off to internal storage');
			root = withSlash(lime.system.System.applicationStorageDirectory) + FOLDER + '/';
			try
			{
				if (!FileSystem.exists(root)) FileSystem.createDirectory(root);
			}
			catch (e2:Dynamic) {}
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
		// 1) /sdcard/RealQuickJS - the one players can actually find. Needs the
		//    "all files access" grant; without it isExternalStorageManager() is false.
		var pub:String = publicStorageDir();
		if (pub != null) return pub;
		#end

		#if android
		// 2) app's own external dir: no permission, still readable over USB / adb
		var own:String = externalFilesDir();
		if (own != null) return withSlash(own) + FOLDER;
		#end

		// 3) internal private dir, always works
		return withSlash(lime.system.System.applicationStorageDirectory) + FOLDER;
	}

	#if android
	// /storage/emulated/0/RealQuickJS - visible in every file manager, so dropping a
	// mod in is just copy-paste. Returns null unless the user granted all-files access.
	static function publicStorageDir():String
	{
		try
		{
			var isManager:Dynamic = lime.system.JNI.createStaticMethod("android/os/Environment", "isExternalStorageManager", "()Z");
			if (isManager() != true) return null;

			var getExternal:Dynamic = lime.system.JNI.createStaticMethod("android/os/Environment", "getExternalStorageDirectory", "()Ljava/io/File;");
			var dir:Dynamic = getExternal();
			if (dir == null) return null;

			var getPath:Dynamic = lime.system.JNI.createMemberMethod("java/io/File", "getAbsolutePath", "()Ljava/lang/String;");
			var base:String = getPath(dir);
			if (base == null || base.length == 0) return null;

			return withSlash(base) + PUBLIC_NAME;
		}
		catch (e:Dynamic)
			trace('MobileStorage: public storage unavailable ($e)');

		return null;
	}
	#end

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
