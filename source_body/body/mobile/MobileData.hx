package mobile;

import backend.CoolUtil;
import flixel.util.FlxSave;
import mobile.objects.TouchButton;
import mobile.objects.TouchPad;

// Saved button positions for 'Custom'. Own save file, tag/x/y triples.
class MobileData
{
	static var save:FlxSave;
	static var bound:Bool = false;

	static function bind():Void
	{
		if (bound)
			return;
		save = new FlxSave();
		save.bind('mobileControls', CoolUtil.getSavePath());
		bound = true;
	}

	// Move the pad's buttons to where they were left last time.
	public static function applyPositions(pad:TouchPad):Void
	{
		if (pad == null)
			return;
		bind();

		var tags:Array<String> = save.data.tags;
		var coords:Array<Float> = save.data.coords;
		if (tags == null || coords == null)
			return;

		for (i in 0...tags.length)
		{
			if (coords.length < (i * 2) + 2)
				break;

			var button:TouchButton = pad.byTag(tags[i]);
			if (button == null)
				continue;

			button.x = coords[i * 2];
			button.y = coords[i * 2 + 1];
		}
	}

	// Remember where the buttons are right now.
	public static function storePositions(pad:TouchPad):Void
	{
		if (pad == null)
			return;
		bind();

		var tags:Array<String> = [];
		var coords:Array<Float> = [];
		for (button in pad.members)
		{
			if (button == null)
				continue;
			tags.push(button.tag);
			coords.push(button.x);
			coords.push(button.y);
		}

		save.data.tags = tags;
		save.data.coords = coords;
		save.flush();
	}

	public static function clearPositions():Void
	{
		bind();
		save.data.tags = null;
		save.data.coords = null;
		save.flush();
	}
}
