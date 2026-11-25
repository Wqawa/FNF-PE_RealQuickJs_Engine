package substates;

import backend.LoadSkip;
import flixel.math.FlxMath;
import flixel.text.FlxText;

// Shown before a mod song loads. Unticked = load, ticked = skip. Nothing ticked (and the
// 10 second timeout lands here) means everything loads like it always did.
class LoadPickerSubState extends MusicBeatSubstate
{
	public static inline var TIMEOUT:Float = 10;

	static inline var ROW_H:Float = 26;
	static inline var TOP:Float = 118;
	static inline var LEFT_X:Float = 40;
	static inline var RIGHT_X:Float = 700;
	static inline var FONT_SIZE:Int = 18;
	static inline var MAX_PREVIEW:Int = 10;

	var onStart:Void->Void;

	var scripts:Array<{path:String, label:String, group:String}> = [];
	var cats:Array<String> = [];

	// Right column is rebuilt whenever a category is expanded, so it can't be a fixed list.
	var rightRows:Array<{cat:String, label:String, isCat:Bool, skipIndex:Int}> = [];

	var scriptTexts:Array<FlxText> = [];
	var rightTexts:Array<FlxText> = [];

	var scriptSkip:Array<Bool> = [];
	var catSkip:Array<Bool> = [];
	var expandedCat:String = null;

	var col:Int = 0; // 0 = scripts, 1 = images
	var sel:Int = 0;
	var scroll:Int = 0;
	var viewRows:Int = 16;

	var timeLeft:Float = TIMEOUT;
	var timerText:FlxText;
	var started:Bool = false;
	var font:String = null;

	var songName:String = '';
	var diffName:String = '';

	public function new(onStart:Void->Void)
	{
		super();
		this.onStart = onStart;
		font = Paths.font('vcr.ttf');

		var song:Dynamic = PlayState.SONG;
		if (song != null) songName = Std.string(song.song);
		diffName = Difficulty.getString();

		var bg = new FlxSprite().makeGraphic(1, 1, 0xFF000000);
		bg.scale.set(FlxG.width, FlxG.height);
		bg.updateHitbox();
		bg.alpha = 0.88;
		bg.scrollFactor.set();
		add(bg);

		var title = makeText(LEFT_X, 34, 24, 'Load options  ·  $songName  ·  $diffName');
		title.color = 0xFFFFFF66;

		scripts = LoadSkip.listScripts(songName);

		for (c in LoadSkip.CATS) cats.push(c);

		makeText(LEFT_X, TOP - 34, 20, 'Scripts   (' + scripts.length + ')');
		makeText(RIGHT_X, TOP - 34, 20, 'Images');

		viewRows = Std.int((FlxG.height - TOP - 130) / ROW_H);
		if (viewRows < 4) viewRows = 4;

		for (i in 0...viewRows)
			scriptTexts.push(makeText(LEFT_X, TOP + i * ROW_H, FONT_SIZE, ''));

		// cats + up to MAX_PREVIEW preview lines
		for (i in 0...(cats.length + MAX_PREVIEW + 1))
			rightTexts.push(makeText(RIGHT_X, TOP + i * ROW_H, FONT_SIZE, ''));

		for (i in 0...scripts.length) scriptSkip.push(false);
		for (i in 0...cats.length) catSkip.push(false);

		if (scripts.length < 1)
		{
			var empty = makeText(LEFT_X, TOP, FONT_SIZE, 'no scripts found');
			empty.color = 0x888888;
		}

		var hint = makeText(LEFT_X, FlxG.height - 88, FONT_SIZE,
			'UP/DOWN select    LEFT/RIGHT column    SPACE tick = skip    TAB expand    ENTER start    ESC back');
		hint.color = 0xAAAAAA;

		var hint2 = makeText(LEFT_X, FlxG.height - 60, FONT_SIZE,
			'nothing ticked loads everything. ticked rows turn red and are not loaded.');
		hint2.color = 0x777777;

		timerText = makeText(LEFT_X, FlxG.height - 120, 20, '');
		timerText.color = 0xFFFFFF66;

		rebuildRight();
		refresh();
	}

