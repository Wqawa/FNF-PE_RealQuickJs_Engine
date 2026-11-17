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
 * Crash handler shared by all three trees.
 *
 * This used to live in the body Main and only covered that branch: switching to 1.0.4
 * or 0.6.3 meant the window just vanished (or openfl swallowed it, with no dump). It now
 * runs before Main.main() forks, so all trees share one path: write a dump, show the screen.
 *
 * It does not Sys.exit immediately: openfl's uncaught error only dispatches and keeps
 * running, so the process is alive and can switch states. Only when even that fails does
 *
 * it fall back to exiting. Ctrl+Alt+Shift+Q triggers it manually without throwing: throwing
 * from preUpdate can corrupt the current frame's flixel state.
 */
class EngineCrash
{
	public static var installed:Bool = false;

	/** Full text of the last crash. The copy button and the dump use the same string. */
	public static var lastText:String = '';

	/** Path of the last dump, null when writing failed. */
	public static var lastDump:String = null;

	static var pending:Bool = false;
	static var entered:Bool = false;
	static var hotkeyLatched:Bool = false;

	/** Called once from Main.main() before the fork; one entry point covers all trees. */
	public static function install():Void
	{
		if (installed) return;
		installed = true;

		#if CRASH_HANDLER
		try
		{
			Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaught);
		}
		catch (e:Dynamic) trace('[crash] could not attach the uncaught error listener: ' + e);
		#end

		try
		{
			flixel.FlxG.signals.preUpdate.add(tick);
		}
		catch (e:Dynamic) trace('[crash] could not attach preUpdate: ' + e);
	}

	#if CRASH_HANDLER
	static function onUncaught(e:UncaughtErrorEvent):Void
	{
		report(describe((e != null) ? e.error : null), false);
	}
	#end

	/**
	 * Formats an exception for humans: stack first, message last.
	 * If the stack is gone (hxcpp ate it), keep the message and do not blow up again.
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
	 * Records a crash and queues the screen switch.
	 * It does not switchState inside the exception handler: that frame's flixel state is half
	 * built. Waiting for the next preUpdate is far safer.
	 */
	public static function report(reason:String, ?manual:Bool):Void
	{
		var head:String = '[engine] ' + Engine.current() + '   ' + Date.now().toString() + '\n';
		var body:String = (reason == null) ? '' : reason;

		lastText = head + body;
		lastDump = saveDump(lastText);
		if (lastDump != null && lastDump.length > 0) lastText += '\n\nCrash dump: ' + lastDump;

		pending = true;
		trace('[crash] ' + ((manual == true) ? 'manual trigger' : 'uncaught error') + ' -> switching to the crash screen');
	}

	static function tick():Void
	{
		#if desktop
		// The hotkey only fires when not already on the crash screen, or it would refresh it
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
			trace('[crash] switched to the crash screen');
		}
		catch (e:Dynamic)
		{
			// Even the state switch failed; exit - the dump is already on disk
			trace('[crash] crash screen failed (' + Std.string(e) + '), exiting');
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
		catch (e:Dynamic) trace('[crash] failed to write the dump: ' + e);
		#end
		return null;
	}

	/** Copies to the clipboard. Returns false on failure and the crash screen says so. */
	public static function copy(text:String):Bool
	{
		#if desktop
		try
		{
			Clipboard.text = (text == null) ? '' : text;
			return true;
		}
		catch (e:Dynamic) trace('[crash] copy failed: ' + e);
		#end
		return false;
	}

	/** Main menu class for the current engine (from engine.txt), null when unavailable. */
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
