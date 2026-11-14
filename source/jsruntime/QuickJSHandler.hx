package jsruntime;

import haxe.Log;
import psychlua.LuaUtils;
import backend.Paths;
import backend.CoolUtil;
import backend.ScriptClassAliases;
import flixel.FlxG;
import flixel.tweens.FlxTween;
import flixel.util.FlxTimer;
import states.PlayState;
import backend.MusicBeatState;

/**
 * QuickJS-NG 运行时 + JS↔Haxe 桥。
 *
 * 桥接形态：「单 trampoline + 函数编号」。
 *   JS 侧:  __host(idx, a, b, c, d, e, f)  ← 由 Haxe 一次性 eval 出来的 wrapper 调
 *   C  侧:  qjs_host 读编号和六个字符串，回调 Haxe 的 hostDispatch
 *   Haxe:   按编号查表
 * 加函数只改 Haxe 表 + WRAPPERS 字符串，C 一个字符都不用动。
 *
 * 之前用过「每函数一条 trampoline」和「JS_SetOpaque 存函数名」，都不划算：
 * 前者代码量爆炸，后者对 CFunction 不可靠（class id 对不上就读不到）。
 *
 * 其它约定：
 * - runtime/context 是 C++ 文件级 static，不往 Dynamic 里塞裸指针（GC 会移动对象）。
 * - 错误只 trace + 写 testout/js_log.txt，不抛异常：一个脚本挂了不能带走整个游戏。
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

typedef ::String (*qjs_host_fn)(int, ::String, ::String, ::String, ::String, ::String, ::String);
static qjs_host_fn g_host = nullptr;

// 唯一的宿主入口：argv[0] = 函数编号，argv[1..6] = 字符串参数
static JSValue qjs_host(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
	int idx = 0;
	if (argc > 0) JS_ToInt32(ctx, &idx, argv[0]);

	char buf[6][1024];
	memset(buf, 0, sizeof(buf));
	for (int i = 1; i <= 6 && i < argc; i++) {
		const char *s = JS_ToCString(ctx, argv[i]);
		if (s != nullptr) { snprintf(buf[i - 1], 1024, "%s", s); JS_FreeCString(ctx, s); }
	}

	::String r = g_host ? g_host(idx,
		::String(buf[0]), ::String(buf[1]), ::String(buf[2]),
		::String(buf[3]), ::String(buf[4]), ::String(buf[5])) : ::String("");
	return JS_NewString(ctx, r.utf8_str());
}

// 调用 JS 全局函数（回调用）：
//   mode 0 = 无参，1 = (number)，2 = (string)，
//   mode 3 = (string, number)，4 = (string, string)
static bool js_invoke(const char *name, int mode, double num, const char *str, const char *str2) {
	bool ok = false;
	g_js_err[0] = 0; // 清掉上一次的残留，否则「函数不存在」会被误报成异常
	if (g_js_ctx == nullptr) return false;
	JSValue g = JS_GetGlobalObject(g_js_ctx);
	JSValue f = JS_GetPropertyStr(g_js_ctx, g, name);
	if (JS_IsFunction(g_js_ctx, f)) {
		JSValue a[2];
		int n = 0;
		if (mode == 1) { a[0] = JS_NewFloat64(g_js_ctx, num); n = 1; }
		else if (mode == 2) { a[0] = JS_NewString(g_js_ctx, str ? str : ""); n = 1; }
		else if (mode == 3) {
			a[0] = JS_NewString(g_js_ctx, str ? str : "");
			a[1] = JS_NewFloat64(g_js_ctx, num);
			n = 2;
		}
		else if (mode == 4) {
			a[0] = JS_NewString(g_js_ctx, str ? str : "");
			a[1] = JS_NewString(g_js_ctx, str2 ? str2 : "");
			n = 2;
		}
		JSValue r = JS_Call(g_js_ctx, f, g, n, n > 0 ? a : nullptr);
		ok = !JS_IsException(r);
		if (!ok) {
			JSValue e = JS_GetException(g_js_ctx);
			const char *m = JS_ToCString(g_js_ctx, e);
			snprintf(g_js_err, sizeof(g_js_err), "%s", m ? m : "(unknown)");
			if (m) JS_FreeCString(g_js_ctx, m);
			JS_FreeValue(g_js_ctx, e);
		}
		JS_FreeValue(g_js_ctx, r);
		for (int i = 0; i < n; i++) JS_FreeValue(g_js_ctx, a[i]);
	}
	JS_FreeValue(g_js_ctx, f);
	JS_FreeValue(g_js_ctx, g);
	return ok;
}
')
class QuickJSHandler
{
	public static inline var NAME:String = 'quickjs';

	// ---------------------------------------------------------------- 文件日志
	// trace 只往 stdout 走，双击启动的窗口没有控制台，等于全丢。
	// 脚本相关的输出一律再写一份到 testout/js_log.txt，出问题能直接看。
	static var LOG_PATH:String = './testout/js_log.txt';

	public static function log(msg:String):Void
	{
		#if sys
		try {
			sys.FileSystem.createDirectory('./testout');
			var f = sys.io.File.append(LOG_PATH, false);
			f.writeString(msg + '\n');
			f.close();
		} catch (e:Dynamic) {}
		#end
	}

	/** 每首歌开头清一次，免得日志越滚越长 */
	public static function truncateLog(header:String):Void
	{
		#if sys
		try {
			sys.FileSystem.createDirectory('./testout');
			var f = sys.io.File.write(LOG_PATH, false);
			f.writeString(header + '\n');
			f.close();
		} catch (e:Dynamic) {}
		#end
	}

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
			// 长度必须用 strlen：code.length 是字符数，中文注释会让 UTF-8 字节数更大，
			// 按字符数传就被截断，报 "SyntaxError: unexpected end of string"
			const char *src = code.utf8_str();
			JSValue r = JS_Eval(g_js_ctx, src, strlen(src), chunkName.utf8_str(), JS_EVAL_TYPE_GLOBAL);
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
		if (!out)
		{
			var m:String = '[error] ' + chunkName + ': ' + lastError();
			Log.trace('[js] ' + m, null);
			log(m);
		}
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

	// ---------------------------------------------------------------- 回调调用
	/** 无参回调。函数不存在时静默返回 false。 */
	public static function callGlobal(name:String):Bool
	{
		if (!isReady()) return false;
		var ok:Bool = false;
		untyped __cpp__('ok = js_invoke(name.utf8_str(), 0, 0, nullptr, nullptr);');
		if (!ok && lastError().length > 0) log('[error] ' + name + '(): ' + lastError());
		return ok;
	}

	/** 一个数字参数的回调（onUpdate / onBeatHit / onStepHit …） */
	public static function callGlobalNum(name:String, v:Float):Bool
	{
		if (!isReady()) return false;
		var ok:Bool = false;
		untyped __cpp__('ok = js_invoke(name.utf8_str(), 1, (double)v, nullptr, nullptr);');
		if (!ok && lastError().length > 0) log('[error] ' + name + '(num): ' + lastError());
		return ok;
	}

	/** 一个字符串参数的回调 */
	public static function callGlobalStr(name:String, s:String):Bool
	{
		if (!isReady()) return false;
		var ok:Bool = false;
		untyped __cpp__('ok = js_invoke(name.utf8_str(), 2, 0, s.utf8_str(), nullptr);');
		if (!ok && lastError().length > 0) log('[error] ' + name + '(str): ' + lastError());
		return ok;
	}

	/** (字符串, 数字) 回调：onTimerCompleted(tag, loopsLeft) */
	public static function callGlobalStrNum(name:String, s1:String, n1:Float):Bool
	{
		if (!isReady()) return false;
		var ok:Bool = false;
		untyped __cpp__('ok = js_invoke(name.utf8_str(), 3, (double)n1, s1.utf8_str(), nullptr);');
		if (!ok && lastError().length > 0) log('[error] ' + name + '(s,n): ' + lastError());
		return ok;
	}

	/** (字符串, 字符串) 回调：onTweenCompleted(tag, vars) 之类 */
	public static function callGlobalStrStr(name:String, s1:String, s2:String):Bool
	{
		if (!isReady()) return false;
		var ok:Bool = false;
		untyped __cpp__('ok = js_invoke(name.utf8_str(), 4, 0, s1.utf8_str(), s2.utf8_str());');
		if (!ok && lastError().length > 0) log('[error] ' + name + '(s,s): ' + lastError());
		return ok;
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

	@:keep static function fnum(v:String, def:Float = 0):Float
	{
		if (v == null || v.length == 0) return def;
		var f:Float = Std.parseFloat(v);
		return Math.isNaN(f) ? def : f;
	}

	@:keep static function inum(v:String, def:Int = 0):Int
	{
		if (v == null || v.length == 0) return def;
		var i:Null<Int> = Std.parseInt(v);
		return (i == null) ? def : i;
	}

	@:keep static function truthy(v:String):Bool
	{
		if (v == null) return false;
		var t:String = v.toLowerCase().trim();
		return t == 'true' || t == '1' || t == 'yes';
	}

	/**
	 * JS 侧包装：全部走 __host(编号, a, b, c, d, e, f)。
	 * 编号必须和下面 hostDispatch 的 case 一一对应。
	 */
	static inline var WRAPPERS:String = '
		const __h = (i, a, b, c, d, e, f) => __host(i,
			a === undefined ? "" : String(a), b === undefined ? "" : String(b),
			c === undefined ? "" : String(c), d === undefined ? "" : String(d),
			e === undefined ? "" : String(e), f === undefined ? "" : String(f));
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
		globalThis.getPropertyFromGroup = (g, i, v) => __h(11, g, i, v);
		globalThis.setPropertyFromGroup = (g, i, v, val) => __h(12, g, i, v, val);
		globalThis.getObjectOrder = (tag) => Number(__h(13, tag));
		globalThis.setObjectOrder = (tag, pos) => __h(14, tag, pos);
		globalThis.removeLuaSprite = (tag, destroy) => __h(15, tag, destroy);
		globalThis.setScrollFactor = (tag, x, y) => __h(16, tag, x, y);
		globalThis.cameraShake = (cam, intensity, duration) => __h(17, cam, intensity, duration);
		globalThis.cameraFlash = (cam, color, duration, forced) => __h(18, cam, color, duration, forced);
		globalThis.cameraFade = (cam, color, duration, forced, fadeOut) => __h(19, cam, color, duration, forced, fadeOut);
		globalThis.doTweenX = (tag, vars, val, dur, ease) => __h(20, tag, vars, val, dur, ease);
		globalThis.doTweenY = (tag, vars, val, dur, ease) => __h(21, tag, vars, val, dur, ease);
		globalThis.doTweenAngle = (tag, vars, val, dur, ease) => __h(22, tag, vars, val, dur, ease);
		globalThis.doTweenAlpha = (tag, vars, val, dur, ease) => __h(23, tag, vars, val, dur, ease);
		globalThis.doTweenZoom = (tag, cam, val, dur, ease) => __h(24, tag, cam, val, dur, ease);
		globalThis.doTweenColor = (tag, vars, color, dur, ease) => __h(25, tag, vars, color, dur, ease);
		globalThis.cancelTween = (tag) => __h(26, tag);
		globalThis.runTimer = (tag, time, loops) => __h(27, tag, time, loops);
		globalThis.cancelTimer = (tag) => __h(28, tag);
		globalThis.addAnimationByIndices = (tag, name, prefix, indices, fps) => __h(29, tag, name, prefix, indices, fps);
		globalThis.addOffset = (tag, x, y) => __h(30, tag, x, y);
		globalThis.setBlendMode = (tag, mode) => __h(31, tag, mode);
		globalThis.characterDance = (char) => __h(32, char);
		globalThis.addHealth = (v) => __h(33, v);
		globalThis.setHealth = (v) => __h(34, v);
		globalThis.getHealth = () => Number(__h(35));
		globalThis.triggerEvent = (name, v1, v2) => __h(36, name, v1, v2);
		globalThis.getSongPosition = () => Number(__h(37));
		globalThis.setGraphicSize = (tag, w, h) => __h(38, tag, w, h);
		globalThis.updateHitbox = (tag) => __h(39, tag);
		globalThis.makeGraphic = (tag, w, h, color) => __h(40, tag, w, h, color);
		globalThis.precacheImage = (tag) => __h(41, tag);
		globalThis.screenCenter = (tag, pos) => __h(42, tag, pos);
		globalThis.playMusic = (name, vol, loop) => __h(43, name, vol, loop);
	';

	/** 编号 → 实现。加函数只在这张表里加一行。 */
	@:keep static function hostDispatch(idx:Int, a:String, b:String, c:String, d:String, e:String, f:String):String
	{
		try {
			return dispatchInner(idx, a, b, c, d, e, f);
		} catch (err:Dynamic) {
			var m:String = '[error] host idx=$idx a=$a b=$b : ' + Std.string(err);
			Log.trace('[js] ' + m, null);
			log(m);
			return '';
		}
	}

	@:keep static function dispatchInner(idx:Int, a:String, b:String, c:String, d:String, e:String, f:String):String
	{
		switch (idx)
		{
			case -1: // trace / console.log
				Log.trace('[js] ' + a, null);
				log(a);
				return '';

			case 0: // getProperty
				var split:Array<String> = a.split('.');
				var v:Dynamic = (split.length > 1)
					? LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split, true), split[split.length - 1])
					: LuaUtils.getVarInArray(LuaUtils.getTargetInstance(), a);
				return Std.string(v);

			case 1: // setProperty
				var split1:Array<String> = a.split('.');
				if (split1.length > 1)
					LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split1, true), split1[split1.length - 1], coerce(b));
				else
					LuaUtils.setVarInArray(LuaUtils.getTargetInstance(), a, coerce(b));
				return b;

			case 2: // getPropertyFromClass
				var cls2:Dynamic = ScriptClassAliases.resolve(a);
				if (cls2 == null) return '';
				return Std.string(LuaUtils.getVarInArray(cls2, b));

			case 3: // setPropertyFromClass
				var cls3:Dynamic = ScriptClassAliases.resolve(a);
				if (cls3 == null) return '0';
				LuaUtils.setVarInArray(cls3, b, coerce(c));
				return c;

			case 4: // playSound
				var snd = Paths.sound(a);
				if (snd != null)
				{
					FlxG.sound.play(snd, fnum(b, 1));
					return '1';
				}
				return '0';

			case 5, 6: // makeLuaSprite / makeAnimatedLuaSprite
				var spr = new psychlua.ModchartSprite(fnum(c, 0), fnum(d, 0));
				if (b.length > 0)
				{
					if (idx == 5) spr.loadGraphic(Paths.image(b));
					else LuaUtils.loadFrames(spr, b, 'auto');
				}
				MusicBeatState.getVariables().set(a, spr);
				return '1';

			case 7: // addLuaSprite
				var spr7:Dynamic = MusicBeatState.getVariables().get(a);
				if (spr7 == null || PlayState.instance == null) return '0';
				PlayState.instance.add(spr7);
				return '1';

			case 8: // addAnimationByPrefix
				var o8:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o8 == null) return '0';
				var fps8:Int = inum(d, 24);
				if (fps8 <= 0) fps8 = 24;
				o8.animation.addByPrefix(b, c, fps8, true);
				return '1';

			case 9: // objectPlayAnimation
				var o9:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o9 == null) return '0';
				o9.animation.play(b, truthy(c));
				return '1';

			case 10: // setObjectCamera
				var o10:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o10 == null) return '0';
				if (!Std.isOfType(o10, flixel.FlxSprite)) return '0'; // 组 / Bar 这类没有 cameras 字段
				var sp10:flixel.FlxSprite = cast o10;
				sp10.cameras = [b == 'hud' ? PlayState.instance.camHUD : PlayState.instance.camGame];
				return '1';

			case 11: // getPropertyFromGroup
				var g11:Dynamic = Reflect.getProperty(LuaUtils.getTargetInstance(), a);
				if (g11 == null) return '';
				var item11:Dynamic = (g11.members != null) ? g11.members[inum(b, 0)] : g11[inum(b, 0)];
				if (item11 == null) return '';
				return Std.string(LuaUtils.getGroupStuff(item11, c, false));

			case 12: // setPropertyFromGroup
				var g12:Dynamic = Reflect.getProperty(LuaUtils.getTargetInstance(), a);
				if (g12 == null) return '0';
				var item12:Dynamic = (g12.members != null) ? g12.members[inum(b, 0)] : g12[inum(b, 0)];
				if (item12 == null) return '0';
				LuaUtils.setGroupStuff(item12, c, coerce(d), false);
				return '1';

			case 13: // getObjectOrder
				var obj13:Dynamic = LuaUtils.getObjectDirectly(a);
				if (obj13 == null) return '-1';
				var grp13:Dynamic = (psychlua.CustomSubstate.instance != null)
					? psychlua.CustomSubstate.instance : LuaUtils.getTargetInstance();
				if (grp13 == null || grp13.members == null) return '-1';
				var i13:Int = grp13.members.indexOf(obj13);
				if (i13 < 0)
				{
					// 1.0 把 healthBar / iconP1 塞进 uiGroup，按 members 查不到；
					// 给一个「在 UI 之上」的位置，否则 +1 之后会被舞台盖住
					var ui13:Dynamic = Reflect.getProperty(grp13, 'uiGroup');
					if (ui13 != null && ui13.members != null)
					{
						var s13:Int = ui13.members.indexOf(obj13);
						if (s13 >= 0) return Std.string(grp13.members.length + s13);
					}
				}
				return Std.string(i13);

			case 14: // setObjectOrder
				var obj14:Dynamic = LuaUtils.getObjectDirectly(a);
				if (obj14 == null) return '0';
				var grp14:Dynamic = LuaUtils.getTargetInstance();
				if (grp14 == null || grp14.members == null) return '0';
				var pos14:Int = inum(b, 0);
				if (pos14 < 0) pos14 = 0;
				if (pos14 > grp14.members.length) pos14 = grp14.members.length;
				grp14.remove(obj14, true);
				grp14.insert(pos14, obj14);
				return '1';

			case 15: // removeLuaSprite
				var spr15:Dynamic = LuaUtils.getObjectDirectly(a);
				if (spr15 == null) return '0';
				if (PlayState.instance != null)
				{
					PlayState.instance.remove(spr15, true);
					spr15.kill();
				}
				if (truthy(b) && spr15.destroy != null) spr15.destroy();
				MusicBeatState.getVariables().remove(a);
				return '1';

			case 16: // setScrollFactor
				var spr16:Dynamic = LuaUtils.getObjectDirectly(a);
				if (spr16 == null) return '0';
				var sx16:Float = fnum(b, 1);
				var sy16:Float = (c.length > 0) ? fnum(c, sx16) : sx16;
				spr16.scrollFactor.set(sx16, sy16);
				return '1';

			case 17, 18, 19: // cameraShake / cameraFlash / cameraFade
				var cam17 = LuaUtils.cameraFromString(a);
				if (cam17 == null) return '0';
				if (idx == 17) cam17.shake(fnum(b, 0.05), fnum(c, 0.5));
				else if (idx == 18) cam17.flash(CoolUtil.colorFromString(b), fnum(c, 1), null, truthy(d));
				else cam17.fade(CoolUtil.colorFromString(b), fnum(c, 1), truthy(e), null, truthy(d));
				return '1';

			case 20, 21, 22, 23, 24: // doTweenX / Y / Angle / Alpha / Zoom
				var target20:Dynamic = LuaUtils.tweenPrepare(a, b);
				if (target20 == null) return '0';
				var val20:Float = fnum(c, 0);
				var dur20:Float = fnum(d, 1);
				if (dur20 <= 0) dur20 = 1;
				var vars20:Dynamic = switch (idx)
				{
					case 20: {x: val20};
					case 21: {y: val20};
					case 22: {angle: val20};
					case 23: {alpha: val20};
					default: {zoom: val20};
				}
				tweenStore(a, FlxTween.tween(target20, vars20, dur20, {
					ease: LuaUtils.getTweenEaseByString(e),
					onComplete: function(_) onTweenDone(a, b)
				}));
				return '1';

			case 25: // doTweenColor
				var target25:Dynamic = LuaUtils.tweenPrepare(a, b);
				if (target25 == null) return '0';
				var from25:FlxColor = target25.color;
				from25.alphaFloat = target25.alpha;
				tweenStore(a, FlxTween.color(target25, fnum(d, 1), from25, CoolUtil.colorFromString(c), {
					ease: LuaUtils.getTweenEaseByString(e),
					onComplete: function(_) onTweenDone(a, b)
				}));
				return '1';

			case 26: // cancelTween
				if (PlayState.instance == null) return '0';
				var tw26:Dynamic = PlayState.instance.modchartTweens.get('tween_' + a);
				if (tw26 == null) return '0';
				tw26.cancel();
				PlayState.instance.modchartTweens.remove('tween_' + a);
				return '1';

			case 27: // runTimer
				if (PlayState.instance == null) return '0';
				var time27:Float = fnum(b, 1);
				if (time27 <= 0) time27 = 1;
				var loops27:Int = inum(c, 1);
				if (loops27 <= 0) loops27 = 1;
				var tag27:String = a;
				var tmr27:FlxTimer = new FlxTimer().start(time27, function(t) {
					JSPlayer.onTimerCompleted(tag27, loops27, Std.int(t.loopsLeft));
				}, loops27);
				PlayState.instance.modchartTimers.set('timer_' + tag27, tmr27);
				return '1';

			case 28: // cancelTimer
				if (PlayState.instance == null) return '0';
				var tmr28:Dynamic = PlayState.instance.modchartTimers.get('timer_' + a);
				if (tmr28 == null) return '0';
				tmr28.cancel();
				PlayState.instance.modchartTimers.remove('timer_' + a);
				return '1';

			case 29: // addAnimationByIndices
				var o29:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o29 == null) return '0';
				var idxs29:Array<Int> = [];
				for (part in d.split(','))
				{
					var n29:Null<Int> = Std.parseInt(part.trim());
					if (n29 != null) idxs29.push(n29);
				}
				if (idxs29.length == 0) return '0';
				var fps29:Int = inum(e, 24);
				if (fps29 <= 0) fps29 = 24;
				o29.animation.addByIndices(b, c, idxs29, '', fps29, false);
				return '1';

			case 30: // addOffset
				var o30:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o30 == null) return '0';
				o30.offset.set(fnum(b, 0), fnum(c, 0));
				return '1';

			case 31: // setBlendMode
				var o31:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o31 == null) return '0';
				o31.blend = switch (b.toLowerCase())
				{
					case 'add': flash.display.BlendMode.ADD;
					case 'multiply': flash.display.BlendMode.MULTIPLY;
					case 'screen': flash.display.BlendMode.SCREEN;
					case 'subtract': flash.display.BlendMode.SUBTRACT;
					case 'erase': flash.display.BlendMode.ERASE;
					case 'invert': flash.display.BlendMode.INVERT;
					case 'layer': flash.display.BlendMode.LAYER;
					case 'darken': flash.display.BlendMode.DARKEN;
					case 'lighten': flash.display.BlendMode.LIGHTEN;
					case 'difference': flash.display.BlendMode.DIFFERENCE;
					case 'overlay': flash.display.BlendMode.OVERLAY;
					case 'hardlight': flash.display.BlendMode.HARDLIGHT;
					default: flash.display.BlendMode.NORMAL;
				}
				return '1';

			case 32: // characterDance
				var ch32:Dynamic = null;
				if (PlayState.instance != null)
				{
					ch32 = switch (a.toLowerCase())
					{
						case 'boyfriend' | 'bf': PlayState.instance.boyfriend;
						case 'dad' | 'opponent': PlayState.instance.dad;
						case 'gf' | 'girlfriend': PlayState.instance.gf;
						default: null;
					}
				}
				if (ch32 == null) return '0';
				ch32.dance();
				return '1';

			case 33: // addHealth
				if (PlayState.instance == null) return '0';
				PlayState.instance.health = Math.max(0, Math.min(2, PlayState.instance.health + fnum(a, 0)));
				return Std.string(PlayState.instance.health);

			case 34: // setHealth
				if (PlayState.instance == null) return '0';
				PlayState.instance.health = Math.max(0, Math.min(2, fnum(a, 1)));
				return Std.string(PlayState.instance.health);

			case 35: // getHealth
				return (PlayState.instance != null) ? Std.string(PlayState.instance.health) : '';

			case 36: // triggerEvent
				if (PlayState.instance == null) return '0';
				PlayState.instance.triggerEvent(a, b, c, Conductor.songPosition);
				return '1';

			case 37: // getSongPosition
				return Std.string(Conductor.songPosition);

			case 38: // setGraphicSize
				var o38:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o38 == null) return '0';
				o38.setGraphicSize(fnum(b, 0), fnum(c, 0));
				return '1';

			case 39: // updateHitbox
				var o39:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o39 == null) return '0';
				o39.updateHitbox();
				return '1';

			case 40: // makeGraphic
				var g40 = new psychlua.ModchartSprite(fnum(c, 0), fnum(d, 0));
				g40.makeGraphic(inum(b, 1), inum(b, 1), CoolUtil.colorFromString(e), true);
				MusicBeatState.getVariables().set(a, g40);
				return '1';

			case 41: // precacheImage
				Paths.image(a);
				return '1';

			case 42: // screenCenter
				var o42:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o42 == null) return '0';
				o42.screenCenter(switch (b.toLowerCase())
				{
					case 'x': flixel.util.FlxAxes.X;
					case 'y': flixel.util.FlxAxes.Y;
					default: flixel.util.FlxAxes.XY;
				});
				return '1';

			case 43: // playMusic
				var mus = Paths.music(a);
				if (mus == null) return '0';
				FlxG.sound.playMusic(mus, fnum(b, 1), truthy(c));
				return '1';

			default:
				var m2:String = '[warn] 未实现的宿主函数编号 $idx (a=$a)';
				Log.trace('[js] ' + m2, null);
				log(m2);
				return '';
		}
	}

	// ---------------------------------------------------------------- tween 辅助
	static function tweenStore(tag:String, tw:FlxTween):Void
	{
		if (PlayState.instance == null || tw == null) return;
		PlayState.instance.modchartTweens.set('tween_' + tag, tw);
	}

	/** tween 结束：清表 + 回调 onTweenCompleted(tag, vars)，和 Lua 那边一致 */
	static function onTweenDone(tag:String, vars:String):Void
	{
		if (PlayState.instance != null) PlayState.instance.modchartTweens.remove('tween_' + tag);
		JSPlayer.onTweenCompleted(tag, vars);
	}

	// ---------------------------------------------------------------- 注册
	/** 注册 trace + 所有包装函数（一次 eval 搞定） */
	public static function installHostFunctions():Void
	{
		if (!isReady() && !init()) return;
		// 取地址必须在方法体里：此处 QuickJSHandler_obj 已经定义
		untyped __cpp__('g_host = (qjs_host_fn)::jsruntime::QuickJSHandler_obj::hostDispatch;');
		untyped __cpp__('
			JSValue g = JS_GetGlobalObject(g_js_ctx);
			JS_SetPropertyStr(g_js_ctx, g, "__host", JS_NewCFunction(g_js_ctx, qjs_host, "__host", 7));
			JS_SetPropertyStr(g_js_ctx, g, "console", JS_NewObject(g_js_ctx));
			JS_FreeValue(g_js_ctx, g);
		');
		eval(WRAPPERS + '\nconsole.log = trace; console.error = trace; console.warn = trace;', '<wrappers>');
	}
}
