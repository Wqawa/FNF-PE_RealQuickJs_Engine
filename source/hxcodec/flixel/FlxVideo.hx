package hxcodec.flixel;

#if VIDEOS_ALLOWED
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxTimer;
import hxvlc.openfl.Video;
import lime.app.Event;
import openfl.display.BitmapData;

/**
 * hxcodec 3.x 的 FlxVideo 兼容壳。
 *
 * 1.0 把播放器换成了 hxvlc，老 mod 在 HScript 里写的还是
 * `new FlxVideo()` + `play(path, loop)` + `video.bitmapData`，
 * 这里用 hxvlc 的 Video 接住同一套调用，脚本不用改。
 */
@:keep
class FlxVideo extends FlxSprite
{
	public var bitmap(default, null):Video;
	public var finishCallback:Void->Void = null;

	/** hxcodec 的结束回调，转发到 hxvlc 的 event */
	public var onEndReached(get, never):Event<Void->Void>;
	/** 当前视频帧，0.6/0.7 的 mod 常拿它 loadGraphic 到自己的 sprite 上 */
	public var bitmapData(get, never):BitmapData;

	private var disposed:Bool = false;

	public function new(?x:Float = 0, ?y:Float = 0)
	{
		super(x, y);

		bitmap = new Video();
		bitmap.forceRendering = true;
		// 先不上屏，等自己真的被 add 进 state 再挂（见 draw）
		bitmap.visible = false;

		bitmap.onEndReached.add(function() {
			if (finishCallback != null) finishCallback();
		});
	}

	inline function get_onEndReached():Event<Void->Void> return bitmap.onEndReached;
	inline function get_bitmapData():BitmapData return bitmap.bitmapData;

	public var volume(get, set):Int;
	inline function get_volume():Int return bitmap.volume;
	inline function set_volume(value:Int):Int return bitmap.volume = value;

	/** hxcodec 3 的入口；不传路径就当成继续播放 */
	public function play(path:String, ?shouldLoop:Bool = false):Void
	{
		if (disposed || bitmap == null) return;

		if (path == null || path.length < 1)
		{
			bitmap.play();
			return;
		}

		if (bitmap.load(path, shouldLoop ? ['input-repeat=65545'] : null))
			new FlxTimer().start(0.001, function(tmr:FlxTimer) if (!disposed) bitmap.play());
	}

	/** hxcodec 2.6 / VideoHandler 的入口 */
	public function playVideo(path:String):Void play(path, false);

	public function stop():Void if (bitmap != null) bitmap.stop();

	/** hxcodec 2.6 的退出入口，停下来并释放 */
	public function stopVideo():Void
	{
		stop();
		dispose();
	}

	public function pause():Void if (bitmap != null) bitmap.pause();
	public function resume():Void if (bitmap != null) bitmap.resume();

	public function dispose():Void
	{
		if (disposed || bitmap == null) return;
		disposed = true;

		if (bitmap.parent != null)
			bitmap.parent.removeChild(bitmap);

		bitmap.stop();
		bitmap.dispose();
	}

	public override function draw():Void
	{
		if (bitmap != null && !disposed)
		{
			// 只有自己进了 state 才把视频挂到舞台上，
			// 免得 mod 光 new 一个（只取 bitmapData）就把画面糊满
			if (bitmap.parent == null) FlxG.game.addChild(bitmap);

			bitmap.x = x;
			bitmap.y = y;
			bitmap.scaleX = scale.x;
			bitmap.scaleY = scale.y;
			bitmap.alpha = alpha;
			bitmap.visible = visible;
		}
		super.draw();
	}

	public override function destroy():Void
	{
		dispose();
		super.destroy();
	}
}
#else
class FlxVideo extends flixel.FlxSprite
{
	public var finishCallback:Void->Void = null;
	public var bitmapData(default, null):openfl.display.BitmapData = null;
	public function new(?x:Float = 0, ?y:Float = 0) super(x, y);
	public function play(path:String, ?shouldLoop:Bool = false):Void {}
	public function playVideo(path:String):Void {}
	public function stop():Void {}
	public function stopVideo():Void {}
	public function pause():Void {}
	public function resume():Void {}
	public function dispose():Void {}
}
#end
