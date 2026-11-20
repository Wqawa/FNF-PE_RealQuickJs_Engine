package backend;

#if (android || ios)
import flixel.FlxG;
import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldAutoSize;

// 触屏兜底键盘。直接喂 FlxG.keys 的 onKeyDown/onKeyUp，等于按了实体键，
// 不管当前是什么界面，读 controls / FlxG.keys 的逻辑都吃得到。
// 整个东西挂在 stage 上，不进任何 state，所以切界面不掉。
//
// 操作：左边的小球点开；键盘出来后拖顶栏那个方格整体移动；
// 顶栏 - / + 缩放，X 关掉。
class DebugKeyboard
{
	static var ball:Sprite;
	static var panel:Sprite;
	static var held:Map<Int, Bool> = [];

	static inline var GAP:Float = 4;
	static inline var PAD:Float = 8;
	static inline var KEY_H:Float = 34;

	// rows: [label, keyCode, optional width in "key units"]
	static var layout:Array<Array<Dynamic>> = [
		[['1', 49], ['2', 50], ['3', 51], ['4', 52], ['5', 53], ['6', 54], ['7', 55], ['8', 56], ['9', 57], ['0', 48]],
		[['Q', 81], ['W', 87], ['E', 69], ['R', 82], ['T', 84], ['Y', 89], ['U', 85], ['I', 73], ['O', 79], ['P', 80]],
		[['A', 65], ['S', 83], ['D', 68], ['F', 70], ['G', 71], ['H', 72], ['J', 74], ['K', 75], ['L', 76], [';', 186]],
		[['Z', 90], ['X', 88], ['C', 67], ['V', 86], ['B', 66], ['N', 78], ['M', 77], [',', 188], ['.', 190], ['/', 191]],
		[['SHIFT', 16, 74], ['CTRL', 17, 64], ['ALT', 18, 60], ['SPACE', 32, 210], ['ENTER', 13, 92], ['ESC', 27, 62], ['TAB', 9, 62]],
		[['←', 37], ['↑', 38], ['↓', 40], ['→', 39], ['BKSP', 8, 88], ['DEL', 46, 68]]
	];

