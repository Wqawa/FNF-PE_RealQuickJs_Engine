package hxcodec.flixel;

#if VIDEOS_ALLOWED
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxTimer;
import hxvlc.openfl.Video;
import lime.app.Event;
import openfl.display.BitmapData;

/**
 * Compatibility shell for hxcodec 3.x's FlxVideo.
 *
 * 1.0 switched the player to hxvlc, while old mods still write
 * `new FlxVideo()` + `play(path, loop)` + `video.bitmapData`，
 * hxvlc's Video takes the same calls here, so scripts need no changes.
 */
@:keep
class FlxVideo extends FlxSprite
{
	public var bitmap(default, null):Video;
	public var finishCallback:Void->Void = null;

	/** hxcodec's end callback, forwarded to hxvlc's event */
	public var onEndReached(get, never):Event<Void->Void>;
	/** Current video frame; 0.6/0.7 mods often loadGraphic it onto their own sprite */
	public var bitmapData(get, never):BitmapData;

	private var disposed:Bool = false;

	public function new(?x:Float = 0, ?y:Float = 0)
	{
		super(x, y);

		bitmap = new Video();
		bitmap.forceRendering = true;
		// Not attached yet: wait until this object is actually added to a state (see draw)
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

	/** hxcodec 3 entry point; no path means resume */
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

	/** hxcodec 2.6 / VideoHandler entry point */
	public function playVideo(path:String):Void play(path, false);

	public function stop():Void if (bitmap != null) bitmap.stop();

	/** hxcodec 2.6 exit entry: stop and release */
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
			// Only attach the video to the stage once this object is in a state,
			// so a mod that just news one up (for bitmapData) does not cover the screen
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