	function makeText(x:Float, y:Float, size:Int, str:String):FlxText
	{
		var t = new FlxText(x, y, 0, str, size);
		t.setFormat(font, size, 0xFFFFFFFF, LEFT, FlxTextBorderStyle.OUTLINE, 0xFF000000);
		t.scrollFactor.set();
		t.active = false;
		add(t);
		return t;
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (started) return;

		// ESC / pad B: back out to the song list without loading anything
		if (controls.BACK)
		{
			cancel();
			return;
		}

		// the countdown only runs while you are not doing anything
		timeLeft -= elapsed;
		if (timeLeft <= 0)
		{
			finish();
			return;
		}

		timerText.text = 'starting in ' + FlxMath.roundDecimal(timeLeft, 1) + 's without input';

		var listLen:Int = (col == 0) ? scripts.length : rightRows.length;
		if (listLen > 0)
		{
			if (controls.UI_UP_P)
			{
				sel = (sel - 1 + listLen) % listLen;
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
				timeLeft = TIMEOUT;
			}
			if (controls.UI_DOWN_P)
			{
				sel = (sel + 1) % listLen;
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
				timeLeft = TIMEOUT;
			}
			if (controls.UI_LEFT_P && scripts.length > 0)
			{
				col = 0;
				sel = 0;
				timeLeft = TIMEOUT;
			}
			if (controls.UI_RIGHT_P)
			{
				col = 1;
				sel = 0;
				timeLeft = TIMEOUT;
			}
			// SPACE ticks, and only SPACE. controls.ACCEPT also covers ENTER, so using it
			// here meant ENTER ticked the highlighted row on its way to starting the song -
			// the first script in the list got skipped every single time.
			if (FlxG.keys.justPressed.SPACE)
			{
				toggle(sel);
				timeLeft = TIMEOUT;
			}
			if (FlxG.keys.justPressed.TAB && col == 1)
			{
				var row = rightRows[Std.int(Math.min(sel, rightRows.length - 1))];
				if (row != null && row.isCat)
				{
					expandedCat = (expandedCat == row.cat) ? null : row.cat;
					rebuildRight();
					sel = 0;
					timeLeft = TIMEOUT;
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
				}
			}
		}

		if (FlxG.keys.justPressed.ENTER)
		{
			finish();
			return;
		}

		// mouse: click a row to tick it
		if (FlxG.mouse.justPressed)
		{
			var my:Float = FlxG.mouse.y;
			var idx:Int = Std.int((my - TOP) / ROW_H);
			if (idx >= 0)
			{
				if (FlxG.mouse.x < RIGHT_X - 20 && idx + scroll < scripts.length)
				{
					col = 0;
					sel = idx + scroll;
					toggle(sel);
					timeLeft = TIMEOUT;
				}
				else if (FlxG.mouse.x >= RIGHT_X - 20 && idx < rightRows.length)
				{
					col = 1;
					sel = idx;
					var row = rightRows[idx];
					if (row.isCat) toggle(idx);
					else
					{
						expandedCat = row.cat;
						rebuildRight();
					}
					timeLeft = TIMEOUT;
				}
			}
		}

		refresh();
	}

	function rebuildRight():Void
	{
		rightRows = [];

		for (i in 0...cats.length)
		{
			var c:String = cats[i];
			rightRows.push({cat: c, label: LoadSkip.CAT_LABELS.get(c), isCat: true, skipIndex: i});

			if (expandedCat != c) continue;

			var imgs:Array<String> = LoadSkip.listImages(c);
			var shown:Int = Std.int(Math.min(imgs.length, MAX_PREVIEW));
			for (k in 0...shown)
				rightRows.push({cat: c, label: imgs[k], isCat: false, skipIndex: i});

			if (imgs.length > shown)
				rightRows.push({cat: c, label: '+${imgs.length - shown} more', isCat: false, skipIndex: i});
			else if (imgs.length < 1)
				rightRows.push({cat: c, label: '(nothing found)', isCat: false, skipIndex: i});
		}

		if (sel >= rightRows.length) sel = Std.int(Math.max(0, rightRows.length - 1));
	}

