package pe063.debug;

import flixel.FlxG;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.system.System;

/**
	The FPS class provides an easy-to-use monitor to display
	the current frame rate of an OpenFL project
**/
class FPSCounter extends TextField
{
	/**
		The current frame rate, expressed using frames-per-second
	**/
	public var currentFPS(default, null):Int;

	/**
		The current memory usage (WARNING: this is NOT your total program memory usage, rather it shows the garbage collector memory)
	**/
	public var memoryMegas(get, never):Float;

	@:noCompletion private var times:Array<Float>;

	public function new(x:Float = 10, y:Float = 10, color:Int = 0x000000)
	{
		super();

		this.x = x;
		this.y = y;

		currentFPS = 0;
		selectable = false;
		mouseEnabled = false;
		defaultTextFormat = new TextFormat("_sans", 14, color);
		autoSize = LEFT;
		multiline = true;
		text = "FPS: ";

		times = [];
	}

	var deltaTimeout:Float = 0.0;

	// Event Handlers
	private override function __enterFrame(deltaTime:Float):Void
	{
		final now:Float = haxe.Timer.stamp() * 1000;
		times.push(now);
		while (times[0] < now - 1000) times.shift();
		// prevents the overlay from updating every frame, why would you need to anyways @crowplexus
		if (deltaTimeout < 50) {
			deltaTimeout += deltaTime;
			return;
		}

		currentFPS = times.length < FlxG.updateFramerate ? times.length : FlxG.updateFramerate;		
		updateText();
		deltaTimeout = 0.0;
	}

	public dynamic function updateText():Void { // so people can override it in hscript
		text = 'FPS: ${currentFPS}'
		+ '\nMemory: ${flixel.util.FlxStringUtil.formatBytes(memoryMegas)}'
		+ '\n${whereAmI()}';

		textColor = 0xFFFFFFFF;
		if (currentFPS < FlxG.drawFramerate * 0.5)
			textColor = 0xFFFF0000;
	}

	/**
	 * 现在在哪：<版本>/<状态类名>，进 PlayState 之后再带歌名。
	 *
	 * 直接拼进 FPS 同一个 TextField，字号/颜色/更新节奏天然和 FPS 那两行一致；
	 * 单独做一个 TextField 会跟 Memory 挤在一起，低帧率变红时也不会有反应。
	 * 读歌名走 Reflect，不 import PlayState，避免状态类互相依赖。
	 */
	static function whereAmI():String
	{
		var state:Dynamic = FlxG.state;
		if (state == null) return 'pe063/(no state)';

		var cls:Null<String> = Type.getClassName(Type.getClass(state));
		if (cls != null) cls = cls.split('.').pop();

		var out:String = 'pe063/' + cls;

		var song:Dynamic = Reflect.getProperty(state, 'SONG');
		if (song != null)
		{
			var name:Dynamic = Reflect.getProperty(song, 'song');
			if (name != null)
			{
				var s:String = Std.string(name);
				if (s.length > 0) out += ' · ' + s;
			}
		}
		return out;
	}

	inline function get_memoryMegas():Float
		return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
}
