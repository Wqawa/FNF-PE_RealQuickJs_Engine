package vanilla.mobile.objects;

import flixel.input.FlxInput;
import flixel.input.FlxPointer;
import flixel.input.IFlxInput;
import flixel.util.FlxDestroyUtil;
import flixel.util.FlxDestroyUtil.IFlxDestroyable;
import vanilla.mobile.input.MobileInputID;
#if desktop
import flixel.input.mouse.FlxMouseButton;
#end

/**
 * A sprite that behaves like a touch button: it owns a set of MobileInputIDs
 * and fires onDown / onUp / onOver / onOut.
 *
 * Port of the Mobile Porting Team's TouchButton (MIT, by Karim Akra and
 * Homura Akemi). Two changes for this engine:
 *   - the brightness shader is gone, status is shown with alpha only. An extra
 *     fragment shader per button is not free on phones, and alpha reads fine.
 *   - on desktop it listens to the mouse button instead of FlxG.touches, so the
 *     layout can be tested in a window with -DMOBILE_CONTROLS.
 */
class TouchButton extends TypedTouchButton<FlxSprite>
{
	public static inline var NORMAL:Int = 0;
	public static inline var HIGHLIGHT:Int = 1;
	public static inline var PRESSED:Int = 2;

	/** Graphic name in upper case, used by the layout tables. */
	public var tag:String;

	/** IDs this button answers to. */
	public var IDs:Array<MobileInputID> = [];

	public function new(X:Float = 0, Y:Float = 0, ?IDs:Array<MobileInputID> = null)
	{
		super(X, Y);
		this.IDs = IDs == null ? [] : IDs;
	}

}

#if !display
@:generic
#end
class TypedTouchButton<T:FlxSprite> extends FlxSprite implements IFlxInput
{
	public var label(default, set):T;

	/** Press the button by dragging a finger over it instead of tapping it. */
	public var allowSwiping:Bool = true;

	/** Allow more than one finger on this button (hitbox hints need it). */
	public var multiTouch:Bool = false;

	public var onUp(default, null):TouchButtonEvent;
	public var onDown(default, null):TouchButtonEvent;
	public var onOver(default, null):TouchButtonEvent;
	public var onOut(default, null):TouchButtonEvent;

	public var status(default, set):Int;

	/** Alpha for NORMAL / HIGHLIGHT / PRESSED. Filled from parentAlpha. */
	public var statusAlphas:Array<Float> = [1.0, 0.95, 0.55];

	/** Added to the label alpha so the glyph stays readable over the pad. */
	public var labelStatusDiff:Float = 0.05;

	/** Set this to the group alpha, like TouchPad does. */
	public var parentAlpha(default, set):Float = 1;

	public var justReleased(get, never):Bool;
	public var released(get, never):Bool;
	public var pressed(get, never):Bool;
	public var justPressed(get, never):Bool;

	public var canChangeLabelAlpha:Bool = true;

	var _spriteLabel:FlxSprite;
	var input:FlxInput<Int>;

	/** The pointer currently holding this button, if any. */
	var currentInput:IFlxInput;

	public function new(X:Float = 0, Y:Float = 0):Void
	{
		super(X, Y);

		onUp = new TouchButtonEvent();
		onDown = new TouchButtonEvent();
		onOver = new TouchButtonEvent();
		onOut = new TouchButtonEvent();

		status = TouchButton.NORMAL;

		scrollFactor.set();
		input = new FlxInput(0);
	}

	override public function destroy():Void
	{
		label = FlxDestroyUtil.destroy(label);
		_spriteLabel = null;

		onUp = FlxDestroyUtil.destroy(onUp);
		onDown = FlxDestroyUtil.destroy(onDown);
		onOver = FlxDestroyUtil.destroy(onOver);
		onOut = FlxDestroyUtil.destroy(onOut);

		currentInput = null;
		input = null;

		super.destroy();
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (visible)
			updateButton();

		input.update();
	}

	override public function draw():Void
	{
		super.draw();

		if (_spriteLabel != null && _spriteLabel.graphic != null && _spriteLabel.pixels != null && _spriteLabel.visible)
		{
			if (_spriteLabel.cameras != cameras)
				_spriteLabel.cameras = cameras;
			_spriteLabel.draw();
		}
	}

	function updateButton():Void
	{
		var overlapFound:Bool = checkTouchOverlap();

		if (currentInput != null && currentInput.justReleased && overlapFound)
			onUpHandler();

		if (status != TouchButton.NORMAL && (!overlapFound || (currentInput != null && currentInput.justReleased)))
			onOutHandler();
	}

