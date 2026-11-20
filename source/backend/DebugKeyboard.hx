package backend;

#if (android || ios)
import flixel.FlxG;
import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldAutoSize;

// 触屏兜底键盘。按键直接喂 FlxG.keys.onKeyDown/onKeyUp，等于按了实体键。
// 挂在 stage 上，不进任何 state，切界面不掉。
//
// 打开时会关掉 FlxG.mouse，否则一次点击会同时打到键盘和下面的菜单，
// 出现「点一个键顺手把后面那个选项也点了」。
class DebugKeyboard
{
	static var ball:Sprite;
	static var panel:Sprite;
	static var held:Map<Int, Bool> = [];

	static inline var GAP:Float = 3;
	static inline var PAD:Float = 6;
	static inline var BAR_H:Float = 28;

	// 一行一个数组，元素是 [标签, keyCode, 宽度(字母键为 1.0)]
	static var layout:Array<Array<Dynamic>> = [
		// 功能键
		[['ESC', 27, 1], ['F1', 112, 1], ['F2', 113, 1], ['F3', 114, 1], ['F4', 115, 1], ['F5', 116, 1], ['F6', 117, 1],
		 ['F7', 118, 1], ['F8', 119, 1], ['F9', 120, 1], ['F10', 121, 1], ['F11', 122, 1], ['F12', 123, 1]],
		// 数字行
		[['`', 192, 1], ['1', 49, 1], ['2', 50, 1], ['3', 51, 1], ['4', 52, 1], ['5', 53, 1], ['6', 54, 1], ['7', 55, 1],
		 ['8', 56, 1], ['9', 57, 1], ['0', 48, 1], ['-', 189, 1], ['=', 187, 1], ['BKSP', 8, 2]],
		// Q 行
		[['TAB', 9, 1.5], ['Q', 81, 1], ['W', 87, 1], ['E', 69, 1], ['R', 82, 1], ['T', 84, 1], ['Y', 89, 1],
		 ['U', 85, 1], ['I', 73, 1], ['O', 79, 1], ['P', 80, 1], ['[', 219, 1], [']', 221, 1], ['\\', 220, 1.5]],
		// A 行
		[['CAPS', 20, 1.75], ['A', 65, 1], ['S', 83, 1], ['D', 68, 1], ['F', 70, 1], ['G', 71, 1], ['H', 72, 1],
		 ['J', 74, 1], ['K', 75, 1], ['L', 76, 1], [';', 186, 1], ["'", 222, 1], ['ENTER', 13, 2.25]],
		// Z 行
		[['SHIFT', 16, 2.25], ['Z', 90, 1], ['X', 88, 1], ['C', 67, 1], ['V', 86, 1], ['B', 66, 1], ['N', 78, 1],
		 ['M', 77, 1], [',', 188, 1], ['.', 190, 1], ['/', 191, 1], ['SHIFT', 16, 2.75]],
		// 底行
		[['CTRL', 17, 1.25], ['ALT', 18, 1.25], ['SPACE', 32, 6], ['ALT', 18, 1.25], ['CTRL', 17, 1.25],
		 ['UP', 38, 0.75], ['DOWN', 40, 0.75], ['LEFT', 37, 0.75], ['RIGHT', 39, 0.75]]
	];

