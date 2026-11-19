package backend;

#if sys
import sys.FileSystem;
#end

/**
 * Where the mobile builds keep their writable files.
 *
 * Shared by all three trees (body / vanilla / pe063) so they land in the same
 * folder. Everything the game writes at runtime — saves, mods, logs, screenshots
 * — is relative to the working directory, which is what this sets up.
 *
 * Android: lime 的 applicationStorageDirectory 是 Context.getFilesDir()，
 * 也就是 /data/data/<包名>/files，卸载就没了，普通文件管理器也进不去。
 * 这里优先挑外置的应用目录（/storage/emulated/0/Android/data/<包名>/files），
 * 玩家插着数据线就能往里丢 mod，不需要任何存储权限。
 *
 * 桌面上什么都不做，还是从 exe 所在目录跑。
 */
class MobileStorage
{
	/** Folder name under the app's storage. Dot keeps it out of the way. */
	public static inline var FOLDER:String = '.realQuickJSEngine';

	static var resolved:String;

	/** Sets the process working directory and returns it (with a trailing slash). */
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
			// 建不出来就退回基目录，至少别让游戏跑不起来
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
		// lime 的 documentsDirectory 在安卓上就是 getExternalFilesDir() 那一份，
		// 但别处也可能被改成公共 Documents，所以拿路径本身做判断，认不出就用内置目录。
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
