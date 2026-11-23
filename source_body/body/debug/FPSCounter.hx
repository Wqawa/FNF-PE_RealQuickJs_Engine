package debug;

import backend.ClientPrefs;
import backend.Paths;
import flixel.FlxG;
import flixel.input.keyboard.FlxKey;
import flixel.util.FlxStringUtil;
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

	/** 堆总量，跟 memoryMegas 一起看才知道 GC 离下一次回收还有多远 */
	public var totalMegas(get, never):Float;

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

	// F3 toggles this (bound in Controls, key name 'fps_debug'). Compact is the old two-liner.
	public var detailed:Bool = false;

	// Event Handlers
	private override function __enterFrame(deltaTime:Float):Void
	{
		var toggle:Array<FlxKey> = (ClientPrefs.keyBinds != null) ? ClientPrefs.keyBinds.get('fps_debug') : null;
		if (toggle == null) toggle = [F3];
		if (FlxG.keys.anyJustPressed(toggle)) detailed = !detailed;

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
		if (detailed)
		{
			var texCount:Int = 0;
			var gpuCount:Int = 0;
			var texBytes:Float = 0;
			for (key => g in Paths.currentTrackedAssets)
			{
				if (g == null || g.bitmap == null) continue;
				texCount++;
				texBytes += g.bitmap.width * g.bitmap.height * 4;
				// cacheOnGPU 把 CPU 侧像素扔了，image 会是 null，纹理还在显存里
				if (g.bitmap.image == null) gpuCount++;
			}

			text = 'FPS: ${currentFPS}'
			+ '\nHeap: ${FlxStringUtil.formatBytes(memoryMegas)} / ${FlxStringUtil.formatBytes(totalMegas)}'
			+ '\nTextures: $texCount ($gpuCount on GPU) ~${FlxStringUtil.formatBytes(texBytes)}'
			+ '\nAudio: ${Lambda.count(Paths.currentTrackedSounds)}'
			+ '\n${whereAmI()}';
		}
		else
		{
			text = 'FPS: ${currentFPS}'
			+ '\nMemory: ${flixel.util.FlxStringUtil.formatBytes(memoryMegas)}'
			+ '\n${whereAmI()}';
		}

		textColor = 0xFFFFFFFF;
		if (currentFPS < FlxG.drawFramerate * 0.5)
			textColor = 0xFFFF0000;
	}

	// Where you are + song name, in the same TextField as FPS. Reflect keeps this tree-free.
	static function whereAmI():String
	{
		var state:Dynamic = FlxG.state;
		if (state == null) return 'body/(no state)';

		var cls:Null<String> = Type.getClassName(Type.getClass(state));
		if (cls != null) cls = cls.split('.').pop();

		var out:String = 'body/' + cls;

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

	inline function get_totalMegas():Float
		return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_RESERVED);
}