	function checkTouchOverlap():Bool
	{
		if (cameras == null || cameras.length == 0)
			return false;

		for (camera in cameras)
		{
			#if desktop
			var mouse:FlxMouseButton = FlxMouseButton.getByID(FlxMouseButtonID.LEFT);
			if (mouse != null && checkInput(FlxG.mouse, mouse, camera))
				return true;
			#else
			for (touch in FlxG.touches.list)
				if (checkInput(touch, touch, camera))
					return true;
			#end
		}

		return false;
	}

	function checkInput(pointer:FlxPointer, input:IFlxInput, camera:FlxCamera):Bool
	{
		if (overlapsPoint(pointer.getWorldPosition(camera, _point), true, camera))
		{
			updateStatus(input);
			return true;
		}

		return false;
	}

	function updateStatus(input:IFlxInput):Void
	{
		if (input.justPressed)
		{
			currentInput = input;
			onDownHandler();
		}
		else if (status == TouchButton.NORMAL)
		{
			// keep holding when a finger slides off and back on
			if (allowSwiping && input.pressed)
				onDownHandler();
			else
				onOverHandler();
		}
	}

	public function updateLabelPosition():Void
	{
		if (_spriteLabel != null)
		{
			_spriteLabel.x = ((width - _spriteLabel.width) / 2) + (pixelPerfectPosition ? Math.floor(x) : x);
			_spriteLabel.y = ((height - _spriteLabel.height) / 2) + (pixelPerfectPosition ? Math.floor(y) : y);
		}
	}

	function updateLabelScale():Void
	{
		if (_spriteLabel != null)
			_spriteLabel.scale.set(scale.x, scale.y);
	}

	function indicateStatus():Void
	{
		alpha = statusAlphas[status];
	}

	function onUpHandler():Void
	{
		status = TouchButton.NORMAL;
		input.release();
		currentInput = null;
		onUp.fire();
	}

	function onDownHandler():Void
	{
		status = TouchButton.PRESSED;
		input.press();
		onDown.fire();
	}

	function onOverHandler():Void
	{
		status = TouchButton.HIGHLIGHT;
		onOver.fire();
	}

	function onOutHandler():Void
	{
		status = TouchButton.NORMAL;
		input.release();
		onOut.fire();
	}

	function set_label(Value:T):T
	{
		if (Value != null)
		{
			Value.scrollFactor.put();
			Value.scrollFactor = scrollFactor;
		}

		label = Value;
		_spriteLabel = label;

		updateLabelPosition();
		return Value;
	}

	function set_status(Value:Int):Int
	{
		status = Value;
		indicateStatus();
		return status;
	}

	function set_parentAlpha(Value:Float):Float
	{
		statusAlphas = [
			Value,
			Value > 0.1 ? Value - 0.05 : Value,
			Value > 0.4 ? Value - 0.45 : (Value > 0 ? 0.25 : 0)
		];
		indicateStatus();
		return parentAlpha = Value;
	}

	override function set_alpha(Value:Float):Float
	{
		super.set_alpha(Value);
		if (_spriteLabel != null && canChangeLabelAlpha)
			_spriteLabel.alpha = alpha == 0 ? 0 : alpha + labelStatusDiff;
		return Value;
	}

	override function set_visible(Value:Bool):Bool
	{
		super.set_visible(Value);
		if (_spriteLabel != null)
			_spriteLabel.visible = Value;
		return Value;
	}

	override function set_x(Value:Float):Float
	{
		super.set_x(Value);
		updateLabelPosition();
		return x;
	}

	override function set_y(Value:Float):Float
	{
		super.set_y(Value);
		updateLabelPosition();
		return y;
	}

	override function set_color(Value:FlxColor):Int
	{
		if (_spriteLabel != null)
			_spriteLabel.color = Value;
		return super.set_color(Value);
	}

	override private function set_width(Value:Float)
	{
		super.set_width(Value);
		updateLabelScale();
		return Value;
	}

	override private function set_height(Value:Float)
	{
		super.set_height(Value);
		updateLabelScale();
		return Value;
	}

	override public function updateHitbox():Void
	{
		super.updateHitbox();
		if (_spriteLabel != null)
			_spriteLabel.updateHitbox();
	}

	inline function get_justReleased():Bool
		return input.justReleased;

	inline function get_released():Bool
		return input.released;

	inline function get_pressed():Bool
		return input.pressed;

	inline function get_justPressed():Bool
		return input.justPressed;
}

/**
 * Callback holder for a TouchButton event. Sounds were dropped, nothing here
 * played one.
 */
private class TouchButtonEvent implements IFlxDestroyable
{
	public var callback:Void->Void;

	public function new(?Callback:Void->Void)
	{
		callback = Callback;
	}

	public inline function destroy():Void
	{
		callback = null;
	}

	public inline function fire():Void
	{
		if (callback != null)
			callback();
	}
}
