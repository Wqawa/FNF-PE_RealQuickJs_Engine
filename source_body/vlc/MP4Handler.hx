package vlc;

#if VIDEOS_ALLOWED
import hxcodec.flixel.FlxVideo;

/**
 * 0.6.x 里视频播放器叫 `vlc.MP4Handler`（hxcodec 2.x）。
 * 现在底层是 hxvlc，这里留个同名壳，`import vlc.MP4Handler;` 还能用。
 */
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
