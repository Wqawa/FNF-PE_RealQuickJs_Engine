package pe063.mobile;

import flixel.FlxG;
import flixel.system.scaleModes.BaseScaleMode;
import pe063.ClientPrefs;

/**
 * Flixel's default scale mode keeps the 1280x720 canvas intact and letterboxes
 * it, which leaves black bars on tall phones. 'Wide Screen' stretches the
 * canvas over the whole display instead.
 *
 * Installed once at startup and left alone: with wideScreen off it does exactly
 * what the default mode does, so the option only flips a flag.
 */
class MobileScaleMode extends BaseScaleMode
{
	public static var allowWideScreen(default, set):Bool = true;

	override function updateGameSize(Width:Int, Height:Int):Void
	{
		if (ClientPrefs.wideScreen && allowWideScreen)
		{
			super.updateGameSize(Width, Height);
			return;
		}

		var ratio:Float = FlxG.width / FlxG.height;
		var realRatio:Float = Width / Height;

		if (realRatio < ratio)
		{
			gameSize.x = Width;
			gameSize.y = Math.floor(gameSize.x / ratio);
		}
		else
		{
			gameSize.y = Height;
			gameSize.x = Math.floor(gameSize.y * ratio);
		}
	}

	override function updateGamePosition():Void
	{
		if (ClientPrefs.wideScreen && allowWideScreen)
			FlxG.game.x = FlxG.game.y = 0;
		else
			super.updateGamePosition();
	}

	/** Re-applies the mode, for when the option changes at runtime. */
	@:noCompletion
	static function set_allowWideScreen(value:Bool):Bool
	{
		allowWideScreen = value;
		FlxG.scaleMode = new MobileScaleMode();
		return value;
	}
}
