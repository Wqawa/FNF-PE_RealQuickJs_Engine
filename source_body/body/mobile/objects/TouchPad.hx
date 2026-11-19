package mobile.objects;

import mobile.MobileLayouts;
import mobile.MobileLayouts.ButtonLayout;
import mobile.input.MobileInputID;
import mobile.input.MobileInputManager;

/**
 * The on-screen D-Pad plus action buttons.
 *
 * Port of the Mobile Porting Team's TouchPad (MIT, by Karim Akra and Homura
 * Akemi). Layouts come from MobileLayouts instead of the json files the ports
 * ship, and every button carries both a menu ID (UP/DOWN/...) and a note ID
 * (NOTE_UP/...) so one pad serves menus and gameplay.
 */
class TouchPad extends MobileInputManager
{
	public var buttonLeft:TouchButton;
	public var buttonUp:TouchButton;
	public var buttonRight:TouchButton;
	public var buttonDown:TouchButton;
	public var buttonA:TouchButton;
	public var buttonB:TouchButton;
	public var buttonC:TouchButton;
	public var buttonE:TouchButton;
	public var buttonP:TouchButton;
	public var buttonX:TouchButton;
	public var buttonY:TouchButton;

	/**
	 * @param DPad     RIGHT_FULL / LEFT_FULL / UP_DOWN / LEFT_RIGHT
	 * @param Action   A / B / A_B / A_B_E / ... see MobileLayouts.action
	 */
	public function new(DPad:String, Action:String)
	{
		super();

		for (data in MobileLayouts.dpad(DPad))
			assign(data);
		for (data in MobileLayouts.action(Action))
			assign(data);

		alpha = ClientPrefs.data.controlsAlpha;
		scrollFactor.set();
		updateTrackedButtons();
	}

	function assign(data:ButtonLayout):Void
	{
		var button:TouchButton = createButton(data.x, data.y, data.graphic, data.color, idsFor(data.button));

		switch (data.button)
		{
			case 'buttonUp': buttonUp = button;
			case 'buttonDown': buttonDown = button;
			case 'buttonLeft': buttonLeft = button;
			case 'buttonRight': buttonRight = button;
			case 'buttonA': buttonA = button;
			case 'buttonB': buttonB = button;
			case 'buttonC': buttonC = button;
			case 'buttonE': buttonE = button;
			case 'buttonP': buttonP = button;
			case 'buttonX': buttonX = button;
			case 'buttonY': buttonY = button;
			default:
		}

		bind(button);
	}

	function idsFor(field:String):Array<MobileInputID>
	{
		return switch (field)
		{
			case 'buttonUp': [MobileInputID.UP, MobileInputID.NOTE_UP];
			case 'buttonDown': [MobileInputID.DOWN, MobileInputID.NOTE_DOWN];
			case 'buttonLeft': [MobileInputID.LEFT, MobileInputID.NOTE_LEFT];
			case 'buttonRight': [MobileInputID.RIGHT, MobileInputID.NOTE_RIGHT];
			case 'buttonA': [MobileInputID.A];
			case 'buttonB': [MobileInputID.B];
			case 'buttonC': [MobileInputID.C];
			case 'buttonE': [MobileInputID.E];
			case 'buttonP': [MobileInputID.P];
			case 'buttonX': [MobileInputID.X];
			case 'buttonY': [MobileInputID.Y];
			default: [MobileInputID.NONE];
		}
	}

	function createButton(X:Float, Y:Float, Graphic:String, Color:Int, IDs:Array<MobileInputID>):TouchButton
	{
		var button:TouchButton = new TouchButton(X, Y, IDs);
		button.loadGraphic(Paths.image('mobile/touchpad/bg'));
		button.label = new FlxSprite();
		button.label.loadGraphic(Paths.image('mobile/touchpad/${Graphic.toUpperCase()}'));

		button.scale.set(0.243, 0.243);
		button.updateHitbox();
		button.updateLabelPosition();

		button.immovable = true;
		button.solid = button.moves = false;
		button.label.antialiasing = button.antialiasing = ClientPrefs.data.antialiasing;
		button.tag = Graphic.toUpperCase();
		button.color = Color;
		button.parentAlpha = button.alpha;
		return button;
	}

	override function set_alpha(Value:Float):Float
	{
		forEachAlive((button:TouchButton) -> button.parentAlpha = Value);
		return super.set_alpha(Value);
	}
}
