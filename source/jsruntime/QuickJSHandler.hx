package jsruntime;

import haxe.Log;

/**
 * QuickJS-NG 的运行时封装（单上下文，够 PE 用）。
 *
 * 设计取舍：
 * - runtime/context 存在 C++ 侧的 file-static 里，不往 Haxe 的 Dynamic 里塞裸指针
 *   （hxcpp 的 GC 会移动对象，存指针迟早出事）。
 * - 出错不抛异常，走 trace，别把整个游戏带崩；脚本错误本来就该是"只死这一个脚本"。
 * - 内存上限 + 中断预算留给下一步，现在先把"能 eval、能读文件"跑通。
 */
@:buildXml('
<target id="haxe">
	<include name="D:/FNF/FNF code/FNF-PE_RealQuickJs_Engine/third_party/quickjs-ng" />
	<libpath name="D:/FNF/FNF code/FNF-PE_RealQuickJs_Engine/third_party/quickjs-ng/build" />
	<lib name="quickjs-ng.lib" />
</target>
')
@:cppFileCode('
#include "D:/FNF/FNF code/FNF-PE_RealQuickJs_Engine/third_party/quickjs-ng/quickjs.h"
#include <cstdio>
#include <cstdlib>

static JSRuntime *g_js_rt = nullptr;
static JSContext *g_js_ctx = nullptr;
static char g_js_err[1024];
')
class QuickJSHandler
{
	public static inline var NAME:String = 'quickjs';

	/** 建 runtime + context。重复调用是安全的。memLimitMB<=0 表示不限制。 */
	public static function init(memLimitMB:Int = 0):Bool
	{
		var ok:Bool = false;
		untyped __cpp__('
			if (g_js_ctx == nullptr) {
				g_js_rt = JS_NewRuntime();
				if (g_js_rt != nullptr) {
					if ((int)memLimitMB > 0)
						JS_SetMemoryLimit(g_js_rt, (size_t)memLimitMB * 1024 * 1024);
					g_js_ctx = JS_NewContext(g_js_rt);
				}
			}
			ok = (g_js_ctx != nullptr);
		');
		return ok;
	}

	public static function isReady():Bool
	{
		var ok:Bool = false;
		untyped __cpp__('ok = (g_js_ctx != nullptr);');
		return ok;
	}

	/** 跑一段代码；返回 true 表示没有异常。异常信息通过 trace 打出来。 */
	public static function eval(code:String, ?chunkName:String = '<js>'):Bool
	{
		if (!isReady() && !init()) return false;

		var out:Bool = false;
		untyped __cpp__('
			JSValue r = JS_Eval(g_js_ctx, code.utf8_str(), code.length, chunkName.utf8_str(), JS_EVAL_TYPE_GLOBAL);
			if (JS_IsException(r)) {
				JSValue e = JS_GetException(g_js_ctx);
				const char *msg = JS_ToCString(g_js_ctx, e);
				snprintf(g_js_err, sizeof(g_js_err), "%s", msg ? msg : "(unknown)");
				if (msg) JS_FreeCString(g_js_ctx, msg);
				JS_FreeValue(g_js_ctx, e);
				out = false;
			} else {
				out = true;
			}
			JS_FreeValue(g_js_ctx, r);
		');
		if (!out) Log.trace('[js] eval failed in ' + chunkName + ': ' + lastError(), null);
		return out;
	}

	/** 上一段错误信息（只在 eval 失败后有意义）。 */
	public static function lastError():String
	{
		var msg:String = '';
		untyped __cpp__('msg = ::String(g_js_err);');
		return msg;
	}

	/** 读一个 .js 文件并执行。文件不存在返回 false。 */
	public static function evalFile(path:String):Bool
	{
		if (!sys.FileSystem.exists(path)) return false;
		return eval(sys.io.File.getContent(path), path);
	}

	/** 每帧调一次：跑完 microtask/ Promise 回调。 */
	public static function pump():Void
	{
		if (!isReady()) return;
		untyped __cpp__('
			JSContext *c = nullptr;
			while (JS_ExecutePendingJob(g_js_rt, &c) > 0) { }
		');
	}

	public static function dispose():Void
	{
		untyped __cpp__('
			if (g_js_ctx != nullptr) { JS_FreeContext(g_js_ctx); g_js_ctx = nullptr; }
			if (g_js_rt != nullptr) { JS_FreeRuntime(g_js_rt); g_js_rt = nullptr; }
		');
	}
}
