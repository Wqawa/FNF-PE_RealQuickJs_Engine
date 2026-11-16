package backend;

import openfl.Lib;

#if CRASH_HANDLER
import haxe.CallStack;
import openfl.events.UncaughtErrorEvent;
#end

#if desktop
import lime.system.Clipboard;
#end

/**
 * 三棵树共用的崩溃拦截。
 *
 * 原来这段在 `source/Main.hx` 里、只挂在 body 那条分支上 —— 切到原版 1.0.4 或 0.6.3
 * 以后崩了就是窗口直接没（或者被 openfl 静默吞掉，连 dump 都没有）。现在挂在
 * `Main.main()` 分叉之前，三棵树走同一条路：写 dump → 切崩溃屏幕。
 *
 * 之所以不直接 `Sys.exit`，是因为 openfl 的未捕获异常默认只是"派发一下然后继续跑"，
 * 进程还活着，能切 state。真到切不动的地步（比如 FlxG 本身坏了）才退化成退出。
 *
 * Ctrl+Alt+Shift+Q 是手动触发：不抛异常，直接走 report —— 抛异常在 preUpdate 里
 * 有可能把当帧的 flixel 状态搞乱，验证崩溃屏幕用不着付这个代价。
 */
class EngineCrash
{
	public static var installed:Bool = false;

	/** 最近一次崩溃的完整文本（复制按钮和 dump 用的是同一份） */
	public static var lastText:String = '';

	/** 最近一次 dump 的路径，没写成就是 null */
	public static var lastDump:String = null;

	static var pending:Bool = false;
	static var entered:Bool = false;
	static var hotkeyLatched:Bool = false;

	/** 在 Main.main() 里、分叉之前调一次。三棵树共用同一个入口，所以只调一次就够。 */
	public static function install():Void
	{
		if (installed) return;
		installed = true;

		#if CRASH_HANDLER
		try
		{
			Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaught);
		}
		catch (e:Dynamic) trace('[crash] 挂不上未捕获异常监听: ' + e);
		#end

		try
		{
			flixel.FlxG.signals.preUpdate.add(tick);
		}
		catch (e:Dynamic) trace('[crash] 挂不上 preUpdate: ' + e);
	}

	#if CRASH_HANDLER
	static function onUncaught(e:UncaughtErrorEvent):Void
	{
		report(describe((e != null) ? e.error : null), false);
	}
	#end

	/**
	 * 把异常整理成人能看的文本：栈在上，错误信息在下。
	 * 取不到栈（比如 hxcpp 已经把栈吃了）就只留错误信息，别为此再炸一次。
	 */
	public static function describe(err:Dynamic):String
	{
		var out:String = '';

		#if CRASH_HANDLER
		try
		{
			var stack:Array<StackItem> = CallStack.exceptionStack(true);
			if (stack != null && stack.length > 0)
			{
				out += 'Call stack:\n';
				for (item in stack)
				{
					switch (item)
					{
						case FilePos(_, file, line, _): out += '  ' + file + ':' + line + '\n';
						default: out += '  ' + Std.string(item) + '\n';
					}
				}
				out += '\n';
			}
		}
		catch (e:Dynamic) {}
		#end

		out += 'Uncaught error: ' + Std.string(err);
		return out;
	}

	/**
	 * 记下崩溃并排队切屏幕。
	 * 不在异常处理栈里直接 switchState —— 那一帧的 flixel 状态是半截的，
	 * 推到下一次 preUpdate 再切，稳得多。
	 */
	public static function report(reason:String, ?manual:Bool):Void
	{
		var head:String = '[engine] ' + Engine.current() + '   ' + Date.now().toString() + '\n';
		var body:String = (reason == null) ? '' : reason;

		lastText = head + body;
		lastDump = saveDump(lastText);
		if (lastDump != null && lastDump.length > 0) lastText += '\n\nCrash dump: ' + lastDump;

		pending = true;
		trace('[crash] ' + ((manual == true) ? '手动触发' : '未捕获异常') + ' → 准备切崩溃屏幕');
	}

	static function tick():Void
	{
		#if desktop
		// 快捷键只在「当前不在崩溃屏」时起作用，否则在崩溃屏上按一下又刷一遍
		if (!hotkeyLatched && flixel.FlxG.keys.pressed.CONTROL && flixel.FlxG.keys.pressed.ALT
			&& flixel.FlxG.keys.pressed.SHIFT && flixel.FlxG.keys.pressed.Q)
		{
			hotkeyLatched = true;
			if (!Std.isOfType(flixel.FlxG.state, CrashState))
				report('Manually triggered with Ctrl+Alt+Shift+Q (crash screen self-test).', true);
		}
		else if (!flixel.FlxG.keys.pressed.Q)
		{
			hotkeyLatched = false;
		}
		#end

		if (!pending || entered) return;
		entered = true;
		pending = false;
		enterScreen();
	}

	static function enterScreen():Void
	{
		try
		{
			flixel.FlxG.switchState(cast Type.createInstance(CrashState, [lastText]));
			trace('[crash] 已切到崩溃屏幕');
		}
		catch (e:Dynamic)
		{
			// 连 state 都切不动了，只能退出去 —— 至少 dump 已经落盘
			trace('[crash] 切崩溃屏幕失败（' + Std.string(e) + '），直接退出');
			#if sys
			Sys.exit(1);
			#end
		}
	}

	static function saveDump(text:String):String
	{
		#if sys
		try
		{
			if (!sys.FileSystem.exists('./crash')) sys.FileSystem.createDirectory('./crash');
			var stamp:String = Date.now().toString();
			stamp = stamp.split(' ').join('_').split(':').join("'");
			var path:String = './crash/PsychEngine_' + stamp + '.txt';
			sys.io.File.saveContent(path, text + '\n');
			return path;
		}
		catch (e:Dynamic) trace('[crash] 写 dump 失败: ' + e);
		#end
		return null;
	}

	/** 复制到剪贴板。失败返回 false，崩溃屏那边会把提示文字改掉。 */
	public static function copy(text:String):Bool
	{
		#if desktop
		try
		{
			Clipboard.text = (text == null) ? '' : text;
			return true;
		}
		catch (e:Dynamic) trace('[crash] 复制失败: ' + e);
		#end
		return false;
	}

	/** 当前引擎的主菜单类（按 engine.txt 选），取不到返回 null。 */
	public static function mainMenuClass():Dynamic
	{
		var name:String = switch (Engine.current())
		{
			case Engine.VANILLA: 'vanilla.states.MainMenuState';
			case Engine.PE063: 'pe063.MainMenuState';
			default: 'states.MainMenuState';
		};

		try return Type.resolveClass(name) catch (e:Dynamic) return null;
	}
}
