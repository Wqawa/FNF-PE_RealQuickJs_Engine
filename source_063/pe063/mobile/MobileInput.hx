package pe063.mobile;

import pe063.mobile.input.MobileInputID;
import pe063.mobile.input.MobileInputManager;
import haxe.ds.Map;

// Bridges 0.6.3 input actions to whatever pad is on screen. Note IDs also answer
// for their hitbox lane, so a tap on the lane counts as NOTE_LEFT too.
class MobileInput
{
	static var cache:Map<Int, Array<MobileInputID>> = new Map<Int, Array<MobileInputID>>();

	public static inline function pressed(id:MobileInputID):Bool
	{
		var pad:MobileInputManager = MobileInputManager.current;
		return pad != null && pad.anyPressed(ids(id));
	}

	public static inline function justPressed(id:MobileInputID):Bool
	{
		var pad:MobileInputManager = MobileInputManager.current;
		return pad != null && pad.anyJustPressed(ids(id));
	}

	public static inline function justReleased(id:MobileInputID):Bool
	{
		var pad:MobileInputManager = MobileInputManager.current;
		return pad != null && pad.anyJustReleased(ids(id));
	}

	@:noCompletion
	static function ids(id:MobileInputID):Array<MobileInputID>
	{
		var i:Int = id;
		var arr:Array<MobileInputID> = cache.get(i);
		if (arr == null)
		{
			arr = [id];
			// NOTE_LEFT..NOTE_RIGHT and HITBOX_LEFT..HITBOX_RIGHT are 34 apart
			if (i >= 0 && i <= 3)
				arr.push(cast (i + 34));
			cache.set(i, arr);
		}
		return arr;
	}
}
