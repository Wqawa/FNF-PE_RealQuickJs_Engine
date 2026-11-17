package hxcodec;

#if VIDEOS_ALLOWED
import hxcodec.flixel.FlxVideo;

/**
 * hxcodec 2.6 的类名。0.6/0.7 的 mod 里 `import hxcodec.VideoHandler;` 很常见，
 * 3.0 之后改叫 `hxcodec.flixel.FlxVideo`，这里给老名字留个壳。
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
