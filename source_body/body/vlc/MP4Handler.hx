package vlc;

#if VIDEOS_ALLOWED
import hxcodec.flixel.FlxVideo;

// 0.6.x vlc.MP4Handler, now backed by hxvlc. Keeps old imports alive.
@:keep
class MP4Handler extends FlxVideo
{
	public function new()
	{
		super();
	}
}
#else
class MP4Handler extends flixel.FlxSprite
{
	public var finishCallback:Void->Void = null;
	public function new() super();
	public function playVideo(path:String):Void {}
	public function stopVideo():Void {}
	public function dispose():Void {}
}
#end
