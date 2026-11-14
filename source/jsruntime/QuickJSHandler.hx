package jsruntime;

import haxe.Log;
import psychlua.LuaUtils;
import backend.Paths;
import backend.ScriptClassAliases;
import flixel.FlxG;
import states.PlayState;
import backend.MusicBeatState;

/**
 * QuickJS-NG 运行时 + JS↔Haxe 桥。
 *
 * 桥接形态：「单 trampoline + 函数编号」。
 *   JS 侧:  __host(idx, a, b, c)   ← 由 Haxe 一次性 eval 出来的 wrapper 调
 *   C  侧:  qjs_host 读编号和三个字符串，回调 Haxe 的 hostDispatch
 *   Haxe:   按编号查表
 * 这样加函数只改 Haxe 表 + WRAPPERS 字符串，不用碰 C。
 *
 * 之前用过「每函数一条 trampoline」和「JS_SetOpaque 存函数名」，都不划算：
 * 前者代码量爆炸，后者对 CFunction 不可靠（class id 对不上就读不到）。
 *
 * 其它约定：
 * - runtime/context 是 C++ 文件级 static，不往 Dynamic 里塞裸指针（GC 会移动对象）。
 * - 错误只 trace，不抛异常：一个脚本挂了不能带走整个游戏。
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

typedef ::String (*qjs_host_fn)(int, ::String, ::String, ::String, ::String);
static qjs_host_fn g_host = nullptr;

static JSValue qjs_trace(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
	const char *s = (argc > 0) ? JS_ToCString(ctx, argv[0]) : nullptr;
	::haxe::Log_obj::trace(::String(s ? s : ""), null());
	if (s != nullptr) JS_FreeCString(ctx, s);
	return JS_UNDEFINED;
}

// 唯一的宿主入口：argv[0] = 函数编号，argv[1..3] = 字符串参数
static JSValue qjs_host(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
	int idx = 0;
	if (argc > 0) JS_ToInt32(ctx, &idx, argv[0]);

	char buf[4][1024];
	memset(buf, 0, sizeof(buf));
	for (int i = 1; i <= 4 && i < argc; i++) {
		const char *s = JS_ToCString(ctx, argv[i]);
		if (s != nullptr) { snprintf(buf[i - 1], 1024, "%s", s); JS_FreeCString(ctx, s); }
	}

	::String r = g_host ? g_host(idx, ::String(buf[0]), ::String(buf[1]), ::String(buf[2]), ::String(buf[3])) : ::String("");
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

	// ---------------------------------------------------------------- 宿主函数表
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

	/**
	 * JS 侧包装：全部走 __host(编号, a, b, c)。
	 * 编号必须和下面 hostDispatch 的 case 一一对应。
	 */
	static inline var WRAPPERS:String = '
		const __h = (i, a, b, c, d) => __host(i, a === undefined ? "" : String(a), b === undefined ? "" : String(b), c === undefined ? "" : String(c), d === undefined ? "" : String(d));
		globalThis.trace = (m) => __h(-1, m);
		globalThis.getProperty = (v) => __h(0, v);
		globalThis.setProperty = (v, val) => __h(1, v, val);
		globalThis.getPropertyFromClass = (c, v) => __h(2, c, v);
		globalThis.setPropertyFromClass = (c, v, val) => __h(3, c, v, val);
		globalThis.playSound = (name, vol) => __h(4, name, vol);
		globalThis.makeLuaSprite = (tag, img, x, y) => __h(5, tag, img, x, y);
		globalThis.makeAnimatedLuaSprite = (tag, img, x, y) => __h(6, tag, img, x, y);
		globalThis.addLuaSprite = (tag, front) => __h(7, tag, front);
		globalThis.addAnimationByPrefix = (tag, name, prefix, fps) => __h(8, tag, name, prefix, fps);
		globalThis.objectPlayAnimation = (tag, name, forced) => __h(9, tag, name, forced);
		globalThis.setObjectCamera = (tag, cam) => __h(10, tag, cam);
	';

	/** 编号 → 实现。加函数只在这张表里加一行。 */
	@:keep static function hostDispatch(idx:Int, a:String, b:String, c:String, d:String):String
	{
		try {
			return dispatchInner(idx, a, b, c, d);
		} catch (e:Dynamic) {
			Log.trace('[js] 宿主函数异常 idx=$idx a=$a b=$b : ' + Std.string(e), null);
			return '';
		}
	}

	@:keep static function dispatchInner(idx:Int, a:String, b:String, c:String, d:String):String
	{
		switch (idx)
		{
			case 0: // getProperty
				var split:Array<String> = a.split('.');
				var v:Dynamic = (split.length > 1)
					? LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split, true), split[split.length - 1])
					: LuaUtils.getVarInArray(LuaUtils.getTargetInstance(), a);
				return Std.string(v);

			case 1: // setProperty
				var split:Array<String> = a.split('.');
				if (split.length > 1)
					LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split, true), split[split.length - 1], coerce(b));
				else
					LuaUtils.setVarInArray(LuaUtils.getTargetInstance(), a, coerce(b));
				return b;

			case 2: // getPropertyFromClass
				var cls:Dynamic = ScriptClassAliases.resolve(a);
				return Std.string(LuaUtils.getVarInArray(cls, b));

			case 3: // setPropertyFromClass
				var cls:Dynamic = ScriptClassAliases.resolve(a);
				LuaUtils.setVarInArray(cls, b, coerce(c));
				return c;

			case 4: // playSound
				var snd = Paths.sound(a);
				if (snd != null)
				{
					var vol:Float = (b.length > 0) ? Std.parseFloat(b) : 1;
					if (Math.isNaN(vol)) vol = 1;
					FlxG.sound.play(snd, vol);
					return '1';
				}
				return '0';

			case 5, 6: // makeLuaSprite / makeAnimatedLuaSprite
				var x:Float = (c.length > 0) ? Std.parseFloat(c) : 0;
				var y:Float = (d.length > 0) ? Std.parseFloat(d) : 0;
				if (Math.isNaN(x)) x = 0;
				if (Math.isNaN(y)) y = 0;
				var spr = new psychlua.ModchartSprite(x, y);
				if (b.length > 0)
				{
					if (idx == 5) spr.loadGraphic(Paths.image(b));
					else LuaUtils.loadFrames(spr, b, 'auto');
				}
				MusicBeatState.getVariables().set(a, spr);
				return '1';

			case 7: // addLuaSprite
				var spr7:Dynamic = MusicBeatState.getVariables().get(a);
				if (spr7 == null) return '0';
				PlayState.instance.add(spr7);
				return '1';

			case 8: // addAnimationByPrefix
				var o8:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o8 == null) return '0';
				var fps:Int = (d.length > 0) ? Std.parseInt(d) : 24;
				if (fps <= 0) fps = 24;
				o8.animation.addByPrefix(b, c, fps, true);
				return '1';

			case 9: // objectPlayAnimation
				var o9:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o9 == null) return '0';
				o9.animation.play(b, true);
				return '1';

			case 10: // setObjectCamera
				var o10:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o10 == null) return '0';
				if (!Std.isOfType(o10, flixel.FlxSprite)) return '0'; // 组/Bar 这类没有 cameras 字段
				var sp:flixel.FlxSprite = cast o10;
				sp.cameras = [b == 'hud' ? PlayState.instance.camHUD : PlayState.instance.camGame];
				return '1';

			default:
				Log.trace('[js] 未实现的宿主函数编号 $idx', null);
				return '';
		}
	}

	/** 注册 trace + 所有包装函数（一次 eval 搞定） */
	public static function installHostFunctions():Void
	{
		if (!isReady() && !init()) return;
		// 取地址必须在方法体里：此处 QuickJSHandler_obj 已经定义
		untyped __cpp__('g_host = (qjs_host_fn)::jsruntime::QuickJSHandler_obj::hostDispatch;');
		untyped __cpp__('
			JSValue g = JS_GetGlobalObject(g_js_ctx);
			JS_SetPropertyStr(g_js_ctx, g, "__host", JS_NewCFunction(g_js_ctx, qjs_host, "__host", 5));
			JS_SetPropertyStr(g_js_ctx, g, "console", JS_NewObject(g_js_ctx));
			JS_FreeValue(g_js_ctx, g);
		');
		eval(WRAPPERS + '\nconsole.log = trace;', '<wrappers>');
	}
}