	function toggle(idx:Int):Void
	{
		if (col == 0)
		{
			if (idx < 0 || idx >= scriptSkip.length) return;
			scriptSkip[idx] = !scriptSkip[idx];
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
			return;
		}

		if (idx < 0 || idx >= rightRows.length) return;
		var row = rightRows[idx];
		var catIdx:Int = row.skipIndex;
		if (catIdx < 0 || catIdx >= catSkip.length) return;
		catSkip[catIdx] = !catSkip[catIdx];
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	function refresh():Void
	{
		// keep the selected script inside the visible window
		if (col == 0 && scripts.length > viewRows)
		{
			if (sel < scroll) scroll = sel;
			if (sel >= scroll + viewRows) scroll = sel - viewRows + 1;
			if (scroll > scripts.length - viewRows) scroll = scripts.length - viewRows;
			if (scroll < 0) scroll = 0;
		}

		for (i in 0...scriptTexts.length)
		{
			var t = scriptTexts[i];
			var idx:Int = i + scroll;
			if (idx >= scripts.length)
			{
				t.visible = false;
				continue;
			}

			var e = scripts[idx];
			t.visible = true;
			t.text = (scriptSkip[idx] ? '[X] ' : '[ ] ') + e.label + '   ' + e.group;
			if (col == 0 && idx == sel) t.color = 0xFFFFAA00;
			else t.color = scriptSkip[idx] ? 0xFFFF5555 : 0xFFFFFFFF;
		}

		for (i in 0...rightTexts.length)
		{
			var t = rightTexts[i];
			if (i >= rightRows.length)
			{
				t.visible = false;
				continue;
			}

			var row = rightRows[i];
			t.visible = true;

			if (row.isCat)
			{
				var mark:String = (expandedCat == row.cat) ? '- ' : '+ ';
				t.text = (catSkip[row.skipIndex] ? '[X] ' : '[ ] ') + mark + row.label;
				if (col == 1 && i == sel) t.color = 0xFFFFAA00;
				else t.color = catSkip[row.skipIndex] ? 0xFFFF5555 : 0xFFFFFFFF;
			}
			else
			{
				t.text = '      ' + row.label;
				t.color = (col == 1 && i == sel) ? 0xFFFFAA00 : 0x888888;
			}
		}
	}

	// Backs out to the song list without loading anything. The parent's closeSubState puts
	// persistentUpdate back, so freeplay keeps working straight away.
	function cancel():Void
	{
		if (started) return;
		started = true;

		// nothing was decided for this song, so ask again next time
		LoadSkip.forgetSong();

		FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
		close();
	}

	function finish():Void
	{
		if (started) return;
		started = true;

		LoadSkip.reset();
		LoadSkip.active = true;
		LoadSkip.askedKey = LoadSkip.songKey(songName, diffName);

		for (i in 0...cats.length)
			if (catSkip[i]) LoadSkip.skipped.set(cats[i], true);

		// the engine resolves scripts through Paths.findScriptFile, which can come back with a
		// different prefix, so register the bare name as a safety net too
		for (i in 0...scripts.length)
		{
			if (!scriptSkip[i]) continue;
			LoadSkip.skippedScripts.set(scripts[i].path, true);
			LoadSkip.skippedScripts.set(scripts[i].label, true);
		}

		FlxG.sound.play(Paths.sound('confirmMenu'), 0.6);

		close();

		// the parent resumes next frame; switching state inside close() itself upsets it
		new FlxTimer().start(0.001, function(tmr:FlxTimer)
		{
			if (onStart != null) onStart();
		});
	}
}