	public static function install():Void
	{
		if (ball != null) return;
		if (openfl.Lib.current == null || openfl.Lib.current.stage == null) return;

		ball = new Sprite();
		ball.graphics.beginFill(0x1E6BFF, 0.45);
		ball.graphics.drawCircle(28, 28, 28);
		ball.graphics.endFill();

		var t:TextField = makeText('KB', 13, 0xFFFFFF);
		t.width = 56;
		t.y = 19;
		ball.addChild(t);

		ball.x = 12;
		ball.y = 140;

		var drag:Bool = false;
		var dx:Float = 0;
		var dy:Float = 0;
		var sx:Float = 0;
		var sy:Float = 0;

		ball.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent)
		{
			drag = true;
			dx = e.stageX - ball.x;
			dy = e.stageY - ball.y;
			sx = e.stageX;
			sy = e.stageY;
			e.stopPropagation();
		});
		ball.addEventListener(MouseEvent.MOUSE_MOVE, function(e:MouseEvent)
		{
			if (!drag) return;
			ball.x = e.stageX - dx;
			ball.y = e.stageY - dy;
			e.stopPropagation();
		});
		ball.addEventListener(MouseEvent.MOUSE_UP, function(e:MouseEvent)
		{
			if (!drag) return;
			drag = false;
			if (Math.abs(e.stageX - sx) < 8 && Math.abs(e.stageY - sy) < 8) toggle();
			e.stopPropagation();
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

		// 一行按 15 个单位排，取屏幕的七成宽
		var unit:Float = (screenW * 0.7) / 15;
		var keyH:Float = unit * 0.9;
		var panelW:Float = unit * 15 + GAP * 15 + PAD * 2;
		var panelH:Float = BAR_H + layout.length * (keyH + GAP) + PAD * 2;

		panel = new Sprite();
		panel.graphics.beginFill(0x0E0E14, 0.9);
		panel.graphics.drawRect(0, 0, panelW, panelH);
		panel.graphics.endFill();

		panel.graphics.beginFill(0xFFFFFF, 0.08);
		panel.graphics.drawRect(0, 0, panelW, BAR_H);
		panel.graphics.endFill();

		var title:TextField = makeText('KEYBOARD', 12, 0xA9A9C0, 'left');
		title.x = 8;
		title.y = 6;
		panel.addChild(title);

		// 拖动把手，屏幕短边的 5%
		var handleSize:Float = Math.max(34, Math.min(screenW, screenH) * 0.05);
		var handle:Sprite = makeBox(handleSize, handleSize, 0x3C3C55, 0x7070A0);
		handle.x = 78;
		handle.y = (BAR_H - handleSize) / 2;
		panel.addChild(handle);

		var grip:TextField = makeText(':::', 11, 0x9A9AB8);
		grip.width = handleSize;
		grip.y = handleSize / 2 - 8;
		handle.addChild(grip);

		var mdrag:Bool = false;
		var mdx:Float = 0;
		var mdy:Float = 0;
		handle.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent)
		{
			mdrag = true;
			mdx = e.stageX - panel.x;
			mdy = e.stageY - panel.y;
			e.stopPropagation();
		});
		handle.addEventListener(MouseEvent.MOUSE_MOVE, function(e:MouseEvent)
		{
			if (!mdrag) return;
			panel.x = e.stageX - mdx;
			panel.y = e.stageY - mdy;
			e.stopPropagation();
		});
		handle.addEventListener(MouseEvent.MOUSE_UP, function(e:MouseEvent)
		{
			mdrag = false;
			e.stopPropagation();
		});

		// 顶栏按钮：用 Sprite，TextField 关了 mouseEnabled 收不到事件
		addBarButton(panel, panelW - 32, 'X', 0xFF7777, hide);
		addBarButton(panel, panelW - 68, '+', 0x77FF77, function() rescale(1.12));
		addBarButton(panel, panelW - 104, '-', 0x77FF77, function() rescale(1 / 1.12));

		// 键位
		var y:Float = BAR_H + PAD;
		for (row in layout)
		{
			var x:Float = PAD;
			for (k in row)
			{
				var label:String = k[0];
				var code:Int = k[1];
				var w:Float = k[2] * unit;

				var key:Sprite = makeKey(label, w, keyH);
				key.x = x;
				key.y = y;
				panel.addChild(key);
				bindKey(key, code);

				x += w + GAP;
			}
			y += keyH + GAP;
		}

		// 右下角缩放把手：拖它就是拉伸整个键盘
		var rz:Sprite = makeBox(24, 24, 0x445566, 0x88AACC);
		rz.x = panelW - 26;
		rz.y = panelH - 26;
		panel.addChild(rz);

		var rdrag:Bool = false;
		var startScale:Float = 1;
		var startX:Float = 0;
		rz.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent)
		{
			rdrag = true;
			startScale = panel.scaleX;
			startX = e.stageX;
			e.stopPropagation();
		});
		rz.addEventListener(MouseEvent.MOUSE_MOVE, function(e:MouseEvent)
		{
			if (!rdrag) return;
			var f:Float = 1 + ((e.stageX - startX) / panelW);
			var next:Float = Math.max(0.45, Math.min(2.2, startScale * f));
			panel.scaleX = next;
			panel.scaleY = next;
			e.stopPropagation();
		});
		rz.addEventListener(MouseEvent.MOUSE_UP, function(e:MouseEvent)
		{
			rdrag = false;
			e.stopPropagation();
		});

		panel.x = (screenW - panelW) / 2;
		panel.y = screenH - panelH - 16;
		stage.addChild(panel);

		// 键盘在最前面，先关掉 flixel 的鼠标，不然点击会穿透到下面的菜单
		FlxG.mouse.enabled = false;
	}

	public static function hide():Void
	{
		if (panel == null) return;

		for (code in held.keys())
			release(code);

		if (panel.parent != null) panel.parent.removeChild(panel);
		panel = null;
		FlxG.mouse.enabled = true;
	}

	static function addBarButton(parent:Sprite, x:Float, label:String, color:Int, cb:Void->Void):Void
	{
		var s:Sprite = makeBox(30, 22, 0x2E2E44, 0x000000);
		s.x = x;
		s.y = 3;
		var t:TextField = makeText(label, 14, color);
		t.width = 30;
		t.y = 2;
		s.addChild(t);
		parent.addChild(s);

		s.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent)
		{
			e.stopPropagation();
			cb();
		});
	}

	static function bindKey(key:Sprite, code:Int):Void
	{
		key.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent)
		{
			e.stopPropagation();
			key.alpha = 0.5;
			press(code);
		});
		key.addEventListener(MouseEvent.MOUSE_UP, function(e:MouseEvent)
		{
			e.stopPropagation();
			key.alpha = 1;
			release(code);
		});
		key.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent)
		{
			key.alpha = 1;
			release(code);
		});
	}

	static function rescale(factor:Float):Void
	{
		if (panel == null) return;
		var next:Float = panel.scaleX * factor;
		if (next < 0.45 || next > 2.2) return;
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

	static function makeKey(label:String, w:Float, h:Float):Sprite
	{
		var s:Sprite = new Sprite();
		s.graphics.beginFill(0x262632, 1);
		s.graphics.drawRect(0, 0, w, h);
		s.graphics.endFill();
		s.graphics.lineStyle(1, 0x3E3E52, 1);
		s.graphics.drawRect(0.5, 0.5, w - 1, h - 1);

		var t:TextField = makeText(label, label.length > 3 ? 9 : (label.length > 1 ? 10 : 13), 0xE4E4EE);
		t.width = w;
		t.y = h / 2 - 9;
		s.addChild(t);

		return s;
	}

	static function makeBox(w:Float, h:Float, fill:Int, border:Int):Sprite
	{
		var s:Sprite = new Sprite();
		s.graphics.beginFill(fill, 1);
		s.graphics.drawRect(0, 0, w, h);
		s.graphics.endFill();
		if (border != 0)
		{
			s.graphics.lineStyle(1, border, 1);
			s.graphics.drawRect(0.5, 0.5, w - 1, h - 1);
		}
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
