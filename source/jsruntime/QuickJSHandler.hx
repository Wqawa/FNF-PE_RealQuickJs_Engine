package jsruntime;

import haxe.Log;
import psychlua.LuaUtils;

/**
 * QuickJS-NG 运行时 + JS↔Haxe 桥。
 *
 * 设计要点：
 * - runtime/context 是 C++ 文件级 static，不往 Haxe 的 Dynamic 里塞裸指针（GC 会移动对象）。
 * - 桥接用「每个 JS 函数一条专用 trampoline + 一个 Haxe 静态函数指针」。
 *   不走 JS_SetOpaque 存函数名 —— 那条路对 CFunction 不可靠（class id 对不上就取不到）。
 * - C 里引用 Haxe 静态函数只能在方法体里取地址（@:cppFileCode 在类定义之前，写不了 QuickJSHandler_obj）。
 * - 一切错误只 trace，不抛异常：一个脚本死了不能带走整个游戏。
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
#include <cstring>
#include <haxe/Log.h>

static JSRuntime *g_js_rt = nullptr;
static JSContext *g_js_ctx = nullptr;
static char g_js_err[1024];

// Haxe 侧塞进来的函数指针（在 installHostFunctions 里取地址）
typedef ::String (*qjs_get_fn)(::String);
typedef ::String (*qjs_set_fn)(::String, ::String);
static qjs_get_fn g_host_get = nullptr;
static qjs_set_fn g_host_set = nullptr;

static JSValue qjs_trace(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
	const char *s = (argc > 0) ? JS_ToCString(ctx, argv[0]) : nullptr;
	::haxe::Log_obj::trace(::String(s ? s : ""), null());
	if (s != nullptr) JS_FreeCString(ctx, s);
	return JS_UNDEFINED;
}

static JSValue qjs_getProperty(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
	const char *s = (argc > 0) ? JS_ToCString(ctx, argv[0]) : nullptr;
	::String key(s ? s : "");
	if (s != nullptr) JS_FreeCString(ctx, s);
	::String r = g_host_get ? g_host_get(key) : ::String("");
	return JS_NewString(ctx, r.utf8_str());
}

static JSValue qjs_setProperty(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
	const char *s1 = (argc > 0) ? JS_ToCString(ctx, argv[0]) : nullptr;
	const char *s2 = (argc > 1) ? JS_ToCString(ctx, argv[1]) : nullptr;
	::String k(s1 ? s1 : ""), v(s2 ? s2 : "");
	if (s1 != nullptr) JS_FreeCString(ctx, s1);
	if (s2 != nullptr) JS_FreeCString(ctx, s2);
	::String r = g_host_set ? g_host_set(k, v) : ::String("");
	return JS_NewString(ctx, r.utf8_str());
}
')
class QuickJSHandler
{
	public static inline var NAME:String = 'quickjs';

	// ---------------------------------------------------------------- 生命周期
	public static function init(memLimitMB:Int = 0):Bool
	{
		var ok:Bool = false;
		untyped __cpp__('
			if (g_js_ctx == nullptr) {
				g_js_rt = JS_NewRuntime();
				if (g_js_rt != nullptr) {
					if ((int)memLimitMB > 0) JS_SetMemoryLimit(g_js_rt, (size_t)memLimitMB * 1024 * 1024);
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

	public static function dispose():Void
	{
		untyped __cpp__('
			if (g_js_ctx != nullptr) { JS_FreeContext(g_js_ctx); g_js_ctx = nullptr; }
			if (g_js_rt != nullptr) { JS_FreeRuntime(g_js_rt); g_js_rt = nullptr; }
		');
	}

	public static function pump():Void
	{
		if (!isReady()) return;
		untyped __cpp__('
			JSContext *c = nullptr;
			while (JS_ExecutePendingJob(g_js_rt, &c) > 0) { }
		');
	}

	// ---------------------------------------------------------------- 执行
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
			} else out = true;
			JS_FreeValue(g_js_ctx, r);
		');
		if (!out) Log.trace('[js] eval failed in ' + chunkName + ': ' + lastError(), null);
		return out;
	}

	public static function evalFile(path:String):Bool
	{
		if (!sys.FileSystem.exists(path)) return false;
		return eval(sys.io.File.getContent(path), path);
	}

	public static function lastError():String
	{
		var msg:String = '';
		untyped __cpp__('msg = ::String(g_js_err);');
		return msg;
	}

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

	// ---------------------------------------------------------------- 宿主函数
	/** 字符串 → 数字 / 布尔 / null / 原字符串 */
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

	/** getProperty(variable)：反射走 LuaUtils，和 Lua 完全同一条路 */
	@:keep static function hostGet(a:String):String
	{
		var split:Array<String> = a.split('.');
		var v:Dynamic = (split.length > 1)
			? LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split, true), split[split.length - 1])
			: LuaUtils.getVarInArray(LuaUtils.getTargetInstance(), a);
		return Std.string(v);
	}

	@:keep static function hostSet(a:String, b:String):String
	{
		var split:Array<String> = a.split('.');
		if (split.length > 1)
			LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split, true), split[split.length - 1], coerce(b));
		else
			LuaUtils.setVarInArray(LuaUtils.getTargetInstance(), a, coerce(b));
		return b;
	}

	/** 注册 trace / getProperty / setProperty */
	public static function installHostFunctions():Void
	{
		if (!isReady() && !init()) return;
		// 取地址必须在方法体里：此处 QuickJSHandler_obj 已经定义
		untyped __cpp__('g_host_get = (qjs_get_fn)::jsruntime::QuickJSHandler_obj::hostGet;');
		untyped __cpp__('g_host_set = (qjs_set_fn)::jsruntime::QuickJSHandler_obj::hostSet;');
		untyped __cpp__('
			JSValue g = JS_GetGlobalObject(g_js_ctx);
			JS_SetPropertyStr(g_js_ctx, g, "trace", JS_NewCFunction(g_js_ctx, qjs_trace, "trace", 1));
			JS_SetPropertyStr(g_js_ctx, g, "getProperty", JS_NewCFunction(g_js_ctx, qjs_getProperty, "getProperty", 1));
			JS_SetPropertyStr(g_js_ctx, g, "setProperty", JS_NewCFunction(g_js_ctx, qjs_setProperty, "setProperty", 2));
			JS_FreeValue(g_js_ctx, g);
		');
	}
}
