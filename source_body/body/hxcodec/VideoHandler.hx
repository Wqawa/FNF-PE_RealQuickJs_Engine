package hxcodec;

#if VIDEOS_ALLOWED
import hxcodec.flixel.FlxVideo;

// Old hxcodec 2.6 class name, renamed to FlxVideo in 3.0. Keeps old imports alive.
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
