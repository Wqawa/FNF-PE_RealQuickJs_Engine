package vanilla.mobile.objects;

import vanilla.mobile.input.MobileInputID;
import vanilla.mobile.input.MobileInputManager;

/**
 * Four full-height lanes, tap anywhere in a lane to hit that note.
 *
 * Based on the Mobile Porting Team's Hitbox (MIT), minus the gradient shapes:
 * openfl gradients on cpp are unreliable, so the lanes are plain tinted
 * rectangles and the only visible part is a thin bar at the bottom.
 */
class Hitbox extends MobileInputManager
{
	public var buttonLeft:TouchButton;
	public var buttonDown:TouchButton;
	public var buttonUp:TouchButton;
	public var buttonRight:TouchButton;

	static inline var BAR_HEIGHT:Int = 10;

	public function new()
	{
		super();

		var laneWidth:Int = Std.int(FlxG.width / 4);
		buttonLeft = createLane(0, laneWidth, 0xFFC24B99, [MobileInputID.HITBOX_LEFT, MobileInputID.NOTE_LEFT]);
		buttonDown = createLane(laneWidth, laneWidth, 0xFF00FFFF, [MobileInputID.HITBOX_DOWN, MobileInputID.NOTE_DOWN]);
		buttonUp = createLane(laneWidth * 2, laneWidth, 0xFF12FA05, [MobileInputID.HITBOX_UP, MobileInputID.NOTE_UP]);
		buttonRight = createLane(laneWidth * 3, laneWidth, 0xFFF9393F, [MobileInputID.HITBOX_RIGHT, MobileInputID.NOTE_RIGHT]);

		scrollFactor.set();
		updateTrackedButtons();
	}

	function createLane(X:Int, Width:Int, Color:Int, IDs:Array<MobileInputID>):TouchButton
	{
		var lane:TouchButton = new TouchButton(X, 0, IDs);
		lane.makeGraphic(Width, Std.int(FlxG.height), 0xFFFFFFFF);
		lane.color = Color;

		// nearly invisible but still touchable; pressing it lights the lane up
		lane.alpha = 0.00001;
		lane.statusAlphas = [0.00001, 0.00001, 0.00001];

		lane.label = new FlxSprite();
		lane.label.makeGraphic(Width, BAR_HEIGHT, 0xFFFFFFFF);
		lane.label.color = Color;
		lane.label.alpha = ClientPrefs.data.controlsAlpha * 0.75;
		lane.label.y = lane.height - BAR_HEIGHT;
		lane.canChangeLabelAlpha = false;

		lane.immovable = lane.multiTouch = true;
		lane.solid = lane.moves = false;
		lane.antialiasing = ClientPrefs.data.antialiasing;

		lane.onDown.callback = function()
		{
			lane.alpha = ClientPrefs.data.controlsAlpha * 0.2;
			onButtonDown.dispatch(lane);
		}
		lane.onOut.callback = lane.onUp.callback = function()
		{
			lane.alpha = 0.00001;
			onButtonUp.dispatch(lane);
		}

		add(lane);
		return lane;
	}
}
