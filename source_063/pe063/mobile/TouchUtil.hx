package pe063.mobile;

import flixel.FlxG;

/**
 * "Did the player tap anywhere" helpers.
 *
 * Port of the Mobile Porting Team's TouchUtil (MIT). On desktop it reports the
 * left mouse button instead of a finger so menus stay testable in a window.
 */
class TouchUtil
{
	public static var pressed(get, never):Bool;
	public static var justPressed(get, never):Bool;
	public static var justReleased(get, never):Bool;
	public static var released(get, never):Bool;

	@:noCompletion
	private static function get_pressed():Bool
	{
		#if desktop
		return FlxG.mouse.pressed;
		#else
		for (touch in FlxG.touches.list)
			if (touch.pressed)
				return true;
		return false;
		#end
	}

	@:noCompletion
	private static function get_justPressed():Bool
	{
		#if desktop
		return FlxG.mouse.justPressed;
		#else
		for (touch in FlxG.touches.list)
			if (touch.justPressed)
				return true;
		return false;
		#end
	}

	@:noCompletion
	private static function get_justReleased():Bool
	{
		#if desktop
		return FlxG.mouse.justReleased;
		#else
		for (touch in FlxG.touches.list)
			if (touch.justReleased)
				return true;
		return false;
		#end
	}

	@:noCompletion
	private static function get_released():Bool
	{
		#if desktop
		return FlxG.mouse.released;
		#else
		for (touch in FlxG.touches.list)
			if (touch.released)
				return true;
		return false;
		#end
	}
}
