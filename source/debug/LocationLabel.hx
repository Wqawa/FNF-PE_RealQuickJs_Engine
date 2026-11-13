package debug;

import flixel.FlxG;
import openfl.text.TextField;
import openfl.text.TextFormat;

/**
 * FPS 下面那行小字：现在在哪。
 *
 * 显示 `<引擎>/<状态类名>`，在 PlayState 里再带上歌名。纯调试用，不 import PlayState
 * （读歌名走 Reflect），免得和状态类互相依赖。
 */
class LocationLabel extends TextField
{
	var acc:Float = 0;

	public function new(x:Float = 10, y:Float = 28, color:Int = 0xFFFFFFFF)
	{
		super();

		this.x = x;
		this.y = y;

		selectable = false;
		mouseEnabled = false;
		defaultTextFormat = new TextFormat("_sans", 12, color);
		autoSize = LEFT;
		text = '...';
	}

	override function __enterFrame(deltaTime:Float):Void
	{
		// 250ms 刷一次就够，别每帧拼字符串
		acc += deltaTime;
		if (acc < 250) return;
		acc = 0.0;

		text = describe();
	}

	static function describe():String
	{
		var state:Dynamic = FlxG.state;
		if (state == null) return '${Engine.current()}/(no state)';

		var cls:Null<String> = Type.getClassName(Type.getClass(state));
		if (cls != null) cls = cls.split('.').pop();

		var out:String = '${Engine.current()}/$cls';

		// PlayState 里顺手带歌名：SONG.song（读不到就当没有）
		var song:Dynamic = Reflect.getProperty(state, 'SONG');
		if (song != null)
		{
			var name:Dynamic = Reflect.getProperty(song, 'song');
			if (name != null)
			{
				var s:String = Std.string(name);
				if (s.length > 0) out += ' · $s';
			}
		}
		return out;
	}
}
