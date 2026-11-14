package jsruntime;

import haxe.Log;
import psychlua.LuaUtils;

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
#include <haxe/Log.h>

// A1：Haxe 静态函数指针（签名用 ::String，由 Haxe 方法体里取地址塞进来）
typedef ::String (*qjs_host_probe_fn)(::String);
static qjs_host_probe_fn g_host_probe = nullptr;

static JSValue qjs_getProperty(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
	const char *s = (argc > 0) ? JS_ToCString(ctx, argv[0]) : nullptr;
	::String key(s ? s : "");
	if (s != nullptr) JS_FreeCString(ctx, s);
	::String r = g_host_probe ? g_host_probe(key) : ::String("null");
	return JS_NewString(ctx, r.utf8_str());
}

// 通用桥：函数名走 opaque，参数最多三个，全部按字符串过，结果也是字符串
typedef ::String (*qjs_host4_fn)(::String, ::String, ::String, ::String);
static qjs_host4_fn g_host4 = nullptr;

static JSValue qjs_call4(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
	const char *fn = (const char *)JS_GetOpaque(this_val, 1);
	char a[1024] = "", b[1024] = "", c[1024] = "";
	char *dst[3] = { a, b, c };
	for (int i = 0; i < 3 && i < argc; i++) {
		const char *s = JS_ToCString(ctx, argv[i]);
		if (s != nullptr) { snprintf(dst[i], 1024, "%s", s); JS_FreeCString(ctx, s); }
	}
	::String r = g_host4 ? g_host4(::String(fn ? fn : ""), ::String(a), ::String(b), ::String(c)) : ::String("");
	return JS_NewString(ctx, r.utf8_str());
}

// JS 侧的 trace()：把字符串交给 Haxe 的 Log.trace
static JSValue qjs_trace(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
	const char *s = (argc > 0) ? JS_ToCString(ctx, argv[0]) : nullptr;
	::haxe::Log_obj::trace(::String(s ? s : ""), null());
	if (s != nullptr) JS_FreeCString(ctx, s);
	return JS_UNDEFINED;
}

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

	/** 字符串 → 合适的 Haxe 值（数字 / 布尔 / null / 字符串） */
	@:keep static function coerce(v:String):Dynamic
	{
		if (v == null) return null;
		var t:String = v.trim();
		if (t == 'true') return true;
		if (t == 'false') return false;
		if (t == 'null') return null;
		if (t.length > 0 && t.length < 20)
		{
			var f:Float = Std.parseFloat(t);
			if (!Math.isNaN(f) && Std.string(f) == t) return f;
		}
		return v;
	}

	/**
	 * JS 函数的宿主分发。名字和语义都对齐 FunkinLua 那一套，
	 * 反射直接走 LuaUtils —— Lua 和 JS 查到的是同一个属性、同一套层级规则。
	 */
	@:keep static function hostCall(name:String, a:String, b:String, c:String):String
	{
		switch (name)
		{
			case 'getProperty':
				var split:Array<String> = a.split('.');
				var v:Dynamic = (split.length > 1)
					? LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split, true), split[split.length - 1])
					: LuaUtils.getVarInArray(LuaUtils.getTargetInstance(), a);
				return Std.string(v);

			case 'setProperty':
				var split:Array<String> = a.split('.');
				if (split.length > 1)
					LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split, true), split[split.length - 1], coerce(b));
				else
					LuaUtils.setVarInArray(LuaUtils.getTargetInstance(), a, coerce(b));
				return b;

			default:
				Log.trace('[js] hostCall: 未实现 $name', null);
				return '';
		}
	}

	/** 注册 getProperty / setProperty，走 hostCall */
	public static function installHostFunctions():Void
	{
		if (!isReady() && !init()) return;
		untyped __cpp__('g_host4 = (qjs_host4_fn)::jsruntime::QuickJSHandler_obj::hostCall;');
		// 名字直接写在 C 字面量里：Haxe 的 String 传给 C 会变成 String 对象，不是 const char*
		untyped __cpp__('
			JSValue g = JS_GetGlobalObject(g_js_ctx);
			JSValue f1 = JS_NewCFunction(g_js_ctx, qjs_call4, "getProperty", 3);
			JS_SetOpaque(f1, strdup("getProperty"));
			JS_SetPropertyStr(g_js_ctx, g, "getProperty", f1);
			JSValue f2 = JS_NewCFunction(g_js_ctx, qjs_call4, "setProperty", 3);
			JS_SetOpaque(f2, strdup("setProperty"));
			JS_SetPropertyStr(g_js_ctx, g, "setProperty", f2);
			JS_FreeValue(g_js_ctx, g);
		');
	}

	/** A1 探针：只回显参数，用来验证 C→Haxe 的返回值通道 */
	@:keep static function probe(k:String):String
	{
		return 'got:' + k;
	}

	/** 把 probe 的地址交给 C，并注册成 JS 的 getProperty */
	public static function installProbe():Void
	{
		if (!isReady() && !init()) return;
		// 在方法体里取地址：此处 QuickJSHandler_obj 已经定义完，不像 @:cppFileCode 那样在前面
		untyped __cpp__('g_host_probe = (qjs_host_probe_fn)::jsruntime::QuickJSHandler_obj::probe;');
		untyped __cpp__('
			JSValue g = JS_GetGlobalObject(g_js_ctx);
			JS_SetPropertyStr(g_js_ctx, g, "getProperty", JS_NewCFunction(g_js_ctx, qjs_getProperty, "getProperty", 1));
			JS_FreeValue(g_js_ctx, g);
		');
	}

	/** 注册 JS 侧的基础函数。现在只有 trace，用来验证 JS→C→Haxe 这条链路。 */
	public static function registerBasics():Void
	{
		if (!isReady() && !init()) return;
		untyped __cpp__('
			JSValue g = JS_GetGlobalObject(g_js_ctx);
			JS_SetPropertyStr(g_js_ctx, g, "trace", JS_NewCFunction(g_js_ctx, qjs_trace, "trace", 1));
			JS_FreeValue(g_js_ctx, g);
		');
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

	/** 读一个全局变量的字符串值（用来从 JS 侧取回结果，避免依赖控制台） */
	public static function globalString(name:String):String
	{
		if (!isReady()) return '';
		var out:String = '';
		untyped __cpp__('
			JSValue g = JS_GetGlobalObject(g_js_ctx);
			JSValue v = JS_GetPropertyStr(g_js_ctx, g, name.utf8_str());
			if (!JS_IsUndefined(v)) {
				const char *cs = JS_ToCString(g_js_ctx, v);
				if (cs != nullptr) { out = ::String(cs); JS_FreeCString(g_js_ctx, cs); }
			}
			JS_FreeValue(g_js_ctx, v);
			JS_FreeValue(g_js_ctx, g);
		');
		return out;
	}

	public static function dispose():Void
	{
		untyped __cpp__('
			if (g_js_ctx != nullptr) { JS_FreeContext(g_js_ctx); g_js_ctx = nullptr; }
			if (g_js_rt != nullptr) { JS_FreeRuntime(g_js_rt); g_js_rt = nullptr; }
		');
	}
}
