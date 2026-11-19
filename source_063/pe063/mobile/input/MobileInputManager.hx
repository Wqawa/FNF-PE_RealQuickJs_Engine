package pe063.mobile.input;

import flixel.util.FlxSignal.FlxTypedSignal;

import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import flixel.util.FlxSignal.FlxTypedSignal;
import haxe.ds.Map;
import pe063.mobile.objects.TouchButton;

/**
 * A group of TouchButtons plus the lookup table used for input queries.
 *
 * Port of the Mobile Porting Team's MobileInputManager (MIT). Two additions:
 *  - `onButtonDown` / `onButtonUp` live here, so anything holding a pad can
 *    listen without knowing whether it's a D-Pad or a hitbox.
 *  - `register()` / `unregister()` keep a stack of the pads currently on
 *    screen; `backend.Controls` asks `current` when it needs to know whether a
 *    control is held, which is how menu navigation and note holds work.
 */
class MobileInputManager extends FlxTypedSpriteGroup<TouchButton>
{
	public static var current(default, null):MobileInputManager;
	static var stack:Array<MobileInputManager> = [];

	/** Fired on press, release and slide-out of any button in this pad. */
	public var onButtonDown:FlxTypedSignal<TouchButton->Void> = new FlxTypedSignal<TouchButton->Void>();
	public var onButtonUp:FlxTypedSignal<TouchButton->Void> = new FlxTypedSignal<TouchButton->Void>();

	/** Every button of this pad, indexed by the IDs it answers to. */
	public var trackedButtons:Map<MobileInputID, TouchButton> = new Map<MobileInputID, TouchButton>();

	public function new()
	{
		super();
	}

	public function register():Void
	{
		stack.remove(this);
		stack.push(this);
		current = this;
	}

	public function unregister():Void
	{
		stack.remove(this);
		current = stack.length > 0 ? stack[stack.length - 1] : null;
	}

	/** Wire a button's events to this pad's signals and add it to the group. */
	public function bind(button:TouchButton):TouchButton
	{
		button.onDown.callback = () -> onButtonDown.dispatch(button);
		button.onOut.callback = button.onUp.callback = () -> onButtonUp.dispatch(button);
		add(button);
		return button;
	}

	/** Whether this pad has a button answering to `id` (menu pads have A, note pads don't). */
	public function hasButton(id:MobileInputID):Bool
		return trackedButtons.exists(id);

	/** First button whose tag matches, e.g. 'UP'. The layout editor needs this. */
	public function byTag(tag:String):TouchButton
	{
		for (button in members)
			if (button != null && button.tag == tag)
				return button;
		return null;
	}

	inline public function buttonPressed(button:MobileInputID):Bool
		return anyPressed([button]);

	inline public function buttonJustPressed(button:MobileInputID):Bool
		return anyJustPressed([button]);

	inline public function buttonJustReleased(button:MobileInputID):Bool
		return anyJustReleased([button]);

	inline public function buttonReleased(button:MobileInputID):Bool
		return anyReleased([button]);

	inline public function anyPressed(buttons:Array<MobileInputID>):Bool
		return checkButtonArrayState(buttons, PRESSED);

	inline public function anyJustPressed(buttons:Array<MobileInputID>):Bool
		return checkButtonArrayState(buttons, JUST_PRESSED);

	inline public function anyJustReleased(buttons:Array<MobileInputID>):Bool
		return checkButtonArrayState(buttons, JUST_RELEASED);

	inline public function anyReleased(buttons:Array<MobileInputID>):Bool
		return checkButtonArrayState(buttons, RELEASED);

	/** Drop every hold, e.g. when a pause menu opens on top of the pad. */
	public function releaseAll():Void
	{
		for (button in members)
			if (button != null && button.pressed)
				button.onOut.fire();
	}

	public function checkStatus(button:MobileInputID, state:ButtonsStates = JUST_PRESSED):Bool
	{
		if (button == MobileInputID.ANY)
		{
			for (id in trackedButtons.keys())
				if (checkStatusUnsafe(id, state))
					return true;
			return false;
		}

		if (button == MobileInputID.NONE)
			return false;

		return trackedButtons.exists(button) && checkStatusUnsafe(button, state);
	}

	function checkButtonArrayState(buttons:Array<MobileInputID>, state:ButtonsStates = JUST_PRESSED):Bool
	{
		if (buttons == null)
			return false;

		for (button in buttons)
			if (checkStatus(button, state))
				return true;

		return false;
	}

	function checkStatusUnsafe(button:MobileInputID, state:ButtonsStates = JUST_PRESSED):Bool
	{
		var target:TouchButton = trackedButtons.get(button);
		if (target == null)
			return false;

		return switch (state)
		{
			case RELEASED: target.released;
			case JUST_RELEASED: target.justReleased;
			case PRESSED: target.pressed;
			case JUST_PRESSED: target.justPressed;
		}
	}

	public function updateTrackedButtons():Void
	{
		trackedButtons.clear();
		forEachExists(function(button:TouchButton)
		{
			if (button == null || button.IDs == null)
				return;

			for (id in button.IDs)
				if (!trackedButtons.exists(id))
					trackedButtons.set(id, button);
		});
	}

	override public function destroy():Void
	{
		unregister();
		onButtonUp.destroy();
		onButtonDown.destroy();
		super.destroy();
	}
}

enum ButtonsStates
{
	PRESSED;
	JUST_PRESSED;
	RELEASED;
	JUST_RELEASED;
}
