package options;

/**
 * 引擎切换界面（本体侧）。
 *
 * 选中后把 engine.txt 写到 bin 根目录，然后退出进程，
 * 下次启动由 Main.main() 按 engine.txt 决定加载本体还是原版 1.0.4。
 * 原版侧有一份同样逻辑的 vanilla.options.EngineSelectSubState，两边各自用自己那套
 * ClientPrefs / Paths（原版模式下本体的 ClientPrefs 还没加载）。
 */
class EngineSelectSubState extends MusicBeatSubstate
{
	var options:Array<String> = [
		'Body (Current Fork)',
		'Vanilla Psych Engine 1.0.4'
	];
	var keys:Array<String> = [Engine.BODY, Engine.VANILLA];

	var grpOptions:FlxTypedGroup<Alphabet>;
	var selectorLeft:Alphabet;
	var selectorRight:Alphabet;
	var curSelected:Int = 0;
	var errorText:FlxText;

	override function create()
	{
		super.create();

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.color = 0xFF71bdfd;
		bg.updateHitbox();
		bg.screenCenter();
		add(bg);

		var title:FlxText = new FlxText(0, 40, FlxG.width, 'Select Engine', 32);
		title.setFormat(Paths.font('vcr.ttf'), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.scrollFactor.set();
		add(title);

		var current:FlxText = new FlxText(0, 84, FlxG.width, 'Current: ${Engine.current()}', 16);
		current.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		current.scrollFactor.set();
		add(current);

		grpOptions = new FlxTypedGroup<Alphabet>();
		add(grpOptions);

		for (num => option in options)
		{
			var optionText:Alphabet = new Alphabet(0, 0, option, true);
			optionText.screenCenter();
			optionText.y += (100 * (num - (options.length / 2))) + 70;
			grpOptions.add(optionText);
		}

		selectorLeft = new Alphabet(0, 0, '>', true);
		add(selectorLeft);
		selectorRight = new Alphabet(0, 0, '<', true);
		add(selectorRight);

		var hint:FlxText = new FlxText(0, FlxG.height - 60, FlxG.width, 'Switching writes engine.txt and restarts the game.', 16);
		hint.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hint.scrollFactor.set();
		add(hint);

		errorText = new FlxText(0, FlxG.height - 34, FlxG.width, '', 16);
		errorText.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.RED, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		errorText.scrollFactor.set();
		add(errorText);

		curSelected = keys.indexOf(Engine.current());
		if (curSelected < 0) curSelected = 0;
		changeSelection();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (controls.UI_UP_P)
			changeSelection(-1);
		if (controls.UI_DOWN_P)
			changeSelection(1);

		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			close();
		}
		else if (controls.ACCEPT)
			confirmSelection();
	}

	function changeSelection(change:Int = 0)
	{
		curSelected = FlxMath.wrap(curSelected + change, 0, options.length - 1);

		for (num => item in grpOptions.members)
		{
			item.targetY = num - curSelected;
			item.alpha = 0.6;
			if (item.targetY == 0)
			{
				item.alpha = 1;
				selectorLeft.x = item.x - 63;
				selectorLeft.y = item.y;
				selectorRight.x = item.x + item.width + 15;
				selectorRight.y = item.y;
			}
		}

		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	function confirmSelection()
	{
		var chosen:String = keys[curSelected];

		if (chosen == Engine.current())
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			close();
			return;
		}

		if (!Engine.write(chosen))
		{
			errorText.text = 'Could not write ${Engine.FILE_NAME}. Check the game folder permissions.';
			FlxG.sound.play(Paths.sound('cancelMenu'));
			return;
		}

		FlxG.sound.play(Paths.sound('confirmMenu'));
		Sys.exit(0);
	}
}
