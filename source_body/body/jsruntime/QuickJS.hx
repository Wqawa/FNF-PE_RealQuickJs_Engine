package jsruntime;

/**
 * Minimal QuickJS-NG binding (first step: prove it links and can eval).
 *
 * The static library is built by manage.sh into third_party/quickjs-ng/build/quickjs-ng.lib.
 * Only quickjs.c / libregexp.c / libunicode.c are needed (cutils is folded into quickjs.c here).
 *
 * The path below is absolute; manage.sh realigns it before building when the repo moves (cmd_build).
 */
@:buildXml('
<target id="haxe">
	<include name="D:/FNF/FNF-PE_RealQuickJs_Engine/third_party/quickjs-ng" />
	<libpath name="D:/FNF/FNF-PE_RealQuickJs_Engine/third_party/quickjs-ng/build" />
	<lib name="quickjs-ng.lib" />
</target>
')
@:cppFileCode('
// Absolute include on purpose: the project path has spaces and hxcpp splits -I.
#include "D:/FNF/FNF-PE_RealQuickJs_Engine/third_party/quickjs-ng/quickjs.h"
')
class QuickJS
{
	/** Also writes to testout/quickjs_smoke.txt: double-clicked builds have no console. */
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

	/** Runs 1+1, returns the result string or an error description. ABI smoke test only. */
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
