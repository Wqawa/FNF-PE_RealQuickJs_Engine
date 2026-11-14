package jsruntime;

import haxe.Log;
import psychlua.LuaUtils;
import backend.Paths;
import backend.CoolUtil;
import backend.ScriptClassAliases;
import flixel.FlxG;
import flixel.util.FlxSave;
import flixel.util.FlxColor;
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

// setOnScripts 同步到 JS 全局：Lua 脚本一直能直接读 curBeat / curStep 这些，
// JS 侧没有这一步就完全对不上。
static void js_set_num(const char *name, double v) {
	if (g_js_ctx == nullptr) return;
	JSValue g = JS_GetGlobalObject(g_js_ctx);
	JS_SetPropertyStr(g_js_ctx, g, name, JS_NewFloat64(g_js_ctx, v));
	JS_FreeValue(g_js_ctx, g);
}
static void js_set_str(const char *name, const char *v) {
	if (g_js_ctx == nullptr) return;
	JSValue g = JS_GetGlobalObject(g_js_ctx);
	JS_SetPropertyStr(g_js_ctx, g, name, JS_NewString(g_js_ctx, v ? v : ""));
	JS_FreeValue(g_js_ctx, g);
}
static void js_set_bool(const char *name, bool v) {
	if (g_js_ctx == nullptr) return;
	JSValue g = JS_GetGlobalObject(g_js_ctx);
	JS_SetPropertyStr(g_js_ctx, g, name, JS_NewBool(g_js_ctx, v));
	JS_FreeValue(g_js_ctx, g);
}

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
//   mode 3 = (string, number)，4 = (string, string)，5 = (string, number, number)
static bool js_invoke(const char *name, int mode, double num, const char *str, const char *str2, double extra) {
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
		else if (mode == 5) {
			a[0] = JS_NewString(g_js_ctx, str ? str : "");
			a[1] = JS_NewFloat64(g_js_ctx, num);
			a[2] = JS_NewFloat64(g_js_ctx, extra);
			n = 3;
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
		untyped __cpp__('ok = js_invoke(name.utf8_str(), 0, 0, nullptr, nullptr, 0);');
		if (!ok && lastError().length > 0) log('[error] ' + name + '(): ' + lastError());
		return ok;
	}

	/** 一个数字参数的回调（onUpdate / onBeatHit / onStepHit …） */
	public static function callGlobalNum(name:String, v:Float):Bool
	{
		if (!isReady()) return false;
		var ok:Bool = false;
		untyped __cpp__('ok = js_invoke(name.utf8_str(), 1, (double)v, nullptr, nullptr, 0);');
		if (!ok && lastError().length > 0) log('[error] ' + name + '(num): ' + lastError());
		return ok;
	}

	/** 一个字符串参数的回调 */
	public static function callGlobalStr(name:String, s:String):Bool
	{
		if (!isReady()) return false;
		var ok:Bool = false;
		untyped __cpp__('ok = js_invoke(name.utf8_str(), 2, 0, s.utf8_str(), nullptr, 0);');
		if (!ok && lastError().length > 0) log('[error] ' + name + '(str): ' + lastError());
		return ok;
	}

	/** (字符串, 数字) 回调：onTimerCompleted(tag, loopsLeft) */
	public static function callGlobalStrNum(name:String, s1:String, n1:Float):Bool
	{
		if (!isReady()) return false;
		var ok:Bool = false;
		untyped __cpp__('ok = js_invoke(name.utf8_str(), 3, (double)n1, s1.utf8_str(), nullptr, 0);');
		if (!ok && lastError().length > 0) log('[error] ' + name + '(s,n): ' + lastError());
		return ok;
	}

	/** (字符串, 数字, 数字) 回调：onTimerCompleted(tag, loops, loopsLeft) */
	public static function callGlobalStrNumNum(name:String, s1:String, n1:Float, n2:Float):Bool
	{
		if (!isReady()) return false;
		var ok:Bool = false;
		untyped __cpp__('ok = js_invoke(name.utf8_str(), 5, (double)n1, s1.utf8_str(), nullptr, (double)n2);');
		if (!ok && lastError().length > 0) log('[error] ' + name + '(s,n,n): ' + lastError());
		return ok;
	}

	/** (字符串, 字符串) 回调：onTweenCompleted(tag, vars) 之类 */
	public static function callGlobalStrStr(name:String, s1:String, s2:String):Bool
	{
		if (!isReady()) return false;
		var ok:Bool = false;
		untyped __cpp__('ok = js_invoke(name.utf8_str(), 4, 0, s1.utf8_str(), s2.utf8_str(), 0);');
		if (!ok && lastError().length > 0) log('[error] ' + name + '(s,s): ' + lastError());
		return ok;
	}

	/** setOnScripts 的 JS 侧同步：数字 / 布尔 / 字符串 都能落进全局 */
	public static function setGlobal(name:String, v:Dynamic):Void
	{
		if (!isReady()) return;
		if (v == null) return;
		if (Std.isOfType(v, Bool))
		{
			untyped __cpp__('js_set_bool(name.utf8_str(), v);');
		}
		else if (Std.isOfType(v, Int) || Std.isOfType(v, Float))
		{
			untyped __cpp__('js_set_num(name.utf8_str(), (double)v);');
		}
		else
		{
			var sv:String = Std.string(v);
			untyped __cpp__('js_set_str(name.utf8_str(), sv.utf8_str());');
		}
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
		globalThis.playSound = (name, vol, tag, loop) => __h(4, name, vol, tag, loop);
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
		globalThis.getRandomInt = (a, b) => Number(__h(44, a, b));
		globalThis.getRandomFloat = (a, b) => Number(__h(45, a, b));
		globalThis.getRandomBool = (chance) => __h(46, chance) === "1";
		globalThis.stringSplit = (s, sep) => __h(47, s, sep).split(String.fromCharCode(1));
		globalThis.stringTrim = (s) => __h(48, s);
		globalThis.stringStartsWith = (s, p) => __h(49, s, p) === "1";
		globalThis.stringEndsWith = (s, p) => __h(50, s, p) === "1";
		globalThis.FlxColor = (c) => Number(__h(51, c));
		globalThis.getColorFromHex = (c) => Number(__h(51, c));
		globalThis.getColorFromName = (c) => Number(__h(52, c));
		globalThis.getColorFromString = (c) => Number(__h(53, c));
		globalThis.getScore = () => Number(__h(54));
		globalThis.setScore = (v) => __h(55, v);
		globalThis.addScore = (v) => __h(56, v);
		globalThis.getMisses = () => Number(__h(57));
		globalThis.setMisses = (v) => __h(58, v);
		globalThis.addMisses = (v) => __h(59, v);
		globalThis.getHits = () => Number(__h(60));
		globalThis.setHits = (v) => __h(61, v);
		globalThis.addHits = (v) => __h(62, v);
		globalThis.updateScoreText = () => __h(63);
		globalThis.setRatingPercent = (v) => __h(64, v);
		globalThis.setRatingName = (v) => __h(65, v);
		globalThis.setRatingFC = (v) => __h(66, v);
		globalThis.getCharacterX = (c) => Number(__h(67, c));
		globalThis.setCharacterX = (c, v) => __h(68, c, v);
		globalThis.getCharacterY = (c) => Number(__h(69, c));
		globalThis.setCharacterY = (c, v) => __h(70, c, v);
		globalThis.characterPlayAnim = (c, a, f) => __h(71, c, a, f);
		globalThis.getCameraScrollX = (c) => Number(__h(72, c));
		globalThis.getCameraScrollY = (c) => Number(__h(73, c));
		globalThis.setCameraScroll = (c, x, y) => __h(74, c, x, y);
		globalThis.addCameraScroll = (c, x, y) => __h(75, c, x, y);
		globalThis.getCameraFollowX = (c) => Number(__h(76, c));
		globalThis.getCameraFollowY = (c) => Number(__h(77, c));
		globalThis.setCameraFollowPoint = (c, x, y) => __h(78, c, x, y);
		globalThis.addCameraFollowPoint = (c, x, y) => __h(79, c, x, y);
		globalThis.cameraSetTarget = (c, t) => __h(80, c, t);
		globalThis.luaSpriteExists = (t) => __h(81, t) === "1";
		globalThis.luaTextExists = (t) => __h(82, t) === "1";
		globalThis.luaSoundExists = (t) => __h(83, t) === "1";
		globalThis.objectsOverlap = (a, b) => __h(84, a, b) === "1";
		globalThis.scaleObject = (t, x, y, u) => __h(85, t, x, y, u);
		globalThis.scaleLuaSprite = (t, x, y) => __h(85, t, x, y, "true");
		globalThis.playAnim = (t, a, f) => __h(86, t, a, f);
		globalThis.noteTweenX = (t, n, v, d, e) => __h(87, t, n, v, d, e);
		globalThis.noteTweenY = (t, n, v, d, e) => __h(88, t, n, v, d, e);
		globalThis.noteTweenAngle = (t, n, v, d, e) => __h(89, t, n, v, d, e);
		globalThis.noteTweenAlpha = (t, n, v, d, e) => __h(90, t, n, v, d, e);
		globalThis.noteTweenDirection = (t, n, v, d, e) => __h(91, t, n, v, d, e);
		globalThis.noteTweenScale = (t, n, v, d, e) => __h(92, t, n, v, d, e);
		globalThis.getSoundVolume = (t) => Number(__h(93, t));
		globalThis.setSoundVolume = (t, v) => __h(94, t, v);
		globalThis.getSoundTime = (t) => Number(__h(95, t));
		globalThis.setSoundTime = (t, v) => __h(96, t, v);
		globalThis.getSoundPitch = (t) => Number(__h(97, t));
		globalThis.setSoundPitch = (t, v) => __h(98, t, v);
		globalThis.pauseSound = (t) => __h(99, t);
		globalThis.resumeSound = (t) => __h(100, t);
		globalThis.stopSound = (t) => __h(101, t);
		globalThis.soundFadeIn = (t, d, f, to) => __h(102, t, d, f, to);
		globalThis.soundFadeOut = (t, d, to) => __h(103, t, d, to);
		globalThis.soundFadeCancel = (t) => __h(104, t);
		globalThis.musicFadeIn = (d, f, to) => __h(105, d, f, to);
		globalThis.musicFadeOut = (d, to) => __h(106, d, to);
		globalThis.precacheSound = (t) => __h(107, t);
		globalThis.precacheMusic = (t) => __h(108, t);
		globalThis.addToGroup = (g, t, i) => __h(109, g, t, i);
		globalThis.removeFromGroup = (g, i) => __h(110, g, i);
		globalThis.updateHitboxFromGroup = (g, i) => __h(111, g, i);
		globalThis.getMidpointX = (t) => Number(__h(112, t));
		globalThis.getMidpointY = (t) => Number(__h(113, t));
		globalThis.getGraphicMidpointX = (t) => Number(__h(114, t));
		globalThis.getGraphicMidpointY = (t) => Number(__h(115, t));
		globalThis.getScreenPositionX = (t, c) => Number(__h(116, t, c));
		globalThis.getScreenPositionY = (t, c) => Number(__h(117, t, c));
		globalThis.getMouseX = (c) => Number(__h(118, c));
		globalThis.getMouseY = (c) => Number(__h(119, c));
		globalThis.mouseClicked = (b) => __h(120, b) === "1";
		globalThis.mousePressed = (b) => __h(121, b) === "1";
		globalThis.mouseReleased = (b) => __h(122, b) === "1";
		globalThis.keyJustPressed = (k) => __h(123, k) === "1";
		globalThis.keyPressed = (k) => __h(124, k) === "1";
		globalThis.keyReleased = (k) => __h(125, k) === "1";
		globalThis.debugPrint = (t, c) => __h(126, t, c);
		globalThis.checkFileExists = (p) => __h(127, p) === "1";
		globalThis.getTextFromFile = (p) => __h(128, p);
		globalThis.readJson = (p) => __h(129, p);
		globalThis.startCountdown = () => __h(130);
		globalThis.endSong = () => __h(131);
		globalThis.restartSong = () => __h(132);
		globalThis.exitSong = () => __h(133);
		globalThis.addCharacterToList = (n, t) => __h(134, n, t);
		globalThis.setHealthBarColors = (l, r) => __h(135, l, r);
		globalThis.setTimeBarColors = (l, r) => __h(136, l, r);
		globalThis.getPixelColor = (t, x, y) => Number(__h(137, t, x, y));
		globalThis.makeLuaText = (t, s, w, x, y) => __h(138, t, s, w, x, y);
		globalThis.setTextString = (t, s) => __h(139, t, s) === "1";
		globalThis.setTextSize = (t, v) => __h(140, t, v) === "1";
		globalThis.setTextWidth = (t, v) => __h(141, t, v) === "1";
		globalThis.setTextFont = (t, f) => __h(142, t, f) === "1";
		globalThis.setTextColor = (t, c) => __h(143, t, c) === "1";
		globalThis.setTextBorder = (t, s, c, st) => __h(144, t, s, c, st) === "1";
		globalThis.setTextAlignment = (t, a) => __h(145, t, a) === "1";
		globalThis.setTextAutoSize = (t, v) => __h(146, t, v) === "1";
		globalThis.setTextItalic = (t, v) => __h(147, t, v) === "1";
		globalThis.setTextHeight = (t, v) => __h(148, t, v) === "1";
		globalThis.getTextString = (t) => __h(149, t);
		globalThis.getTextWidth = (t) => Number(__h(150, t));
		globalThis.getTextSize = (t) => Number(__h(151, t));
		globalThis.getTextFont = (t) => __h(152, t);
		globalThis.removeLuaText = (t, d) => __h(153, t, d);
		globalThis.keyboardJustPressed = (k) => __h(154, k) === "1";
		globalThis.keyboardPressed = (k) => __h(155, k) === "1";
		globalThis.keyboardReleased = (k) => __h(156, k) === "1";
		globalThis.gamepadAnalogX = (id, left) => Number(__h(157, id, left));
		globalThis.gamepadAnalogY = (id, left) => Number(__h(158, id, left));
		globalThis.gamepadJustPressed = (id, n) => __h(159, id, n) === "1";
		globalThis.gamepadPressed = (id, n) => __h(160, id, n) === "1";
		globalThis.gamepadReleased = (id, n) => __h(161, id, n) === "1";
		globalThis.initSaveData = (n) => __h(162, n) === "1";
		globalThis.getDataFromSave = (n, f) => __h(163, n, f);
		globalThis.setDataFromSave = (n, f, v) => __h(164, n, f, v);
		globalThis.flushSaveData = (n) => __h(165, n) === "1";
		globalThis.eraseSaveData = (n) => __h(166, n) === "1";
		globalThis.loadGraphic = (t, img, gx, gy) => __h(167, t, img, gx, gy) === "1";
		globalThis.addAnimationByIndicesLoop = (t, n, p, i, f) => __h(168, t, n, p, i, f);
		globalThis.addLuaText = (t) => __h(169, t) === "1";
		globalThis.loadFrames = (t, img, ty) => __h(170, t, img, ty) === "1";
		globalThis.loadMultipleFrames = (t, imgs) => __h(171, t, imgs) === "1";
		globalThis.makeFlxAnimateSprite = (t, x, y, f) => __h(172, t, x, y, f);
		globalThis.loadAnimateAtlas = (t, f, sj, aj) => __h(173, t, f, sj, aj);
		globalThis.addAnimationBySymbol = (t, n, sym, fps, loop, mx) => __h(174, t, n, sym, fps, loop, mx) === "1";
		globalThis.addAnimationBySymbolIndices = (t, n, sym, idx, fps, loop) => __h(175, t, n, sym, idx, fps, loop) === "1";
		globalThis.addAnimation = (t, n, frames, fps, loop) => __h(176, t, n, frames, fps, loop);
		globalThis.luaSpriteMakeGraphic = (t, w, h, c) => __h(177, t, w, h, c);
		globalThis.luaSpriteAddAnimationByPrefix = (t, n, p, fps) => __h(178, t, n, p, fps);
		globalThis.luaSpriteAddAnimationByIndices = (t, n, p, idx, fps) => __h(179, t, n, p, idx, fps);
		globalThis.luaSpritePlayAnimation = (t, n, f) => __h(180, t, n, f);
		globalThis.setLuaSpriteCamera = (t, c) => __h(181, t, c);
		globalThis.setLuaSpriteScrollFactor = (t, x, y) => __h(182, t, x, y);
		globalThis.getPropertyLuaSprite = (t, v) => __h(183, t, v);
		globalThis.setPropertyLuaSprite = (t, v, val) => __h(184, t, v, val);
		globalThis.addLuaScript = (f, ig) => __h(185, f, ig) === "1";
		globalThis.removeLuaScript = (f) => __h(186, f) === "1";
		globalThis.addHScript = (f, ig) => __h(187, f, ig) === "1";
		globalThis.removeHScript = (f) => __h(188, f) === "1";
		globalThis.isRunning = (f) => __h(189, f) === "1";
		globalThis.getRunningScripts = () => __h(190).split(String.fromCharCode(1)).filter(s => s.length > 0);
		globalThis.callScript = (s, f, a1) => __h(191, s, f, a1);
		globalThis.callMethod = (f, a1) => __h(192, f, a1);
		globalThis.callMethodFromClass = (c, m) => __h(193, c, m);
		globalThis.createInstance = (c) => __h(194, c);
		globalThis.getVar = (n) => __h(195, n);
		globalThis.setVar = (n, v) => __h(196, n, v);
		globalThis.getGlobalFromScript = (s, n) => __h(197, s, n);
		globalThis.setGlobalFromScript = (s, n, v) => __h(198, s, n, v);
		globalThis.addInstance = (c, tag) => __h(199, c, tag);
		globalThis.instanceArg = (n) => __h(200, n);
		globalThis.getShaderFloat = (o, p) => Number(__h(201, o, p));
		globalThis.setShaderFloat = (o, p, v) => __h(202, o, p, v) === "1";
		globalThis.getShaderInt = (o, p) => Number(__h(203, o, p));
		globalThis.setShaderInt = (o, p, v) => __h(204, o, p, v) === "1";
		globalThis.getShaderBool = (o, p) => __h(205, o, p) === "1";
		globalThis.setShaderBool = (o, p, v) => __h(206, o, p, v) === "1";
		globalThis.getShaderFloatArray = (o, p) => __h(207, o, p).split(String.fromCharCode(1)).map(Number);
		globalThis.setShaderFloatArray = (o, p, v) => __h(208, o, p, Array.isArray(v) ? v.join(",") : v) === "1";
		globalThis.getShaderIntArray = (o, p) => __h(209, o, p).split(String.fromCharCode(1)).map(Number);
		globalThis.setShaderIntArray = (o, p, v) => __h(210, o, p, Array.isArray(v) ? v.join(",") : v) === "1";
		globalThis.getShaderBoolArray = (o, p) => __h(211, o, p).split(String.fromCharCode(1)).map(s => s === "1");
		globalThis.setShaderBoolArray = (o, p, v) => __h(212, o, p, Array.isArray(v) ? v.join(",") : v) === "1";
		globalThis.setShaderSampler2D = (o, p, img) => __h(213, o, p, img) === "1";
		globalThis.removeSpriteShader = (o) => __h(214, o) === "1";
		globalThis.anyGamepadJustPressed = (n) => __h(215, n) === "1";
		globalThis.anyGamepadPressed = (n) => __h(216, n) === "1";
		globalThis.anyGamepadReleased = (n) => __h(217, n) === "1";
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

			case 4: // playSound(sound, volume, tag, loop)
				var snd = Paths.sound(a);
				if (snd == null) return '0';
				var vol4:Float = fnum(b, 1);
				var loop4:Bool = truthy(d);
				if (c != null && c.length > 0)
				{
					var key4:String = LuaUtils.formatVariable('sound_' + c);
					var old4:Dynamic = MusicBeatState.getVariables().get(key4);
					if (old4 != null)
					{
						old4.stop();
						old4.destroy();
					}
					var orig4:String = c;
					MusicBeatState.getVariables().set(key4,
						FlxG.sound.play(snd, vol4, loop4, null, true, function() {
							if (!loop4) MusicBeatState.getVariables().remove(key4);
							JSPlayer.forward('onSoundFinished', [orig4]);
						}));
					return key4;
				}
				FlxG.sound.play(snd, vol4);
				return '1';

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
				LuaUtils.cancelTween(a);
				return '1';

			case 27: // runTimer
				if (PlayState.instance == null) return '0';
				LuaUtils.cancelTimer(a);
				var time27:Float = fnum(b, 1);
				if (time27 <= 0) time27 = 1;
				var loops27:Int = inum(c, 1);
				if (loops27 <= 0) loops27 = 1;
				var orig27:String = a;
				var key27:String = LuaUtils.formatVariable('timer_' + a);
				var tmr27:FlxTimer = new FlxTimer().start(time27, function(t) {
					if (t.finished) vars().remove(key27);
					JSPlayer.onTimerCompleted(orig27, t.loops, Std.int(t.loopsLeft));
				}, loops27);
				vars().set(key27, tmr27);
				return key27;

			case 28: // cancelTimer
				LuaUtils.cancelTimer(a);
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
				PlayState.instance.health += fnum(a, 0);
				return Std.string(PlayState.instance.health);

			case 34: // setHealth
				if (PlayState.instance == null) return '0';
				PlayState.instance.health = fnum(a, 1);
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


			// ---- 44..50 随机 / 字符串
			case 44: return Std.string(FlxG.random.int(inum(a, 0), inum(b, 10)));
			case 45: return Std.string(FlxG.random.float(fnum(a, 0), fnum(b, 1)));
			case 46: return FlxG.random.bool(inum(a, 50)) ? '1' : '0';
			case 47: return a.split(b.length > 0 ? b : ',').join(String.fromCharCode(1));
			case 48: return StringTools.trim(a);
			case 49: return StringTools.startsWith(a, b) ? '1' : '0';
			case 50: return StringTools.endsWith(a, b) ? '1' : '0';

			// ---- 51..53 颜色（Lua 侧也是 FlxColor.fromString）
			case 51: return Std.string(FlxColor.fromString('#' + a));
			case 52, 53: return Std.string(FlxColor.fromString(a));

			// ---- 54..66 分数 / 评价
			case 54: return Std.string(PlayState.instance != null ? PlayState.instance.songScore : 0);
			case 55:
				if (PlayState.instance == null) return '0';
				PlayState.instance.songScore = inum(a, 0);
				PlayState.instance.RecalculateRating();
				return '1';
			case 56:
				if (PlayState.instance == null) return '0';
				PlayState.instance.songScore += inum(a, 0);
				PlayState.instance.RecalculateRating();
				return '1';
			case 57: return Std.string(PlayState.instance != null ? PlayState.instance.songMisses : 0);
			case 58:
				if (PlayState.instance == null) return '0';
				PlayState.instance.songMisses = inum(a, 0);
				PlayState.instance.RecalculateRating();
				return '1';
			case 59:
				if (PlayState.instance == null) return '0';
				PlayState.instance.songMisses += inum(a, 0);
				PlayState.instance.RecalculateRating();
				return '1';
			case 60: return Std.string(PlayState.instance != null ? PlayState.instance.songHits : 0);
			case 61:
				if (PlayState.instance == null) return '0';
				PlayState.instance.songHits = inum(a, 0);
				PlayState.instance.RecalculateRating();
				return '1';
			case 62:
				if (PlayState.instance == null) return '0';
				PlayState.instance.songHits += inum(a, 0);
				PlayState.instance.RecalculateRating();
				return '1';
			case 63:
				if (PlayState.instance == null) return '0';
				PlayState.instance.updateScoreText();
				return '1';
			case 64:
				if (PlayState.instance == null) return '0';
				PlayState.instance.ratingPercent = fnum(a, 1);
				return '1';
			case 65:
				if (PlayState.instance == null) return '0';
				PlayState.instance.ratingName = a;
				return '1';
			case 66:
				if (PlayState.instance == null) return '0';
				PlayState.instance.ratingFC = a;
				return '1';

			// ---- 67..71 角色
			case 67, 69:
				var ch67:Dynamic = charOf(a);
				if (ch67 == null) return '0';
				return Std.string(idx == 67 ? ch67.x : ch67.y);
			case 68:
				var ch68:Dynamic = charOf(a);
				if (ch68 == null) return '0';
				ch68.x = fnum(b, 0);
				return '1';
			case 70:
				var ch70:Dynamic = charOf(a);
				if (ch70 == null) return '0';
				ch70.y = fnum(b, 0);
				return '1';
			case 71:
				var ch71:Dynamic = charOf(a);
				if (ch71 == null) return '0';
				ch71.playAnim(b, truthy(c));
				return '1';

			// ---- 72..80 相机
			case 72, 73:
				var cam72:FlxCamera = LuaUtils.cameraFromString(a);
				if (cam72 == null) return '0';
				return Std.string(idx == 72 ? cam72.scroll.x : cam72.scroll.y);
			case 74:
				var cam74:FlxCamera = LuaUtils.cameraFromString(a);
				if (cam74 == null) return '0';
				cam74.scroll.set(fnum(b, 0), fnum(c, 0));
				return '1';
			case 75:
				var cam75:FlxCamera = LuaUtils.cameraFromString(a);
				if (cam75 == null) return '0';
				cam75.scroll.x += fnum(b, 0);
				cam75.scroll.y += fnum(c, 0);
				return '1';
			case 76, 77:
				if (PlayState.instance == null) return '0';
				return Std.string(idx == 76 ? PlayState.instance.camFollow.x : PlayState.instance.camFollow.y);
			case 78:
				if (PlayState.instance == null) return '0';
				PlayState.instance.camFollow.setPosition(fnum(b, 0), fnum(c, 0));
				return '1';
			case 79:
				if (PlayState.instance == null) return '0';
				PlayState.instance.camFollow.x += fnum(b, 0);
				PlayState.instance.camFollow.y += fnum(c, 0);
				return '1';
			case 80:
				var cam80:FlxCamera = LuaUtils.cameraFromString(a);
				var tgt80:Dynamic = charOf(b);
				if (cam80 == null || tgt80 == null) return '0';
				cam80.follow(tgt80);
				return '1';

			// ---- 81..83 存在性（跟 Lua 一样按类型判定，不是看键在不在）
			case 81:
				var o81:Dynamic = vars().get(a);
				return (o81 != null && Std.isOfType(o81, psychlua.ModchartSprite)) ? '1' : '0';
			case 82:
				var o82:Dynamic = vars().get(a);
				return (o82 != null && Std.isOfType(o82, flixel.text.FlxText)) ? '1' : '0';
			case 83:
				var o83:Dynamic = vars().get('sound_' + a);
				return (o83 != null && Std.isOfType(o83, flixel.sound.FlxSound)) ? '1' : '0';

			// ---- 84..86 物体杂项
			case 84:
				var o1:Dynamic = LuaUtils.getObjectDirectly(a);
				var o2:Dynamic = LuaUtils.getObjectDirectly(b);
				if (o1 == null || o2 == null) return '0';
				return FlxG.overlap(o1, o2) ? '1' : '0';
			case 85:
				var o85:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o85 == null) return '0';
				o85.scale.set(fnum(b, 1), fnum(c, 1));
				if (d.length == 0 || truthy(d)) o85.updateHitbox();
				return '1';
			case 86:
				var o86:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o86 == null) return '0';
				o86.animation.play(b, truthy(c));
				return '1';

			// ---- 87..92 noteTween（和 Lua 一样打 StrumNote，存同一个键名）
			case 87, 88, 89, 90, 91, 92:
				if (PlayState.instance == null) return '0';
				var strums = PlayState.instance.strumLineNotes;
				if (strums == null || strums.length == 0) return '0';
				var note87:Int = inum(b, 0);
				var strum87:Dynamic = strums.members[note87 % strums.length];
				if (strum87 == null) return '0';
				var val87:Float = fnum(c, 0);
				var dur87:Float = fnum(d, 1);
				if (dur87 <= 0) dur87 = 1;
				var tgt87:Dynamic = strum87;
				var data87:Dynamic = switch (idx)
				{
					case 87: {x: val87};
					case 88: {y: val87};
					case 89: {angle: val87};
					case 90: {alpha: val87};
					case 91: {direction: val87};
					default: {x: val87, y: val87};
				}
				if (idx == 92) tgt87 = strum87.scale;
				tweenStore(a, FlxTween.tween(tgt87, data87, dur87, {
					ease: LuaUtils.getTweenEaseByString(e),
					onComplete: function(_) onTweenDone(a, Std.string(note87))
				}));
				return '1';

			// ---- 93..108 声音
			case 93:
				var s93:Dynamic = soundOf(a);
				if (s93 == null) return '0';
				var fs93:flixel.sound.FlxSound = cast s93;
				return Std.string(fs93.volume);
			case 94:
				var s94:Dynamic = soundOf(a);
				if (s94 == null) return '0';
				s94.volume = fnum(b, 1);
				return '1';
			case 95:
				var s95:Dynamic = soundOf(a);
				if (s95 == null) return '0';
				var fs95:flixel.sound.FlxSound = cast s95;
				return Std.string(fs95.time);
			case 96:
				var s96:Dynamic = soundOf(a);
				if (s96 == null) return '0';
				s96.time = fnum(b, 0);
				return '1';
			case 97:
				var s97:Dynamic = soundOf(a);
				if (s97 == null) return '1';
				var fs97:flixel.sound.FlxSound = cast s97;
				return Std.string(fs97.pitch);
			case 98:
				var s98:Dynamic = soundOf(a);
				if (s98 == null) return '0';
				s98.pitch = fnum(b, 1);
				return '1';
			case 99:
				var s99:Dynamic = soundOf(a);
				if (s99 == null) return '0';
				s99.pause();
				return '1';
			case 100:
				var s100:Dynamic = soundOf(a);
				if (s100 == null) return '0';
				s100.resume();
				return '1';
			case 101:
				var s101:Dynamic = soundOf(a);
				if (s101 == null) return '0';
				s101.stop();
				if (a != null && a.length > 0) vars().remove(LuaUtils.formatVariable('sound_' + a));
				return '1';
			case 102:
				var s102:Dynamic = soundOf(a);
				if (s102 == null) return '0';
				s102.fadeIn(fnum(b, 1), fnum(c, 0), fnum(d, 1));
				return '1';
			case 103:
				var s103:Dynamic = soundOf(a);
				if (s103 == null) return '0';
				s103.fadeOut(fnum(b, 1), fnum(c, 0));
				return '1';
			case 104:
				var s104:Dynamic = soundOf(a);
				if (s104 != null && s104.fadeTween != null) s104.fadeTween.cancel();
				return '1';
			case 105:
				if (FlxG.sound.music == null) return '0';
				FlxG.sound.music.fadeIn(fnum(a, 1), fnum(b, 0), fnum(c, 1));
				return '1';
			case 106:
				if (FlxG.sound.music == null) return '0';
				FlxG.sound.music.fadeOut(fnum(a, 1), fnum(b, 0));
				return '1';
			case 107:
				Paths.sound(a);
				return '1';
			case 108:
				Paths.music(a);
				return '1';

			// ---- 109..111 组
			case 109:
				var g109:Dynamic = Reflect.getProperty(LuaUtils.getTargetInstance(), a);
				var o109:Dynamic = LuaUtils.getObjectDirectly(b);
				if (g109 == null || o109 == null) return '0';
				var pos109:Int = inum(c, -1);
				if (pos109 < 0) g109.add(o109);
				else g109.insert(pos109, o109);
				return '1';
			case 110:
				var g110:Dynamic = Reflect.getProperty(LuaUtils.getTargetInstance(), a);
				if (g110 == null) return '0';
				var item110:Dynamic = (g110.members != null) ? g110.members[inum(b, 0)] : g110[inum(b, 0)];
				if (item110 == null) return '0';
				if (g110.members != null) g110.remove(item110, true);
				else g110.remove(item110);
				return '1';
			case 111:
				var g111:Dynamic = Reflect.getProperty(LuaUtils.getTargetInstance(), a);
				if (g111 == null) return '0';
				var item111:Dynamic = (g111.members != null) ? g111.members[inum(b, 0)] : g111[inum(b, 0)];
				if (item111 == null) return '0';
				item111.updateHitbox();
				return '1';

			// ---- 112..119 中点 / 屏幕位置 / 鼠标
			case 112, 113:
				var o112:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o112 == null) return '0';
				return Std.string(idx == 112 ? o112.getMidpoint().x : o112.getMidpoint().y);
			case 114, 115:
				var o114:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o114 == null) return '0';
				return Std.string(idx == 114 ? o114.getGraphicMidpoint().x : o114.getGraphicMidpoint().y);
			case 116, 117:
				var o116:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o116 == null) return '0';
				var cam116:FlxCamera = LuaUtils.cameraFromString(b.length > 0 ? b : 'game');
				var pos116:Dynamic = o116.getScreenPosition(cam116);
				return Std.string(idx == 116 ? pos116.x : pos116.y);
			case 118, 119:
				var cam118:FlxCamera = LuaUtils.cameraFromString(a.length > 0 ? a : 'game');
				var pos118:Dynamic = FlxG.mouse.getScreenPosition(cam118);
				return Std.string(idx == 118 ? pos118.x : pos118.y);

			// ---- 120..125 鼠标 / 键盘
			case 120:
				return switch (a.toLowerCase())
				{
					case 'middle': FlxG.mouse.justPressedMiddle ? '1' : '0';
					case 'right': FlxG.mouse.justPressedRight ? '1' : '0';
					default: FlxG.mouse.justPressed ? '1' : '0';
				};
			case 121:
				return switch (a.toLowerCase())
				{
					case 'middle': FlxG.mouse.pressedMiddle ? '1' : '0';
					case 'right': FlxG.mouse.pressedRight ? '1' : '0';
					default: FlxG.mouse.pressed ? '1' : '0';
				};
			case 122:
				return switch (a.toLowerCase())
				{
					case 'middle': FlxG.mouse.justReleasedMiddle ? '1' : '0';
					case 'right': FlxG.mouse.justReleasedRight ? '1' : '0';
					default: FlxG.mouse.justReleased ? '1' : '0';
				};
			case 123, 124, 125:
				var ks:Dynamic = switch (idx)
				{
					case 123: FlxG.keys.justPressed;
					case 124: FlxG.keys.pressed;
					default: FlxG.keys.justReleased;
				};
				var k123:Dynamic = Reflect.getProperty(ks, a.toUpperCase());
				return (k123 == true) ? '1' : '0';

			// ---- 126..129 文件
			case 126:
				if (PlayState.instance == null) return '0';
				var col126:FlxColor = (b.length > 0) ? CoolUtil.colorFromString(b) : FlxColor.WHITE;
				PlayState.instance.addTextToDebug(a, col126);
				return '1';
			case 127: return sys.FileSystem.exists(a) ? '1' : '0';
			case 128: return sys.FileSystem.exists(a) ? sys.io.File.getContent(a) : '';
			case 129: return sys.FileSystem.exists(a) ? sys.io.File.getContent(a) : '';

			// ---- 130..132 歌曲控制
			case 130:
				if (PlayState.instance == null) return '0';
				PlayState.instance.startCountdown();
				return '1';
			case 131:
				if (PlayState.instance == null) return '0';
				PlayState.instance.KillNotes();
				PlayState.instance.endSong();
				return '1';
			case 132:
				if (PlayState.instance == null) return '0';
				PlayState.instance.persistentUpdate = false;
				FlxG.camera.followLerp = 0;
				substates.PauseSubState.restartSong(false);
				return '1';

			// ---- 134..137 其它
			case 134:
				if (PlayState.instance == null) return '0';
				var type134:Int = switch (b.toLowerCase())
				{
					case 'dad': 1;
					case 'gf' | 'girlfriend': 2;
					default: 0;
				}
				PlayState.instance.addCharacterToList(a, type134);
				return '1';
			case 135:
				if (PlayState.instance == null || PlayState.instance.healthBar == null) return '0';
				PlayState.instance.healthBar.setColors(
					a.length > 0 ? CoolUtil.colorFromString(a) : null,
					b.length > 0 ? CoolUtil.colorFromString(b) : null);
				return '1';
			case 136:
				if (PlayState.instance == null || PlayState.instance.timeBar == null) return '0';
				PlayState.instance.timeBar.setColors(
					a.length > 0 ? CoolUtil.colorFromString(a) : null,
					b.length > 0 ? CoolUtil.colorFromString(b) : null);
				return '1';
			case 137:
				var o137:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o137 == null || o137.pixels == null) return '0';
				return Std.string(o137.pixels.getPixel32(inum(b, 0), inum(c, 0)));


			// ---- 138..153 文本（跟 TextFunctions.hx 同一套语义）
			case 138: // makeLuaText
				var t138:String = a.replace('.', '');
				LuaUtils.destroyObject(t138);
				var t:flixel.text.FlxText = new flixel.text.FlxText(fnum(d, 0), fnum(e, 0), inum(c, 0), b, 16);
				t.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE,
					flixel.text.FlxText.FlxTextAlign.CENTER,
					flixel.text.FlxText.FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				if (PlayState.instance != null) t.cameras = [PlayState.instance.camHUD];
				t.scrollFactor.set();
				t.borderSize = 2;
				vars().set(t138, t);
				return '1';

			case 139:
				var o139:flixel.text.FlxText = textObj(a);
				if (o139 == null) return '0';
				o139.text = b;
				return '1';

			case 140:
				var o140:flixel.text.FlxText = textObj(a);
				if (o140 == null) return '0';
				o140.size = inum(b, 16);
				return '1';

			case 141:
				var o141:flixel.text.FlxText = textObj(a);
				if (o141 == null) return '0';
				o141.fieldWidth = fnum(b, 0);
				return '1';

			case 142:
				var o142:flixel.text.FlxText = textObj(a);
				if (o142 == null) return '0';
				o142.font = Paths.font(b);
				return '1';

			case 143:
				var o143:flixel.text.FlxText = textObj(a);
				if (o143 == null) return '0';
				o143.color = CoolUtil.colorFromString(b);
				return '1';

			case 144:
				var o144:flixel.text.FlxText = textObj(a);
				if (o144 == null) return '0';
				var st144:String = (d.length > 0) ? d.toLowerCase() : 'outline';
				o144.borderStyle = switch (st144)
				{
					case 'shadow': flixel.text.FlxText.FlxTextBorderStyle.SHADOW;
					case 'outline_fast' | 'fast': flixel.text.FlxText.FlxTextBorderStyle.OUTLINE_FAST;
					case 'none': flixel.text.FlxText.FlxTextBorderStyle.NONE;
					default: flixel.text.FlxText.FlxTextBorderStyle.OUTLINE;
				}
				if (st144 != 'none') o144.borderSize = fnum(b, 2);
				o144.borderColor = CoolUtil.colorFromString(c);
				return '1';

			case 145:
				var o145:flixel.text.FlxText = textObj(a);
				if (o145 == null) return '0';
				o145.alignment = switch (b.toLowerCase())
				{
					case 'right': flixel.text.FlxText.FlxTextAlign.RIGHT;
					case 'center': flixel.text.FlxText.FlxTextAlign.CENTER;
					case 'justify': flixel.text.FlxText.FlxTextAlign.JUSTIFY;
					default: flixel.text.FlxText.FlxTextAlign.LEFT;
				}
				return '1';

			case 146:
				var o146:flixel.text.FlxText = textObj(a);
				if (o146 == null) return '0';
				o146.autoSize = truthy(b);
				return '1';

			case 147:
				var o147:flixel.text.FlxText = textObj(a);
				if (o147 == null) return '0';
				o147.italic = truthy(b);
				return '1';

			case 148:
				var o148:flixel.text.FlxText = textObj(a);
				if (o148 == null) return '0';
				o148.fieldHeight = fnum(b, 0);
				return '1';

			case 149:
				var o149:flixel.text.FlxText = textObj(a);
				return (o149 != null) ? Std.string(o149.text) : '';

			case 150:
				var o150:flixel.text.FlxText = textObj(a);
				return (o150 != null) ? Std.string(o150.width) : '0';

			case 151:
				var o151:flixel.text.FlxText = textObj(a);
				return (o151 != null) ? Std.string(o151.size) : '-1';

			case 152:
				var o152:flixel.text.FlxText = textObj(a);
				return (o152 != null) ? Std.string(o152.font) : '';

			case 153: // removeLuaText
				var o153:flixel.text.FlxText = textObj(a);
				if (o153 == null) return '0';
				if (PlayState.instance != null) PlayState.instance.remove(o153, true);
				if (truthy(b) && o153.destroy != null) o153.destroy();
				vars().remove(a.replace('.', ''));
				return '1';

			// ---- 154..156 键盘别名（Lua 里 keyboard* 跟 key* 是同一套）
			case 154, 155, 156:
				var ks2:Dynamic = switch (idx)
				{
					case 154: FlxG.keys.justPressed;
					case 155: FlxG.keys.pressed;
					default: FlxG.keys.justReleased;
				}
				return (Reflect.getProperty(ks2, a.toUpperCase()) == true) ? '1' : '0';

			// ---- 157..161 手柄
			case 157, 158:
				var pad:Dynamic = FlxG.gamepads.getByID(inum(a, 0));
				if (pad == null) return '0';
				var stick:Dynamic = truthy(b) ? pad.getXAxis(flixel.input.gamepad.FlxGamepadInputID.LEFT_ANALOG_STICK)
					: pad.getXAxis(flixel.input.gamepad.FlxGamepadInputID.RIGHT_ANALOG_STICK);
				if (idx == 158)
					stick = truthy(b) ? pad.getYAxis(flixel.input.gamepad.FlxGamepadInputID.LEFT_ANALOG_STICK)
						: pad.getYAxis(flixel.input.gamepad.FlxGamepadInputID.RIGHT_ANALOG_STICK);
				return Std.string(stick);

			case 159, 160, 161:
				var pad2:Dynamic = FlxG.gamepads.getByID(inum(a, 0));
				if (pad2 == null) return '0';
				var btnState:Dynamic = switch (idx)
				{
					case 159: pad2.justPressed;
					case 160: pad2.pressed;
					default: pad2.justReleased;
				}
				return (Reflect.getProperty(btnState, b) == true) ? '1' : '0';

			// ---- 162..166 存档（键名跟 Lua 一致：save_<name>）
			case 162:
				var skey:String = 'save_' + a;
				if (!vars().exists(skey))
				{
					var sv:FlxSave = new FlxSave();
					sv.bind(a, CoolUtil.getSavePath() + '/psychenginemods');
					vars().set(skey, sv);
				}
				return '1';

			case 163:
				var sv163:Dynamic = vars().get('save_' + a);
				if (sv163 == null || sv163.data == null) return '';
				return Reflect.hasField(sv163.data, b) ? Std.string(Reflect.field(sv163.data, b)) : '';

			case 164:
				var sv164:Dynamic = vars().get('save_' + a);
				if (sv164 == null || sv164.data == null) return '0';
				Reflect.setField(sv164.data, b, coerce(c));
				return '1';

			case 165:
				var sv165:Dynamic = vars().get('save_' + a);
				if (sv165 == null) return '0';
				sv165.flush();
				return '1';

			case 166:
				var sv166:Dynamic = vars().get('save_' + a);
				if (sv166 == null) return '0';
				sv166.erase();
				vars().remove('save_' + a);
				return '1';

			// ---- 167..168 图集
			case 167: // loadGraphic(tag, image, gridX, gridY)
				var o167:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o167 == null || !Std.isOfType(o167, flixel.FlxSprite)) return '0';
				var sp167:flixel.FlxSprite = cast o167;
				var gx167:Int = inum(c, 0);
				var gy167:Int = inum(d, 0);
				var img167 = Paths.image(b);
				if (gx167 > 0 && gy167 > 1) sp167.loadGraphic(img167, true, gx167, gy167);
				else sp167.loadGraphic(img167);
				return '1';

			case 168: // addAnimationByIndicesLoop
				var o168:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o168 == null) return '0';
				var idxs168:Array<Int> = [];
				for (part in d.split(','))
				{
					var n168:Null<Int> = Std.parseInt(part.trim());
					if (n168 != null) idxs168.push(n168);
				}
				if (idxs168.length == 0) return '0';
				var fps168:Int = inum(e, 24);
				if (fps168 <= 0) fps168 = 24;
				o168.animation.addByIndices(b, c, idxs168, '', fps168, true);
				return '1';

			case 169: // addLuaText
				var o169:Dynamic = vars().get(a);
				if (o169 == null) return '0';
				var inst169:Dynamic = (psychlua.CustomSubstate.instance != null)
					? psychlua.CustomSubstate.instance : LuaUtils.getTargetInstance();
				if (inst169 == null) return '0';
				inst169.add(o169);
				return '1';


			// ---- 170..176 图集 / FlxAnimate
			case 170: // loadFrames(tag, image, spriteType)
				var o170:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o170 == null || !Std.isOfType(o170, flixel.FlxSprite)) return '0';
				LuaUtils.loadFrames(cast o170, b, (c.length > 0) ? c : 'auto');
				return '1';

			case 171: // loadMultipleFrames(tag, "a,b,c")
				var o171:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o171 == null || !Std.isOfType(o171, flixel.FlxSprite)) return '0';
				var sp171:flixel.FlxSprite = cast o171;
				sp171.frames = Paths.getMultiAtlas(b.split(','));
				return '1';

			case 172: // makeFlxAnimateSprite(tag, x, y, folder)
				var t172:String = a.replace('.', '');
				var old172:Dynamic = vars().get(t172);
				if (old172 != null)
				{
					old172.kill();
					if (PlayState.instance != null) PlayState.instance.remove(old172);
					try { old172.destroy(); } catch (e:Dynamic) {}
				}
				var anim172:psychlua.ModchartAnimateSprite = new psychlua.ModchartAnimateSprite(fnum(b, 0), fnum(c, 0));
				if (d != null && d.length > 0) Paths.loadAnimateAtlas(anim172, d);
				vars().set(t172, anim172);
				anim172.active = true;
				return '1';

			case 173: // loadAnimateAtlas(tag, folderOrImg, spriteJson, animJson)
				var o173:Dynamic = vars().get(a);
				if (o173 == null) return '0';
				Paths.loadAnimateAtlas(cast o173, b,
					(c.length > 0) ? c : null, (d.length > 0) ? d : null);
				return '1';

			case 174: // addAnimationBySymbol(tag, name, symbol, fps, loop, matX)
				var o174:Dynamic = vars().get(a);
				if (o174 == null) return '0';
				var fps174:Float = fnum(d, 24);
				o174.anim.addBySymbol(b, c, fps174, truthy(e), fnum(f, 0), 0);
				if (o174.anim.curSymbol == null) o174.anim.play(b, true);
				return '1';

			case 175: // addAnimationBySymbolIndices(tag, name, symbol, indices, fps, loop)
				var o175:Dynamic = vars().get(a);
				if (o175 == null) return '0';
				var idxs175:Array<Int> = csvInts(d);
				if (idxs175.length == 0) idxs175 = [0];
				o175.anim.addBySymbolIndices(b, c, idxs175, fnum(e, 24), truthy(f));
				return '1';

			case 176: // addAnimation(tag, name, "0,1,2", fps, loop)
				return Std.string(LuaUtils.addAnimByIndices(a, b, null, csvInts(c), fnum(d, 24), truthy(e)));

			// ---- 177..184 luaSprite* 旧别名（DeprecatedFunctions.hx 那套）
			case 177: // luaSpriteMakeGraphic
				var o177:Dynamic = vars().get(a);
				if (o177 == null) return '0';
				o177.makeGraphic(inum(b, 1), inum(c, 1), CoolUtil.colorFromString(d), true);
				return '1';

			case 178:
				var o178:Dynamic = vars().get(a);
				if (o178 == null) return '0';
				var fps178:Int = inum(d, 24);
				o178.animation.addByPrefix(b, c, fps178, true);
				if (o178.animation.curAnim == null) o178.animation.play(b, true);
				return '1';

			case 179:
				var o179:Dynamic = vars().get(a);
				if (o179 == null) return '0';
				var idxs179:Array<Int> = csvInts(d);
				if (idxs179.length == 0) return '0';
				o179.animation.addByIndices(b, c, idxs179, '', inum(e, 24), true);
				return '1';

			case 180:
				var o180:Dynamic = vars().get(a);
				if (o180 == null) return '0';
				o180.animation.play(b, truthy(c));
				return '1';

			case 181:
				var o181:Dynamic = vars().get(a);
				if (o181 == null) return '0';
				o181.cameras = [LuaUtils.cameraFromString(b)];
				return '1';

			case 182:
				var o182:Dynamic = vars().get(a);
				if (o182 == null) return '0';
				var sx182:Float = fnum(b, 1);
				o182.scrollFactor.set(sx182, (c.length > 0) ? fnum(c, sx182) : sx182);
				return '1';

			case 183: // getPropertyLuaSprite(tag, variable)
				var o183:Dynamic = vars().get(a);
				if (o183 == null) return '';
				return Std.string(LuaUtils.getVarInArray(o183, b));

			case 184: // setPropertyLuaSprite(tag, variable, value)
				var o184:Dynamic = vars().get(a);
				if (o184 == null) return '0';
				LuaUtils.setVarInArray(o184, b, coerce(c));
				return '1';

			// ---- 185..200 脚本管理（JS 单 context，语义按注释里那样简化）
			case 185, 187: // addLuaScript / addHScript
				var p185:String = resolveScript(a);
				if (p185 == null) return '0';
				return JSPlayer.loadFile(p185) ? '1' : '0';

			case 186, 188: // removeLuaScript / removeHScript
				// 单 context 卸不掉单个文件，只能整首换掉。照实说，不假装成功。
				log('[warn] removeLuaScript/removeHScript: JS 共用一个 context，无法单独卸载 $a');
				return '0';

			case 189: // isRunning
				var p189:String = resolveScript(a);
				return JSPlayer.isLoaded(p189 != null ? p189 : a) ? '1' : '0';

			case 190: // getRunningScripts
				return JSPlayer.getLoadedFiles().join(String.fromCharCode(1));

			case 191: // callScript(script, func, arg)
				return QuickJSHandler.callGlobalStr(b, c) ? '1' : '0';

			case 192: // callMethod(func, arg)
				return QuickJSHandler.callGlobalStr(a, b) ? '1' : '0';

			case 193: // callMethodFromClass(class, method)
				var cls193:Dynamic = ScriptClassAliases.resolve(a);
				if (cls193 == null) return '';
				var fn193:Dynamic = Reflect.field(cls193, b);
				if (fn193 == null || !Reflect.isFunction(fn193)) return '';
				return Std.string(Reflect.callMethod(cls193, fn193, []));

			case 194: // createInstance(class)
				var cls194:Dynamic = ScriptClassAliases.resolve(a);
				if (cls194 == null) return '';
				var inst194:Dynamic = Type.createInstance(cls194, []);
				if (inst194 == null) return '';
				vars().set('instance_' + a.split('.').pop(), inst194);
				return 'instance_' + a.split('.').pop();

			case 195: // getVar
				var v195:Dynamic = vars().get(a);
				return (v195 != null) ? Std.string(v195) : '';

			case 196: // setVar
				vars().set(a, coerce(b));
				return b;

			case 197: // getGlobalFromScript（单 context，就是读全局）
				return QuickJSHandler.globalString(b);

			case 198: // setGlobalFromScript
				QuickJSHandler.setGlobal(b, coerce(c));
				return c;

			case 199: // addInstance(class, tag)
				var cls199:Dynamic = ScriptClassAliases.resolve(a);
				if (cls199 == null) return '';
				var inst199:Dynamic = Type.createInstance(cls199, []);
				if (inst199 == null) return '';
				vars().set((b.length > 0) ? b : a.split('.').pop(), inst199);
				return (b.length > 0) ? b : a.split('.').pop();

			case 200: // instanceArg
				// Lua 用它把实例当参数传给 callMethod；JS 侧参数只能是字符串，
				// 只能把 tag 传过去，脚本里自己 getVar 取回来
				return a;

			// ---- 201..214 Shader
			case 201, 203, 205: // getShaderFloat / Int / Bool
				var sh201:flixel.addons.display.FlxRuntimeShader = psychlua.ShaderFunctions.getShader(a);
				if (sh201 == null) return '';
				if (idx == 201) return Std.string(sh201.getFloat(b));
				if (idx == 203) return Std.string(sh201.getInt(b));
				return sh201.getBool(b) ? '1' : '0';

			case 202, 204, 206: // setShaderFloat / Int / Bool
				var sh202:flixel.addons.display.FlxRuntimeShader = psychlua.ShaderFunctions.getShader(a);
				if (sh202 == null) return '0';
				if (idx == 202) sh202.setFloat(b, fnum(c, 0));
				else if (idx == 204) sh202.setInt(b, inum(c, 0));
				else sh202.setBool(b, truthy(c));
				return '1';

			case 207, 209, 211: // getShader*Array
				var sh207:flixel.addons.display.FlxRuntimeShader = psychlua.ShaderFunctions.getShader(a);
				if (sh207 == null) return '';
				var arr207:Array<Dynamic> = (idx == 207) ? cast sh207.getFloatArray(b)
					: (idx == 209) ? cast sh207.getIntArray(b) : cast sh207.getBoolArray(b);
				if (arr207 == null) return '';
				var parts207:Array<String> = [];
				for (v207 in arr207) parts207.push((idx == 211) ? (((v207 == true) ? '1' : '0')) : Std.string(v207));
				return parts207.join(String.fromCharCode(1));

			case 208, 210, 212: // setShader*Array（逗号分隔）
				var sh208:flixel.addons.display.FlxRuntimeShader = psychlua.ShaderFunctions.getShader(a);
				if (sh208 == null) return '0';
				if (idx == 208) sh208.setFloatArray(b, csvFloats(c));
				else if (idx == 210) sh208.setIntArray(b, csvInts(c));
				else sh208.setBoolArray(b, csvBools(c));
				return '1';

			case 213: // setShaderSampler2D
				var sh213:flixel.addons.display.FlxRuntimeShader = psychlua.ShaderFunctions.getShader(a);
				if (sh213 == null) return '0';
				var bmp213 = Paths.image(b);
				if (bmp213 == null || bmp213.bitmap == null) return '0';
				sh213.setSampler2D(c, bmp213.bitmap);
				return '1';

			case 214: // removeSpriteShader
				var o214:Dynamic = LuaUtils.getObjectDirectly(a);
				if (o214 == null) return '0';
				o214.shader = null;
				return '1';

			// ---- 215..217 anyGamepad*（按名字查，跟 gamepad* 一样走反射；
			// FlxGamepadManager.anyJustPressed 要的是枚举 id，不是字符串）
			case 215, 216, 217:
				for (i215 in 0...4)
				{
					var pad215:Dynamic = FlxG.gamepads.getByID(i215);
					if (pad215 == null) continue;
					var st215:Dynamic = switch (idx)
					{
						case 215: pad215.justPressed;
						case 216: pad215.pressed;
						default: pad215.justReleased;
					}
					if (Reflect.getProperty(st215, a) == true) return '1';
				}
				return '0';

			default:
				var m2:String = '[warn] 未实现的宿主函数编号 $idx (a=$a)';
				Log.trace('[js] ' + m2, null);
				log(m2);
				return '';
		}
	}

	// ---------------------------------------------------------------- 小工具
	static inline function vars():Map<String, Dynamic>
		return MusicBeatState.getVariables();

	static function tweenKey(tag:String):String
		return 'tween_' + LuaUtils.formatVariable(tag);

	// tween 存在 MusicBeatState 的 variables 里、键名跟 Lua 一致，
	// 这样 JS 的 cancelTween 能取消 Lua 建的 tween，反过来也一样
	static function tweenStore(tag:String, tw:FlxTween):Void
	{
		if (tw == null) return;
		vars().set(tweenKey(tag), tw);
	}

	static function onTweenDone(tag:String, varsStr:String):Void
	{
		vars().remove(tweenKey(tag));
		JSPlayer.onTweenCompleted(tag, varsStr);
	}

	static function charOf(n:String):Dynamic
	{
		if (PlayState.instance == null || n == null) return null;
		return switch (n.toLowerCase())
		{
			case 'boyfriend' | 'bf': PlayState.instance.boyfriend;
			case 'dad' | 'opponent': PlayState.instance.dad;
			case 'gf' | 'girlfriend': PlayState.instance.gf;
			default: null;
		};
	}

	// 返回强类型：用 Dynamic 访问 size / alignment 这类字段时，hxcpp 反射拿不到值
	// （表现为 NaN 或 Invalid field），文本那批函数全得靠它
	static function csvFloats(v:String):Array<Float>
	{
		var out:Array<Float> = [];
		if (v == null) return out;
		for (part in v.split(','))
		{
			var f:Null<Float> = Std.parseFloat(part.trim());
			if (f != null) out.push(f);
		}
		return out;
	}

	static function csvInts(v:String):Array<Int>
	{
		var out:Array<Int> = [];
		if (v == null) return out;
		for (part in v.split(','))
		{
			var i:Null<Int> = Std.parseInt(part.trim());
			if (i != null) out.push(i);
		}
		return out;
	}

	static function csvBools(v:String):Array<Bool>
	{
		var out:Array<Bool> = [];
		if (v == null) return out;
		for (part in v.split(',')) out.push(truthy(part));
		return out;
	}

	/** 脚本名 → 实际路径（和 Lua 的 findScript 一个思路，先补扩展名再交给 Paths 找） */
	static function resolveScript(path:String):String
	{
		if (path == null || path.length == 0) return null;
		var direct:String = Paths.findScriptFile(path);
		if (direct != null) return direct;
		if (!path.toLowerCase().endsWith('.js'))
		{
			var withExt:String = Paths.findScriptFile(path + '.js');
			if (withExt != null) return withExt;
		}
		return null;
	}

	static function textObj(tag:String):flixel.text.FlxText
	{
		if (tag == null) return null;
		var split:Array<String> = tag.split('.');
		var o:Dynamic = (split.length > 1)
			? LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1])
			: LuaUtils.getObjectDirectly(tag);
		return (o != null && Std.isOfType(o, flixel.text.FlxText)) ? cast o : null;
	}

	static function soundOf(tag:String):Dynamic
	{
		if (tag == null || tag.length == 0) return FlxG.sound.music;
		return vars().get(LuaUtils.formatVariable('sound_' + tag));
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
