package pe063.options;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxColor;

/**
 * 0.6.3 侧的引擎切换界面。
 *
 * 逻辑和本体、原版那两个 pe063.options.EngineSelectSubState 一样：选中后把 engine.txt 写到
 * bin 根目录，然后退出进程，下次启动由 Main.main() 按 engine.txt 决定加载哪一棵树。
 *
 * 单独一份是因为三棵树的 ClientPrefs / Paths / Alphabet 各是各的 —— 0.6.3 的 ClientPrefs
 * 还是静态字段（ClientPrefs.globalAntialiasing），不是 1.0.4 那套 data 结构。
 */
class EngineSelectSubState extends MusicBeatSubstate
{
	var options:Array<String> = [
		'Body (Current Fork)',
		'Vanilla Psych Engine 1.0.4',
		'Psych Engine 0.6.3'
	];
	var keys:Array<String> = [Engine.BODY, Engine.VANILLA, Engine.PE063];

	var grpOptions:FlxTypedGroup<Alphabet>;
	var selectorLeft:Alphabet;
	var selectorRight:Alphabet;
	var curSelected:Int = 0;
	var errorText:FlxText;

	// 0.6.3 的 controls.ACCEPT 是「按住」语义（FlxActionDigital.check()，按住期间恒为 true），
	// 而这个界面正是用 ACCEPT 打开的 —— 打开的同一帧和之后每一帧它都还是 true。
	// 不挡一下的话，第一帧就 confirmSelection()，curSelected 又默认指向当前引擎，
	// 于是立刻 close()；父菜单看到按键没松又开一次 → 界面一闪就回去、create 日志刷屏。
	// 等到 ACCEPT 真正松手才算数。
	var acceptLatch:Bool = true;

	override function create()
	{
		super.create();

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.globalAntialiasing;
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

		for (i in 0...options.length)
		{
			var optionText:Alphabet = new Alphabet(0, 0, options[i], true);
			optionText.screenCenter();
			optionText.y += (100 * (i - (options.length / 2))) + 70;
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

		if (acceptLatch)
		{
			if (!controls.ACCEPT) acceptLatch = false;
			return;
		}

		if (controls.UI_UP_P)
			changeSelection(-1);
		if (controls.UI_DOWN_P)
			changeSelection(1);

		if (controls.BACK)
		{
			var snd = Paths.sound('cancelMenu');
			if (snd != null) FlxG.sound.play(snd);
			close();
		}
		else if (controls.ACCEPT)
			confirmSelection();
	}

	function changeSelection(change:Int = 0)
	{
		curSelected = FlxMath.wrap(curSelected + change, 0, options.length - 1);

		for (i in 0...grpOptions.length)
		{
			var item:Alphabet = grpOptions.members[i];
			item.targetY = i - curSelected;
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

		var snd = Paths.sound('scrollMenu');
		if (snd != null) FlxG.sound.play(snd);
	}

	function confirmSelection()
	{
		var chosen:String = keys[curSelected];

		if (chosen == Engine.current())
		{
			// 不 close()：现在按键还按着，父菜单下一帧就会再开一次，白闪一下。
			// 留在原地，按 BACK 退出。
			var snd = Paths.sound('cancelMenu');
			if (snd != null) FlxG.sound.play(snd);
			return;
		}

		if (!Engine.write(chosen))
		{
			errorText.text = 'Could not write ${Engine.FILE_NAME}. Check the game folder permissions.';
			FlxG.sound.play(Paths.sound('cancelMenu'));
			return;
		}

		var snd = Paths.sound('confirmMenu');
		if (snd != null) FlxG.sound.play(snd);
		Sys.exit(0);
	}
}
