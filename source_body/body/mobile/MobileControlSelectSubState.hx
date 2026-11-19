package mobile;

import mobile.input.MobileInputManager;
import mobile.objects.Hitbox;
import mobile.objects.TouchButton;
import mobile.objects.TouchPad;

/**
 * Pick a touch layout, and for 'Custom' drag the buttons to wherever they sit
 * comfortably under your thumbs.
 *
 * The Android ports keep four layouts in json and put the editor on its own
 * screen with sprite-group collision to keep buttons apart. Here the layouts
 * already live in MobileLayouts, so the pad in the middle of the screen is the
 * preview: what you drag is what you get in a song.
 */
class MobileControlSelectSubState extends MusicBeatSubstate
{
	static var MODES:Array<String> = ['Right', 'Left', 'Custom', 'Hitbox'];
	static inline var ARROW_W:Int = 90;
	static inline var ARROW_H:Int = 90;

	var mode:Int = 0;
	var preview:MobileInputManager;
	var dragged:TouchButton;

	var modeText:FlxText;
	var leftArrow:FlxText;
	var rightArrow:FlxText;
	var hint:FlxText;
	var saveRect:FlxSprite;
	var resetRect:FlxSprite;

	public function new()
	{
		super();

		// the preview pad is for looking at, not for pressing
		#if MOBILE_CONTROLS
		addMenuPad = false;
		#end

		for (i in 0...MODES.length)
			if (MODES[i] == ClientPrefs.data.controlsMode)
				mode = i;

		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0.75;
		bg.scrollFactor.set();
		add(bg);

		var title:FlxText = new FlxText(0, 26, FlxG.width, Language.getPhrase('mobile_controls_title', 'Touch Controls'));
		title.setFormat(Paths.font('vcr.ttf'), 40, FlxColor.WHITE, CENTER);
		add(title);

		leftArrow = new FlxText(480, 96, 60, '<');
		leftArrow.setFormat(Paths.font('vcr.ttf'), 44, FlxColor.WHITE, CENTER);
		add(leftArrow);

		rightArrow = new FlxText(740, 96, 60, '>');
		rightArrow.setFormat(Paths.font('vcr.ttf'), 44, FlxColor.WHITE, CENTER);
		add(rightArrow);

		modeText = new FlxText(0, 100, FlxG.width, '');
		modeText.setFormat(Paths.font('vcr.ttf'), 36, FlxColor.WHITE, CENTER);
		add(modeText);

		hint = new FlxText(0, 152, FlxG.width, '');
		hint.setFormat(Paths.font('vcr.ttf'), 20, 0xFFAAAAAA, CENTER);
		add(hint);

		saveRect = makeButton(FlxG.width - 190, 30, 160, 52, 0xFF1F8A32,
			Language.getPhrase('mobile_controls_save', 'Save'));
		resetRect = makeButton(FlxG.width - 190, 92, 160, 52, 0xFF8A1F1F,
			Language.getPhrase('mobile_controls_reset', 'Reset'));

		buildPreview();
		setMode(mode, false);
	}

	function makeButton(X:Float, Y:Float, Width:Int, Height:Int, Color:Int, Label:String):FlxSprite
	{
		var rect:FlxSprite = new FlxSprite(X, Y).makeGraphic(Width, Height, Color);
		rect.scrollFactor.set();
		add(rect);

		var text:FlxText = new FlxText(X, Y + 13, Width, Label);
		text.setFormat(Paths.font('vcr.ttf'), 22, FlxColor.WHITE, CENTER);
		add(text);
		return rect;
	}

	function buildPreview():Void
	{
		if (preview != null)
		{
			remove(preview, true);
			preview = null;
		}
		dragged = null;

		var custom:Bool = MODES[mode] == 'Custom';
		preview = switch (MODES[mode])
		{
			case 'Left': new TouchPad('LEFT_FULL', 'NONE');
			case 'Hitbox': new Hitbox();
			default: new TouchPad('RIGHT_FULL', 'NONE');
		}
		if (custom)
			MobileData.applyPositions(cast preview);

		// the player may have turned the controls fully transparent; the editor
		// still has to show something or there is nothing to drag
		preview.alpha = Math.max(ClientPrefs.data.controlsAlpha, 0.4);
		preview.scrollFactor.set();
		add(preview);
	}

	function setMode(Value:Int, PlaySound:Bool = true):Void
	{
		mode = FlxMath.wrap(Value, 0, MODES.length - 1);
		if (PlaySound)
			FlxG.sound.play(Paths.sound('scrollMenu'));

		buildPreview();

		modeText.text = MODES[mode];
		hint.text = MODES[mode] == 'Custom' ? Language.getPhrase('mobile_controls_hint', 'Drag the buttons where you want them.') : '';
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (controls.UI_LEFT_P)
			setMode(mode - 1);
		if (controls.UI_RIGHT_P)
			setMode(mode + 1);

		if (TouchUtil.justPressed || FlxG.mouse.justPressed)
			onTap();

		if (dragged != null)
		{
			if (TouchUtil.pressed || FlxG.mouse.pressed)
				dragged.setPosition(TouchUtil.pointerX - dragged.width * 0.5, TouchUtil.pointerY - dragged.height * 0.5);
			else
				dragged = null;
		}

		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			close();
		}
	}

	function onTap():Void
	{
		var x:Float = TouchUtil.pointerX;
		var y:Float = TouchUtil.pointerY;

		if (inRect(x, y, saveRect))
		{
			saveAndClose();
			return;
		}
		if (inRect(x, y, resetRect))
		{
			resetCustom();
			return;
		}
		if (pointIn(x, y, leftArrow.x, leftArrow.y, ARROW_W, ARROW_H) || pointIn(x, y, rightArrow.x, rightArrow.y, ARROW_W, ARROW_H))
		{
			setMode(mode + (x >= rightArrow.x ? 1 : -1));
			return;
		}

		if (MODES[mode] == 'Custom')
			dragged = buttonAt(x, y);
	}

	function buttonAt(x:Float, y:Float):TouchButton
	{
		var point:FlxPoint = FlxPoint.get(x, y);
		var found:TouchButton = null;
		for (button in preview.members)
		{
			if (button != null && button.overlapsPoint(point))
			{
				found = button;
				break;
			}
		}
		point.put();
		return found;
	}

	function inRect(x:Float, y:Float, rect:FlxSprite):Bool
		return pointIn(x, y, rect.x, rect.y, rect.width, rect.height);

	static inline function pointIn(x:Float, y:Float, rx:Float, ry:Float, rw:Float, rh:Float):Bool
		return x >= rx && x <= rx + rw && y >= ry && y <= ry + rh;

	function resetCustom():Void
	{
		MobileData.clearPositions();
		FlxG.sound.play(Paths.sound('cancelMenu'));
		setMode(mode, false);
	}

	function saveAndClose():Void
	{
		ClientPrefs.data.controlsMode = MODES[mode];
		if (MODES[mode] == 'Custom' && Std.isOfType(preview, TouchPad))
			MobileData.storePositions(cast preview);

		ClientPrefs.saveSettings();
		FlxG.sound.play(Paths.sound('confirmMenu'));
		close();
	}
}
