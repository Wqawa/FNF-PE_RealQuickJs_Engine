package backend;

import sys.io.File;
import sys.FileSystem;

/**
 * 把关键流程同时写进工作目录下的 debug.log。
 * 安卓的 logcat 主缓冲区会被系统日志挤爆，崩溃前那一小段 trace 经常被冲掉（这次排查 mod 加载
 * 时就吃了这个亏）；写文件就不受缓冲区影响，出事后 adb pull /sdcard/RealQuickJS/debug.log 就能
 * 拿到完整时间线。桌面端完全不写，只在安卓/苹果生效。
 */
class DebugLog
{
	static var path:String = null;
	static var out:sys.io.FileOutput = null;
	static var broken:Bool = false;

	public static function log(tag:String, msg:String):Void
	{
		#if (android || ios)
		if (broken) return;

		try
		{
			if (out == null)
			{
				if (path == null)
				{
					var cwd:String = Sys.getCwd();
					if (cwd == null || cwd.length == 0) cwd = '/sdcard/RealQuickJS/';
					var last:String = cwd.charAt(cwd.length - 1);
					if (last != '/' && last != '\\') cwd += '/';
					path = cwd + 'debug.log';
				}
				out = File.append(path, false);
				out.writeString('===== debug.log opened =====\n');
			}

			out.writeString(tag + ': ' + msg + '\n');
			out.flush();
		}
		catch (e:Dynamic) broken = true;
		#end
	}

	/** 自检只跑一次 */
	public static var luaSelfTestDone:Bool = false;

	/**
	 * Lua 运行时自检：分步写 debug.log，最后一行就是崩在前一步。
	 */
	public static function luaSelfTest():Void
	{
		#if (android || ios)
		if (luaSelfTestDone) return;
		luaSelfTestDone = true;
		var tag = 'luatest';
		log(tag, 'begin, cwd=' + Sys.getCwd());

		var L = llua.LuaL.newstate();
		log(tag, 's1 newstate=' + (L != null));
		llua.LuaL.openlibs(L);
		log(tag, 's2 openlibs ok, top=' + llua.Lua.gettop(L));

		// s3: 短路字符串入池（openlibs 里已经做过很多次）
		llua.Lua.pushstring(L, 'abc');
		log(tag, 's3 pushstring ok, top=' + llua.Lua.gettop(L));

		// s4: 按名字查全局表
		llua.Lua.getfield(L, llua.Lua.LUA_GLOBALSINDEX, 'print');
		log(tag, 's4 getfield(print) type=' + llua.Lua.type(L, -1));

		// s5: 连续入池 200 个新串（会触发 intern 表扩容）
		var i = 0;
		while (i < 200)
		{
			llua.Lua.pushstring(L, 'probe_key_' + i);
			llua.Lua.pop(L, 1);
			i++;
		}
		log(tag, 's5 pushstring x200 ok');

		// s6: 建表 + 200 次 setfield（表扩容路径）
		llua.Lua.newtable(L);
		var j = 0;
		while (j < 200)
		{
			llua.Lua.pushinteger(L, j);
			llua.Lua.setfield(L, -2, 'field_' + j);
			j++;
		}
		log(tag, 's6 table setfield x200 ok, top=' + llua.Lua.gettop(L));

		// s7: 强制一次全量 GC
		llua.Lua.gc(L, 2, 0);
		log(tag, 's7 gc collect ok');

		// s8: 空 chunk 编译
		var r0 = llua.LuaL.loadbuffer(L, '', 0, '=empty');
		log(tag, 's8 loadbuffer("") ret=' + r0);

		// s9: 最小 chunk 编译
		var s9 = 'return 1';
		var r1 = llua.LuaL.loadbuffer(L, s9, s9.length, '=tiny');
		log(tag, 's9 loadbuffer("return 1") ret=' + r1);

		log(tag, 'end');
		#end
	}
}