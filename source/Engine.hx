package;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * 启动引擎选择。
 *
 * 读取可执行文件所在目录（bin 根）的 engine.txt：
 *   body    -> 当前本体（本仓 fork）
 *   vanilla -> 原版 Psych Engine 1.0.4（source_vanilla 里的原版代码）
 * 文件不存在、读取失败或值不认识，一律回退到 body。
 */
class Engine
{
	public static inline var FILE_NAME:String = 'engine.txt';
	public static inline var BODY:String = 'body';
	public static inline var VANILLA:String = 'vanilla';
	public static inline var PE063:String = 'pe063';

	public static function current():String
	{
		var raw:String = readRaw();
		if (raw == null) return BODY;

		raw = raw.trim().toLowerCase();
		return switch (raw)
		{
			case VANILLA: VANILLA;
			case PE063: PE063;
			default: BODY;
		};
	}

	public static function isVanilla():Bool
		return current() == VANILLA;

	public static function isPe063():Bool
		return current() == PE063;

	public static function readRaw():String
	{
		#if sys
		for (path in candidatePaths())
		{
			if (path == null || !FileSystem.exists(path)) continue;

			try
			{
				return File.getContent(path);
			}
			catch (e:Dynamic)
			{
				trace('Engine: failed to read "$path": $e');
			}
		}
		#end

		return null;
	}

	public static function write(value:String):Bool
	{
		#if sys
		var path:String = writePath();
		if (path == null) return false;

		try
		{
			File.saveContent(path, value + '\n');
			return true;
		}
		catch (e:Dynamic)
		{
			trace('Engine: failed to write "$path": $e');
			return false;
		}
		#else
		return false;
		#end
	}

	public static function writePath():String
	{
		var appDir:String = applicationDirectory();
		if (appDir != null) return join(appDir, FILE_NAME);

		var cwd:String = normalCwd();
		if (cwd != null) return join(cwd, FILE_NAME);

		return null;
	}

	static function candidatePaths():Array<String>
	{
		var out:Array<String> = [];

		var appDir:String = applicationDirectory();
		if (appDir != null) out.push(join(appDir, FILE_NAME));

		var cwd:String = normalCwd();
		if (cwd != null)
		{
			var cwdPath:String = join(cwd, FILE_NAME);
			if (out.length == 0 || out[0] != cwdPath) out.push(cwdPath);
		}

		return out;
	}

	static function applicationDirectory():String
	{
		#if sys
		try
		{
			var dir:String = lime.system.System.applicationDirectory;
			if (dir != null && dir.length > 0) return dir;
		}
		catch (e:Dynamic) {}
		#end

		return null;
	}

	static function normalCwd():String
	{
		#if sys
		try
		{
			return Sys.getCwd();
		}
		catch (e:Dynamic) {}
		#end

		return null;
	}

	static function join(dir:String, file:String):String
	{
		if (dir == null || dir.length == 0) return file;

		var last:String = dir.charAt(dir.length - 1);
		return (last == '/' || last == '\\') ? dir + file : dir + '/' + file;
	}
}