	public static function install():Void
	{
		if (ball != null) return;
		if (openfl.Lib.current == null || openfl.Lib.current.stage == null) return;

		ball = new Sprite();
		ball.graphics.beginFill(0x1E6BFF, 0.5);
		ball.graphics.drawCircle(30, 30, 30);
		ball.graphics.endFill();

		var t:TextField = makeText('KB', 14, 0xFFFFFF);
		t.width = 60;
		t.y = 20;
		ball.addChild(t);

		ball.x = 14;
		ball.y = 130;

		var drag:Bool = false;
		var dx:Float = 0;
		var dy:Float = 0;
		var startX:Float = 0;
		var startY:Float = 0;

		ball.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent)
		{
			drag = true;
			dx = e.stageX - ball.x;
			dy = e.stageY - ball.y;
			startX = e.stageX;
			startY = e.stageY;
		});
		ball.addEventListener(MouseEvent.MOUSE_MOVE, function(e:MouseEvent)
		{
			if (!drag) return;
			ball.x = e.stageX - dx;
			ball.y = e.stageY - dy;
		});
		ball.addEventListener(MouseEvent.MOUSE_UP, function(e:MouseEvent)
		{
			if (!drag) return;
			drag = false;
			// 几乎没动才算「点」，免得拖完顺手把键盘开出来
			if (Math.abs(e.stageX - startX) < 8 && Math.abs(e.stageY - startY) < 8)
				toggle();
		});

		openfl.Lib.current.stage.addChild(ball);
	}

	public static function toggle():Void
	{
		if (panel != null) hide(); else show();
	}

	static function show():Void
	{
		if (panel != null) return;

		var stage = openfl.Lib.current.stage;
		var screenW:Float = stage.stageWidth;
		var screenH:Float = stage.stageHeight;

		// 按屏幕宽度铺开，十个键平摊
		var keyW:Float = (screenW * 0.92 - GAP * 11) / 10;
		var panelW:Float = keyW * 10 + GAP * 11 + PAD * 2;
		var panelH:Float = layout.length * (KEY_H + GAP) + PAD * 2 + 30;

		panel = new Sprite();
		panel.graphics.beginFill(0x101018, 0.82);
		panel.graphics.drawRect(0, 0, panelW, panelH);
		panel.graphics.endFill();

		// 顶栏
		panel.graphics.beginFill(0xFFFFFF, 0.1);
		panel.graphics.drawRect(0, 0, panelW, 30);
		panel.graphics.endFill();

		var title:TextField = makeText('KEYBOARD', 13, 0xBBBBCC, 'left');
		title.x = 10;
		title.y = 7;
		panel.addChild(title);

		var close:TextField = makeText('X', 15, 0xFF7777);
		close.x = panelW - 26;
		close.y = 6;
		panel.addChild(close);
		close.addEventListener(MouseEvent.MOUSE_DOWN, function(_) hide());

		var plus:TextField = makeText('+', 15, 0x77FF77);
		plus.x = panelW - 54;
		plus.y = 6;
		panel.addChild(plus);
		plus.addEventListener(MouseEvent.MOUSE_DOWN, function(_) rescale(1.15));

		var minus:TextField = makeText('-', 15, 0x77FF77);
		minus.x = panelW - 82;
		minus.y = 6;
		panel.addChild(minus);
		minus.addEventListener(MouseEvent.MOUSE_DOWN, function(_) rescale(1 / 1.15));

		// 拖动把手：屏幕短边的 5%，单独一个方块，拖它才移动键盘
		var handleSize:Float = Math.max(36, Math.min(screenW, screenH) * 0.05);
		var handle:Sprite = new Sprite();
		handle.graphics.beginFill(0x3A3A50, 1);
		handle.graphics.drawRect(0, 0, handleSize, handleSize);
		handle.graphics.endFill();
		handle.graphics.lineStyle(2, 0x6A6A90, 1);
		handle.graphics.drawRect(1, 1, handleSize - 2, handleSize - 2);
		handle.x = 100;
		handle.y = 4;
		panel.addChild(handle);

		var grip:TextField = makeText(':::', 12, 0x9999B0);
		grip.width = handleSize;
		grip.y = handleSize / 2 - 9;
		handle.addChild(grip);

		var mdrag:Bool = false;
		var mdx:Float = 0;
		var mdy:Float = 0;
		handle.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent)
		{
			mdrag = true;
			mdx = e.stageX - panel.x;
			mdy = e.stageY - panel.y;
		});
		handle.addEventListener(MouseEvent.MOUSE_MOVE, function(e:MouseEvent)
		{
			if (!mdrag) return;
			panel.x = e.stageX - mdx;
			panel.y = e.stageY - mdy;
		});
		handle.addEventListener(MouseEvent.MOUSE_UP, function(_) mdrag = false);
		handle.addEventListener(MouseEvent.MOUSE_OUT, function(_) mdrag = false);

		// 键位
		var y:Float = 30 + PAD;
		for (row in layout)
		{
			var x:Float = PAD;
			for (k in row)
			{
				var label:String = k[0];
				var code:Int = k[1];
				var w:Float = (k.length > 2) ? (k[2] * keyW / 52) : keyW;

				var key:Sprite = makeKey(label, w);
				key.x = x;
				key.y = y;
				panel.addChild(key);
				bindKey(key, code);

				x += w + GAP;
			}
			y += KEY_H + GAP;
		}

		panel.x = (screenW - panelW) / 2;
		panel.y = (screenH - panelH) / 2;
		stage.addChild(panel);
	}

	static function bindKey(key:Sprite, code:Int):Void
	{
		key.addEventListener(MouseEvent.MOUSE_DOWN, function(_)
		{
			key.alpha = 0.55;   // 按下去要有反应，不然不知道自己点没点到
			press(code);
		});
		key.addEventListener(MouseEvent.MOUSE_UP, function(_)
		{
			key.alpha = 1;
			release(code);
		});
		key.addEventListener(MouseEvent.MOUSE_OUT, function(_)
		{
			key.alpha = 1;
			release(code);
		});
	}

	public static function hide():Void
	{
		if (panel == null) return;

		for (code in held.keys())
			release(code);

		if (panel.parent != null) panel.parent.removeChild(panel);
		panel = null;
	}

	static function rescale(factor:Float):Void
	{
		if (panel == null) return;
		var next:Float = panel.scaleX * factor;
		if (next < 0.4 || next > 2.5) return;
		panel.scaleX = next;
		panel.scaleY = next;
	}

	// 直接喂 flixel 的按键表，比往 stage 派发事件稳
	static function press(code:Int):Void
	{
		if (held.exists(code)) return;
		held.set(code, true);
		@:privateAccess FlxG.keys.onKeyDown(new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, true, 0, code));
	}

	static function release(code:Int):Void
	{
		if (!held.exists(code)) return;
		held.remove(code);
		@:privateAccess FlxG.keys.onKeyUp(new KeyboardEvent(KeyboardEvent.KEY_UP, true, true, 0, code));
	}

	static function makeKey(label:String, w:Float):Sprite
	{
		var s:Sprite = new Sprite();
		s.graphics.beginFill(0x2C2C3A, 1);
		s.graphics.drawRect(0, 0, w, KEY_H);
		s.graphics.endFill();
		s.graphics.lineStyle(1, 0x4A4A60, 1);
		s.graphics.drawRect(0.5, 0.5, w - 1, KEY_H - 1);

		var t:TextField = makeText(label, label.length > 3 ? 10 : 14, 0xE8E8F0);
		t.width = w;
		t.y = (KEY_H - 17) / 2;
		s.addChild(t);

		return s;
	}

	static function makeText(text:String, size:Int, color:Int, ?align:String = 'center'):TextField
	{
		var t:TextField = new TextField();
		var f:TextFormat = new TextFormat('_sans', size, color);
		f.align = align;
		t.defaultTextFormat = f;
		t.text = text;
		t.autoSize = TextFieldAutoSize.LEFT;
		t.selectable = false;
		t.mouseEnabled = false;
		return t;
	}
}
#end
