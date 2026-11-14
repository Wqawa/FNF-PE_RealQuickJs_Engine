package jsruntime;

/**
 * QuickJS-NG 的最小绑定（先只验证能链接 + 能跑 eval）。
 *
 * 静态库由 manage.sh 功能 10 生成：third_party/quickjs-ng/build/quickjs-ng.lib。
 * 只需 quickjs.c / libregexp.c / libunicode.c 三个源文件（这个 fork 把 cutils 并进 quickjs.c 了）。
 *
 * 注意路径里有空格（"FNF code"），buildXml 里的 name 属性用引号包住。
 */
@:buildXml('
<target id="haxe">
	<include name="D:/FNF/FNF code/FNF-PE_RealQuickJs_Engine/third_party/quickjs-ng" />
	<libpath name="D:/FNF/FNF code/FNF-PE_RealQuickJs_Engine/third_party/quickjs-ng/build" />
	<lib name="quickjs-ng.lib" />
</target>
')
@:cppFileCode('
// 绝对路径直接 include：项目路径带空格，hxcpp 的 <include> 加 -I 会被拆开
#include "D:/FNF/FNF code/FNF-PE_RealQuickJs_Engine/third_party/quickjs-ng/quickjs.h"
')
class QuickJS
{
	/** 顺便把结果落到 testout/quickjs_smoke.txt —— 双击启动看不到控制台，写文件才查得到 */
	static function note(text:String):Void
	{
		#if sys
		try {
			sys.FileSystem.createDirectory('./testout');
			var f = sys.io.File.write('./testout/quickjs_smoke.txt', false);
			f.writeString(text + '\n');
			f.close();
		} catch (e:Dynamic) {}
		#end
	}

	/** 跑一次 1+1，返回结果字符串；失败返回错误描述。只用来验证 ABI 通不通。 */
	public static function smokeTest():String
	{
		var out:String = 'fail';
		untyped __cpp__('
			JSRuntime *rt = JS_NewRuntime();
			if (rt == nullptr) { out = String("runtime"); }
			else {
				JSContext *ctx = JS_NewContext(rt);
				if (ctx == nullptr) { out = String("context"); }
				else {
					JSValue v = JS_Eval(ctx, "1+1", 3, "<hd>", JS_EVAL_TYPE_GLOBAL);
					if (JS_IsException(v)) out = String("eval-exception");
					else {
						int32_t n = 0;
						JS_ToInt32(ctx, &n, v);
						out = String("ok ") + String(n);
					}
					JS_FreeValue(ctx, v);
					JS_FreeContext(ctx);
				}
				JS_FreeRuntime(rt);
			}
		');
		note(out);
		return out;
	}
}
