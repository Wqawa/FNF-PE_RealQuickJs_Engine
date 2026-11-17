package hxcodec;

#if VIDEOS_ALLOWED
import hxcodec.flixel.FlxVideo;

/**
 * hxcodec 2.6's class name. 0.6/0.7 mods commonly `import hxcodec.VideoHandler;`,
 * renamed to `hxcodec.flixel.FlxVideo` in 3.0. This keeps the old name working.
 */
@:keep
class VideoHandler extends FlxVideo
{
	public function new()
	{
		super();
	}
}
#else
class VideoHandler extends flixel.FlxSprite
{
	public var finishCallback:Void->Void = null;
	public function new() super();
	public function playVideo(path:String):Void {}
	public function stopVideo():Void {}
	public function dispose():Void {}
}
#end
