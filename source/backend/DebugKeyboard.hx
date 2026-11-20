package backend;

#if (android || ios)
import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.system.Capabilities;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldAutoSize;

// 触屏兜底键盘：直接往 stage 派发真的 key 事件，所以屏幕上不管是什么界面，
// 读 FlxG.keys / controls 的那套逻辑都会当成接了个实体键盘。
// 挂在 stage 上（不是 flixel 的 state 里），所以切界面不会掉。
class DebugKeyboard
{
	static var root:Sprite;
	static var ball:Sprite;
	static var held:Map<Int, Bool> = [];

	static inline var KEY_H:Float = 34;
	static inline var KEY_GAP:Float = 4;
	static inline var PAD:Float = 8;

	// 常驻的悬浮球，点一下开合键盘。挂在 stage 上，切界面不会消失。
	public static function install():Void
	{
		if (ball != null || openfl.Lib.current == null || openfl.Lib.current.stage == null) return;

		ball = new Sprite();
		ball.graphics.beginFill(0x1E6BFF, 0.45);
		ball.graphics.drawCircle(26, 26, 26);
		ball.graphics.endFill();

		var t:TextField = makeText('KB', 15, 0xFFFFFF);
		t.width = 52;
		t.x = 0;
		t.y = 16;
		ball.addChild(t);

		ball.x = 16;
		ball.y = 120;
		ball.alpha = 0.6;

		var drag:Bool = false;
		var dx:Float = 0;
		var dy:Float = 0;
		var moved:Bool = false;

		ball.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent)
		{
			drag = true;
			moved = false;
			dx = e.stageX - ball.x;
			dy = e.stageY - ball.y;
		});
		ball.addEventListener(MouseEvent.MOUSE_MOVE, function(e:MouseEvent)
		{
			if (!drag) return;
			if (Math.abs(e.stageX - ball.x - dx) > 6 || Math.abs(e.stageY - ball.y - dy) > 6) moved = true;
			ball.x = e.stageX - dx;
			ball.y = e.stageY - dy;
		});
		ball.addEventListener(MouseEvent.MOUSE_UP, function(_)
		{
			drag = false;
			if (!moved) toggle();
		});

		openfl.Lib.current.stage.addChild(ball);
	}

	// rows: label -> key code. "-" is a spacer, "|" starts a new row.
	static var layout:Array<Array<Dynamic>> = [
		[['1', 49], ['2', 50], ['3', 51], ['4', 52], ['5', 53], ['6', 54], ['7', 55], ['8', 56], ['9', 57], ['0', 48]],
		[['Q', 81], ['W', 87], ['E', 69], ['R', 82], ['T', 84], ['Y', 89], ['U', 85], ['I', 73], ['O', 79], ['P', 80]],
		[['A', 65], ['S', 83], ['D', 68], ['F', 70], ['G', 71], ['H', 72], ['J', 74], ['K', 75], ['L', 76], [';', 186]],
		[['Z', 90], ['X', 88], ['C', 67], ['V', 86], ['B', 66], ['N', 78], ['M', 77], [',', 188], ['.', 190], ['/', 191]],
		[['SHIFT', 16, 74], ['CTRL', 17, 64], ['ALT', 18, 60], ['SPACE', 32, 220], ['ENTER', 13, 96], ['ESC', 27, 64], ['TAB', 9, 64]],
		[['←', 37], ['↑', 38], ['↓', 40], ['→', 39], ['BKSP', 8, 90], ['DEL', 46, 70]]
	];

	public static function toggle():Void
	{
		if (root != null)
			hide();
		else
			show();
	}

	public static function show():Void
	{
		if (root != null) return;

		root = new Sprite();

		var panelW:Float = measureWidth() + PAD * 2;
		var panelH:Float = layout.length * (KEY_H + KEY_GAP) + PAD * 3;

		root.graphics.beginFill(0x000000, 0.72);
		root.graphics.drawRect(0, 0, panelW, panelH);
		root.graphics.endFill();

		// 标题条，拖它移动；右边两个键调大小
		var barH:Float = 26;
		root.graphics.beginFill(0xFFFFFF, 0.12);
		root.graphics.drawRect(0, 0, panelW, barH);
		root.graphics.endFill();

		var title:TextField = makeText('KEYBOARD  (drag to move)', 14, 0xFFFFFF);
		title.x = 8;
		title.y = 5;
		root.addChild(title);

		var close:TextField = makeText('X', 16, 0xFF8888);
		close.x = panelW - 24;
		close.y = 5;
		root.addChild(close);
		close.addEventListener(MouseEvent.CLICK, function(_) hide());

		var resize:TextField = makeText('+', 16, 0x88FF88);
		resize.x = panelW - 48;
		resize.y = 5;
		root.addChild(resize);
		resize.addEventListener(MouseEvent.CLICK, function(_) rescale(1.15));

		var shrink:TextField = makeText('-', 16, 0x88FF88);
		shrink.x = panelW - 72;
		shrink.y = 5;
		root.addChild(shrink);
		shrink.addEventListener(MouseEvent.CLICK, function(_) rescale(1 / 1.15));

		var y:Float = barH + PAD;
		for (row in layout)
		{
			var x:Float = PAD;
			for (k in row)
			{
				var label:String = k[0];
				var code:Int = k[1];
				var w:Float = (k.length > 2) ? k[2] : 52;

				var key:Sprite = makeKey(label, w);
				key.x = x;
				key.y = y;
				root.addChild(key);

				// hold, not tap: a lot of UI wants a real press/release pair
				key.addEventListener(MouseEvent.MOUSE_DOWN, function(_) press(code));
				key.addEventListener(MouseEvent.MOUSE_UP, function(_) release(code));
				key.addEventListener(MouseEvent.MOUSE_OUT, function(_) release(code));

				x += w + KEY_GAP;
			}
			y += KEY_H + KEY_GAP;
		}

		// 拖动
		var drag:Bool = false;
		var dx:Float = 0;
		var dy:Float = 0;
		root.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent)
		{
			if (e.target != root) return; // 只有面板空白处能拖
			drag = true;
			dx = e.stageX - root.x;
			dy = e.stageY - root.y;
		});
		root.addEventListener(MouseEvent.MOUSE_MOVE, function(e:MouseEvent)
		{
			if (!drag) return;
			root.x = e.stageX - dx;
			root.y = e.stageY - dy;
		});
		root.addEventListener(MouseEvent.MOUSE_UP, function(_) drag = false);

		root.x = 40;
		root.y = 40;

		openfl.Lib.current.stage.addChild(root);
	}

	public static function hide():Void
	{
		if (root == null) return;

		// 松开所有还按着的键，不然界面会以为一直按住
		for (code in held.keys())
			release(code);

		if (root.parent != null) root.parent.removeChild(root);
		root = null;
	}

	static function rescale(factor:Float):Void
	{
		if (root == null) return;

		var next:Float = root.scaleX * factor;
		if (next < 0.5 || next > 3) return;
		root.scaleX = next;
		root.scaleY = next;
	}

	static function press(code:Int):Void
	{
		if (held.exists(code)) return;
		held.set(code, true);

		var stage = openfl.Lib.current.stage;
		stage.dispatchEvent(new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, true, 0, code));
	}

	static function release(code:Int):Void
	{
		if (!held.exists(code)) return;
		held.remove(code);

		var stage = openfl.Lib.current.stage;
		stage.dispatchEvent(new KeyboardEvent(KeyboardEvent.KEY_UP, true, true, 0, code));
	}

	static function measureWidth():Float
	{
		var widest:Float = 0;
		for (row in layout)
		{
			var w:Float = 0;
			for (k in row)
				w += ((k.length > 2) ? k[2] : 52) + KEY_GAP;
			if (w > widest) widest = w;
		}
		return widest;
	}

	static function makeKey(label:String, w:Float):Sprite
	{
		var s:Sprite = new Sprite();
		s.graphics.beginFill(0x2A2A35, 0.95);
		s.graphics.drawRect(0, 0, w, KEY_H);
		s.graphics.endFill();

		var t:TextField = makeText(label, label.length > 3 ? 11 : 15, 0xFFFFFF);
		t.width = w;
		t.x = 0;
		t.y = (KEY_H - 18) / 2;
		s.addChild(t);

		return s;
	}

	static function makeText(text:String, size:Int, color:Int):TextField
	{
		var t:TextField = new TextField();
		var f:TextFormat = new TextFormat('_sans', size, color);
		f.align = 'center';
		t.defaultTextFormat = f;
		t.text = text;
		t.autoSize = TextFieldAutoSize.LEFT;
		t.selectable = false;
		t.mouseEnabled = false;
		return t;
	}
}
#end
