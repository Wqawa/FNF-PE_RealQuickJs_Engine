package vanilla.mobile;

import flixel.FlxObject;
import flixel.input.touch.FlxTouch;

// 'Did the player tap anywhere' helpers (MIT port). Mouse stands in on desktop.
class TouchUtil
{
	public static var pressed(get, never):Bool;
	public static var justPressed(get, never):Bool;
	public static var justReleased(get, never):Bool;
	public static var released(get, never):Bool;

	// The finger currently down, or the first one the driver knows about.
	public static var touch(get, never):FlxTouch;

	// Where that finger is, in game coordinates. Mouse on desktop.
	public static var pointerX(get, never):Float;
	public static var pointerY(get, never):Float;

	// Is any finger inside this object. Used by the layout editor's buttons.
	public static function overlaps(object:FlxObject, ?camera:FlxCamera):Bool
	{
		#if desktop
		return FlxG.mouse.overlaps(object, camera ?? object.camera);
		#else
		for (touch in FlxG.touches.list)
			if (touch != null && touch.overlaps(object, camera ?? object.camera))
				return true;
		return false;
		#end
	}

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

	@:noCompletion
	private static function get_touch():FlxTouch
	{
		for (touch in FlxG.touches.list)
			if (touch != null && touch.pressed)
				return touch;
		return FlxG.touches.getFirst();
	}

	@:noCompletion
	private static function get_pointerX():Float
	{
		#if desktop
		return FlxG.mouse.x;
		#else
		var finger:FlxTouch = touch;
		return finger == null ? 0 : finger.x;
		#end
	}

	@:noCompletion
	private static function get_pointerY():Float
	{
		#if desktop
		return FlxG.mouse.y;
		#else
		var finger:FlxTouch = touch;
		return finger == null ? 0 : finger.y;
		#end
	}
}
