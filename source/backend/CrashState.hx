package backend;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.text.FlxText;
import flixel.util.FlxColor;

/**
 * Crash screen.
 *
 * Deliberately does not use the engine's Button / Alphabet / PsychUI: a crash means the
 * game is in an undefined state and "the UI still works" is the worst assumption. Plain
 * flixel rects and FlxText let all three trees share one screen.
 *
 * Text is English: FlxText's default font has no CJK glyphs.
 */
class CrashState extends FlxState
{
	static inline var BTN_W:Int = 150;
	static inline var BTN_H:Int = 40;
	static inline var BTN_GAP:Int = 18;

	/** Characters shown on screen; the middle is cut beyond this. Full text is copied/dumped. */
	static inline var VISIBLE_MAX:Int = 1800;

	var detail:String;
	var buttons:Array<{box:FlxSprite, cb:Void->Void}> = [];
	var hint:FlxText;

	public function new(detail:String)
	{
		super();
		this.detail = (detail == null) ? '' : detail;
	}

	override function create():Void
	{
		super.create();

		#if desktop
		FlxG.mouse.visible = true;
		#end

		// Crashing inside PlayState leaves its zoom / scroll / split-screen settings on the camera.
		// Without resetting them the title goes off screen and the buttons vanish.
		FlxG.cameras.reset(new FlxCamera(0, 0, 1280, 720));

		// Lay out against the camera's real size, not FlxG.width/height: after a crash those can
		// still hold the previous state's values (1920x1080 seen in practice) and shift everything.
		var cw:Float = FlxG.camera.width;
		var ch:Float = FlxG.camera.height;

		trace('[crash] screen ' + cw + 'x' + ch + '  (FlxG ' + FlxG.width + 'x' + FlxG.height + ')');

		var bg:FlxSprite = new FlxSprite().makeGraphic(Std.int(cw), Std.int(ch), 0xFF14100F);
		add(bg);

		// Red bar on top: obvious at a glance that this is not the normal UI
		var bar:FlxSprite = new FlxSprite(0, 0).makeGraphic(Std.int(cw), 6, 0xFFD64545);
		add(bar);

		var title:FlxText = new FlxText(0, 20, cw, 'ENGINE CRASHED');
		title.setFormat(null, 34, 0xFFD64545, CENTER, OUTLINE_FAST, FlxColor.BLACK);
		// Do not compute width and centre manually: FlxText.width is only valid after the first
		// draw and reads as fieldWidth during create. Use fieldWidth plus alignment.
		title.fieldWidth = cw;
		title.alignment = CENTER;
		title.x = 0;
		add(title);

		var sub:FlxText = new FlxText(0, 64, cw, 'An uncaught error stopped the frame. Details below.');
		sub.setFormat(null, 14, 0xFF9C8F8C, CENTER);
		sub.fieldWidth = cw;
		sub.alignment = CENTER;
		sub.x = 0;
		add(sub);

		var box:FlxText = new FlxText(40, 96, cw - 80, clipText(detail));
		box.setFormat(null, 13, 0xFFE9E2E0, LEFT);
		add(box);

		hint = new FlxText(0, ch - 108, cw, 'Press C or click COPY to put everything on the clipboard.');
		hint.setFormat(null, 13, 0xFF9C8F8C, CENTER);
		hint.fieldWidth = cw;
		hint.alignment = CENTER;
		hint.x = 0;
		add(hint);

		var total:Float = BTN_W * 3 + BTN_GAP * 2;
		var left:Float = (cw - total) / 2;
		var top:Float = ch - 66;

		addButton('COPY (C)', left, top, doCopy);
		addButton('MAIN MENU', left + BTN_W + BTN_GAP, top, doMenu);
		addButton('QUIT', left + (BTN_W + BTN_GAP) * 2, top, doExit);
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (FlxG.keys.justPressed.C) doCopy();
		if (FlxG.keys.justPressed.ESCAPE || FlxG.keys.justPressed.M) doMenu();

		if (FlxG.mouse != null && FlxG.mouse.justPressed)
		{
			for (b in buttons)
			{
				if (over(b.box))
				{
					b.cb();
					return;
				}
			}
		}
	}

	inline function over(s:FlxSprite):Bool
	{
		var mx:Float = FlxG.mouse.x;
		var my:Float = FlxG.mouse.y;
		return mx >= s.x && mx <= s.x + s.width && my >= s.y && my <= s.y + s.height;
	}

	function addButton(label:String, x:Float, y:Float, cb:Void->Void):Void
	{
		var box:FlxSprite = new FlxSprite(x, y).makeGraphic(BTN_W, BTN_H, 0xFF3A2530);
		add(box);

		var text:FlxText = new FlxText(x, y + (BTN_H - 18) / 2, BTN_W, label);
		text.setFormat(null, 14, 0xFFEDE3E6, CENTER);
		add(text);

		buttons.push({box: box, cb: cb});
	}

	function doCopy():Void
	{
		var ok:Bool = EngineCrash.copy(detail);
		hint.text = ok ? 'Copied to clipboard.' : 'Copy failed - the full text is in the crash dump file.';
		hint.color = ok ? 0xFF7FD07F : 0xFFD6A25B;
	}

	function doMenu():Void
	{
		var cls:Dynamic = EngineCrash.mainMenuClass();
		try
		{
			if (cls == null) throw 'main menu class not found';
			// Sound and pause state are unreliable after a crash; tidy up before switching
			if (FlxG.sound != null && FlxG.sound.music != null) FlxG.sound.music.stop();
			FlxG.switchState(cast Type.createInstance(cls, []));
			return;
		}
		catch (e:Dynamic)
		{
			trace('[crash] returning to the main menu failed: ' + Std.string(e));
		}
		doExit();
	}

	function doExit():Void
	{
		#if sys
		Sys.exit(1);
		#end
	}

	/** Truncates for display only; the whole stack does not belong in a FlxText. */
	static function clipText(text:String):String
	{
		if (text.length <= VISIBLE_MAX) return text;

		var head:Int = Std.int(VISIBLE_MAX * 0.75);
		var tail:Int = VISIBLE_MAX - head;
		return text.substr(0, head) + '\n...\n' + text.substr(text.length - tail);
	}
}
