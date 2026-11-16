package backend;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.text.FlxText;
import flixel.util.FlxColor;

/**
 * 崩溃屏幕。
 *
 * 这里刻意**不用**引擎自己的 Button / Alphabet / PsychUI 那一套：崩溃意味着游戏已经
 * 处在 undefined 状态，最不该假设的就是「UI 还好使」。所以全是 flixel 原生色块 + FlxText，
 * 三棵树（本仓 fork / 原版 1.0.4 / 0.6.3）才能共用同一个界面。
 *
 * 文案用英文：FlxText 的默认字体不保证带中文字形，崩在缺字体的地方很难看也没意义。
 */
class CrashState extends FlxState
{
	static inline var BTN_W:Int = 150;
	static inline var BTN_H:Int = 40;
	static inline var BTN_GAP:Int = 18;

	/** 屏上最多显示这么多字符，再多就把中间截掉 —— 完整内容在剪贴板和 dump 里 */
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

		// 崩在 PlayState 里的时候，相机还挂着他那套 zoom / scroll / 分屏设置。
		// 不换掉的话标题会被推出屏幕、底部按钮直接看不见（第一次自测就是这么翻车的）。
		FlxG.cameras.reset(new FlxCamera(0, 0, 1280, 720));

		// 一律按相机实际尺寸摆版，不读 FlxG.width/height —— 崩的时候这两个值
		// 可能还是上一个 state 留下的（实测 1920x1080），拿它算布局会整体偏出去。
		var cw:Float = FlxG.camera.width;
		var ch:Float = FlxG.camera.height;

		trace('[crash] 屏幕 ' + cw + 'x' + ch + '  (FlxG ' + FlxG.width + 'x' + FlxG.height + ')');

		var bg:FlxSprite = new FlxSprite().makeGraphic(Std.int(cw), Std.int(ch), 0xFF14100F);
		add(bg);

		// 顶部红条：一眼能看出这不是正常界面
		var bar:FlxSprite = new FlxSprite(0, 0).makeGraphic(Std.int(cw), 6, 0xFFD64545);
		add(bar);

		var title:FlxText = new FlxText(0, 20, cw, 'ENGINE CRASHED');
		title.setFormat(null, 34, 0xFFD64545, CENTER, OUTLINE_FAST, FlxColor.BLACK);
		// 注意别用「算了 width 再手动居中」的写法：FlxText.width 要等第一次 draw 才算出来，
		// create 阶段读到的是 fieldWidth。老老实实交给 fieldWidth + alignment。
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
			// 崩过之后声音/暂停状态都不可靠，先收拾一下再切
			if (FlxG.sound != null && FlxG.sound.music != null) FlxG.sound.music.stop();
			FlxG.switchState(cast Type.createInstance(cls, []));
			return;
		}
		catch (e:Dynamic)
		{
			trace('[crash] 回主菜单失败: ' + Std.string(e));
		}
		doExit();
	}

	function doExit():Void
	{
		#if sys
		Sys.exit(1);
		#end
	}

	/** 只截显示用的那份，别把整个栈塞进 FlxText */
	static function clipText(text:String):String
	{
		if (text.length <= VISIBLE_MAX) return text;

		var head:Int = Std.int(VISIBLE_MAX * 0.75);
		var tail:Int = VISIBLE_MAX - head;
		return text.substr(0, head) + '\n...\n' + text.substr(text.length - tail);
	}
}
