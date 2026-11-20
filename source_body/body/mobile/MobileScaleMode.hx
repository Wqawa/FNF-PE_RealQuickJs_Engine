package mobile;

import flixel.system.scaleModes.BaseScaleMode;

// Flixel's default letterboxes; 'Wide Screen' stretches over the whole display.
class MobileScaleMode extends BaseScaleMode
{
	public static var allowWideScreen(default, set):Bool = true;

	override function updateGameSize(Width:Int, Height:Int):Void
	{
		if (ClientPrefs.data.wideScreen && allowWideScreen)
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
		if (ClientPrefs.data.wideScreen && allowWideScreen)
			FlxG.game.x = FlxG.game.y = 0;
		else
			super.updateGamePosition();
	}

	// Re-applies the mode, for when the option changes at runtime.
	@:noCompletion
	static function set_allowWideScreen(value:Bool):Bool
	{
		allowWideScreen = value;
		FlxG.scaleMode = new MobileScaleMode();
		return value;
	}
}
