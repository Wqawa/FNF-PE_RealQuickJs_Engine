package debug;

import backend.ClientPrefs;
import backend.Paths;
import flixel.FlxG;
import flixel.input.keyboard.FlxKey;
import flixel.util.FlxStringUtil;
import openfl.display.DisplayObjectContainer;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;
import psychlua.IScriptHost;

/**
	The FPS class provides an easy-to-use monitor to display
	the current frame rate of an OpenFL project
**/
class FPSCounter extends TextField
{
	/**
		The current frame rate, expressed using frames-per-second
	**/
	public var currentFPS(default, null):Int;

	/** Logic ticks per second (update framerate). Render frames never show this. **/
	public var calcFPS(default, null):Int = 0;

	/**
		The current memory usage (WARNING: this is NOT your total program memory usage, rather it shows the garbage collector memory)
	**/
	public var memoryMegas(get, never):Float;

	/** 堆总量，跟 memoryMegas 一起看才知道 GC 离下一次回收还有多远 */
	public var totalMegas(get, never):Float;

	// F3 cycles through pages instead of dumping everything at once. The game window is
	// never tall enough for the full texture list, and a second OS window turned out to
	// wreck the main GL context, so the overlay stays in-window and scrolls instead.
	public static inline var PAGE_OFF:Int = 0;
	public static inline var PAGE_SUMMARY:Int = 1;
	public static inline var PAGE_GAME:Int = 2;
	public static inline var PAGE_SCRIPTS:Int = 3;
	public static inline var PAGE_TEXTURES:Int = 4;
	public static inline var PAGES:Int = 5;

	public var page:Int = PAGE_OFF;
	public var detailed:Bool = false;

	// What you actually see: one box per block, stacked under each other like the MC debug
	// screen. Main adds this right below the text field, which stays empty and only carries
	// the position and visibility, so Main.fpsVar keeps working for scripts.
	public var panel:Sprite;

	static inline var PAD:Float = 3;
	static inline var GAP:Float = 5;
	static inline var MARGIN:Float = 6;
	static inline var BLOCKS:Int = 5;
	static inline var FONT_SIZE:Int = 13;
	static inline var BG_COLOR:Int = 0x000000;
	static inline var BG_ALPHA:Float = 0.55;
	static inline var SCROLL_STEP:Float = 48;
	static final FONT:String = '_sans';

	var boxes:Array<Shape> = [];
	var labels:Array<TextField> = [];

	@:noCompletion private var times:Array<Float>;

	public function new(x:Float = 10, y:Float = 10, color:Int = 0x000000)
	{
		super();

		this.x = x;
		this.y = y;

		currentFPS = 0;
		selectable = false;
		mouseEnabled = false;
		defaultTextFormat = new TextFormat(FONT, FONT_SIZE, color);
		autoSize = TextFieldAutoSize.LEFT;
		multiline = true;
		text = '';

		times = [];

		panel = new Sprite();
		panel.x = 0;
		panel.y = 0;
		panel.mouseEnabled = false;
		panel.visible = false;

		// every box first, then every label, so a box never covers the text above it
		for (i in 0...BLOCKS)
		{
			var box = new Shape();
			box.visible = false;
			panel.addChild(box);
			boxes.push(box);
		}

		for (i in 0...BLOCKS)
		{
			var label = new TextField();
			label.selectable = false;
			label.mouseEnabled = false;
			label.multiline = true;
			label.wordWrap = false;
			label.x = PAD;
			label.defaultTextFormat = new TextFormat(FONT, FONT_SIZE, 0xFFFFFFFF);
			label.autoSize = TextFieldAutoSize.LEFT;
			label.visible = false;
			panel.addChild(label);
			labels.push(label);
		}

		// Logic and render rates are separate settings, so a lone frame counter can't tell
		// you whether the game itself is keeping up.
		FlxG.signals.preUpdate.add(onUpdateStart);
		FlxG.signals.postUpdate.add(onUpdateTick);
		FlxG.signals.preDraw.add(onDrawStart);
		FlxG.signals.postDraw.add(onDrawEnd);
		FlxG.signals.focusLost.add(onFocusLost);
		FlxG.signals.focusGained.add(onFocusGained);
	}

	// Losing focus pauses the game (autoPause), so repainting the overlay is pure churn.
	var focused:Bool = true;

	function onFocusLost():Void focused = false;
	function onFocusGained():Void focused = true;

	var calcCount:Int = 0;
	var calcWindowStart:Float = 0;
	static var defaultToggle:Array<FlxKey> = [F3];

	// Microseconds. Recorded every frame, shown on the summary page.
	var updateUs:Float = 0;
	var drawUs:Float = 0;
	var updateStart:Float = 0;
	var drawStart:Float = 0;

	// How far the current page is scrolled up, in pixels.
	var scrollY:Float = 0;
	var contentH:Float = 0;

	function onUpdateStart():Void
	{
		updateStart = Perf.micros();
	}

	function onDrawStart():Void
	{
		drawStart = Perf.micros();
	}

	function onDrawEnd():Void
	{
		drawUs = Perf.micros() - drawStart;
	}

	function onUpdateTick():Void
	{
		updateUs = Perf.micros() - updateStart;

		// The F3 toggle lives here, not in __enterFrame: that one only runs once per drawn
		// frame, and justPressed lasts for a single logic tick, so at update 120 / draw 60
		// every other press got eaten.
		var toggle:Array<FlxKey> = (ClientPrefs.keyBinds != null) ? ClientPrefs.keyBinds.get('fps_debug') : null;
		if (toggle == null) toggle = defaultToggle;
		if (FlxG.keys.anyJustPressed(toggle))
		{
			page = (page + 1) % PAGES;
			detailed = (page != PAGE_OFF);
			scrollY = 0;
			statNext = 0; // don't show the previous page's numbers on the new one
			updateText();
		}

		// wheel scrolls the open page. Nothing else in the game uses it, so no key to steal.
		if (page != PAGE_OFF)
		{
			var wheel:Int = FlxG.mouse.wheel;
			if (wheel != 0) scrollY -= wheel * SCROLL_STEP;
		}

		var now:Float = haxe.Timer.stamp() * 1000;
		if (calcWindowStart == 0) calcWindowStart = now;

		calcCount++;
		if (now - calcWindowStart >= 1000)
		{
			calcFPS = calcCount;
			calcCount = 0;
			calcWindowStart = now;
		}
	}

	var deltaTimeout:Float = 0.0;

	// Event Handlers
	private override function __enterFrame(deltaTime:Float):Void
	{
		final now:Float = haxe.Timer.stamp() * 1000;
		times.push(now);
		while (times[0] < now - 1000) times.shift();
		// prevents the overlay from updating every frame, why would you need to anyways @crowplexus
		if (deltaTimeout < 50) {
			deltaTimeout += deltaTime;
			return;
		}

		// this counts rendered frames, so cap it at the draw rate, not the update rate
		currentFPS = times.length < FlxG.drawFramerate ? times.length : FlxG.drawFramerate;
		updateText();
		deltaTimeout = 0.0;
	}

	public dynamic function updateText():Void { // so people can override it in hscript
		if (panel == null) return;

		panel.visible = visible;
		if (!focused) return;

		attachPanel();

		Perf.on = detailed;
		if (detailed) collect(Perf.micros());

		// the text field is only an anchor now, everything goes through the boxes
		text = '';
		layout(pageBlocks());

		// same idea as before: drop below half the draw rate and the top block goes red
		var color:Int = (currentFPS < FlxG.drawFramerate * 0.5) ? 0xFFFF0000 : 0xFFFFFFFF;
		if (labels[0].textColor != color) labels[0].textColor = color;
	}

	// Keeps the panel on the game's stage. One placement, done every refresh so a state
	// switch that rebuilds the stage cannot leave it orphaned.
	function attachPanel():Void
	{
		var want:DisplayObjectContainer = this.parent;
		if (want == null || panel.parent == want) return;

		try
		{
			if (panel.parent != null) panel.parent.removeChild(panel);
			want.addChild(panel);
		}
		catch (e:Dynamic)
		{
			trace('fps panel reparent failed: ' + e);
		}
	}

	// Lays the page out top to bottom, hugging the left edge, scrolled by scrollY. Blocks
	// that scroll past the screen are skipped instead of drawn off-screen.
	function layout(blocks:Array<String>):Void
	{
		var screenH:Float = (panel.stage != null) ? panel.stage.stageHeight : FlxG.height;

		var count:Int = Std.int(Math.min(blocks.length, BLOCKS));

		for (i in 0...BLOCKS)
		{
			var label = labels[i];
			if (i >= count || blocks[i] == null || blocks[i].length == 0)
			{
				label.visible = false;
				boxes[i].visible = false;
				continue;
			}
			label.text = blocks[i];
		}

		// keep the scroll inside the page
		var viewH:Float = screenH - MARGIN * 2;
		var maxScroll:Float = contentH - viewH;
		if (maxScroll < 0) maxScroll = 0;
		if (scrollY > maxScroll) scrollY = maxScroll;
		if (scrollY < 0) scrollY = 0;

		var y:Float = MARGIN - scrollY;
		for (i in 0...count)
		{
			var label = labels[i];
			var box = boxes[i];

			// textHeight relayouts on demand in openfl, so this is the real size
			var h:Float = label.textHeight;

			// fully off screen, no point drawing it
			if (y + h + PAD * 2 < 0 || y > screenH)
			{
				label.visible = false;
				box.visible = false;
				y += h + PAD * 2 + GAP;
				continue;
			}

			label.visible = true;
			box.visible = true;
			label.x = MARGIN + PAD;
			label.y = y + PAD;

			box.graphics.clear();
			box.graphics.beginFill(BG_COLOR, BG_ALPHA);
			box.graphics.drawRoundRect(MARGIN, y, label.textWidth + PAD * 2, h + PAD * 2, 4, 4);
			box.graphics.endFill();

			y += h + PAD * 2 + GAP;
		}

		contentH = y + scrollY + MARGIN;
	}

	function pageBlocks():Array<String>
	{
		var out:Array<String> = [];

		switch (page)
		{
			case PAGE_SCRIPTS:
				out.push(scriptBlock.length > 0 ? scriptBlock : 'scripts   none loaded');

			case PAGE_TEXTURES:
				out.push(texBlock.length > 0 ? texBlock : 'textures   none tracked');

			case PAGE_GAME:
				out.push(gameBlock.length > 0 ? gameBlock : 'game   no PlayState');

			case PAGE_SUMMARY:
				out.push('FPS $currentFPS / ${ClientPrefs.data.drawFramerate}   Calc $calcFPS / ${ClientPrefs.data.updateFramerate}'
					+ '\nupdate ${fmtMs(updateUs)}   draw ${fmtMs(drawUs)}'
					+ '\n${whereAmI()}');
				out.push('heap ${FlxStringUtil.formatBytes(memoryMegas)} / ${FlxStringUtil.formatBytes(totalMegas)}'
					+ '\naudio $audioCount'
					+ '\ntex $texCount   RAM ${FlxStringUtil.formatBytes(texRam)}   VRAM ${FlxStringUtil.formatBytes(texVram)}');
				if (charBlock.length > 0) out.push(charBlock);

			default:
				out.push('FPS $currentFPS   heap ${FlxStringUtil.formatBytes(memoryMegas)}');
				var here:String = whereAmI();
				if (here.length > 0) out.push(here);
		}

		return out;
	}

	// Live numbers, refreshed on their own slower beat than the text itself.
	var texCount:Int = 0;
	var texRam:Float = 0;
	var texVram:Float = 0;
	var audioCount:Int = 0;
	var charLines:Array<String> = [];
	var luaCount:Int = 0;
	var hxCount:Int = 0;
	var jsCount:Int = 0;
	var scriptUs:Float = 0;
	var jsHeap:Float = 0;
	var statNext:Float = 0;

	// Blocks that only change once per collect. Rebuilding a few hundred lines five times a
	// second for the same text is pure garbage, so they are built here and reused.
	var scriptBlock:String = '';
	var charBlock:String = '';
	var texBlock:String = '';
	var gameBlock:String = '';

	static inline var STAT_INTERVAL:Float = 250000; // 250 ms, in microseconds

	function collect(now:Float):Void
	{
		if (now < statNext) return;
		statNext = now + STAT_INTERVAL;

		// A state switch can free the characters / scripts mid-walk. Swallow it: the panel
		// is a debug toy and must never be the reason a song change blows up.
		try
		{
			jsHeap = jsruntime.QuickJSHandler.heapBytes();
			collectTextures();
			collectChars();
			collectScripts();
			collectGame();
		}
		catch (e:Dynamic) {}

		// window based: the next read starts counting from zero
		Perf.resetScripts();
	}

	function collectTextures():Void
	{
		texCount = 0;
		texRam = 0;
		texVram = 0;
		audioCount = 0;
		texBlock = '';

		var rows:Array<{name:String, w:Int, h:Int, bytes:Float, gpu:Bool}> = [];

		for (key => g in Paths.currentTrackedAssets)
		{
			if (g == null || g.bitmap == null) continue;
			texCount++;

			var bd = g.bitmap;
			var bytes:Float = bd.width * bd.height * 4;
			// cacheOnGPU 把 CPU 侧像素扔了（image 变 null），纹理还在显存里。
			// 分开算，不然开了缓存还显示同一个数，看不出省没省
			var gpu:Bool = (bd.image == null);
			if (gpu) texVram += bytes;
			else texRam += bytes;

			rows.push({name: shortName(key), w: bd.width, h: bd.height, bytes: bytes, gpu: gpu});
		}

		// biggest first: the one 4K sheet a mod forgot to shrink is what you're looking for
		rows.sort(function(a, b) return (a.bytes < b.bytes) ? 1 : ((a.bytes > b.bytes) ? -1 : 0));

		if (texCount > 0)
		{
			var buf = new StringBuf();
			buf.add('textures $texCount   RAM ${FlxStringUtil.formatBytes(texRam)}   VRAM ${FlxStringUtil.formatBytes(texVram)}');
			for (r in rows)
				buf.add('\n${r.name}  ${r.w}x${r.h}  ${FlxStringUtil.formatBytes(r.bytes)}${r.gpu ? ' gpu' : ''}');
			texBlock = buf.toString();
		}

		audioCount = Lambda.count(Paths.currentTrackedSounds);
	}

	// bf / dad / gf only. Modchart characters live inside their own groups and walking those
	// means poking at typed groups through reflection, not worth it on a debug line.
	function collectChars():Void
	{
		charBlock = '';
		charLines = [];
		var ps = PlayState.instance;
		if (ps == null) return;

		var seen:Array<Dynamic> = [];
		for (c in [ps.boyfriend, ps.dad, ps.gf])
		{
			if (c == null) continue;

			var bytes:Float = 0;
			if (c.graphic != null && c.graphic.bitmap != null && seen.indexOf(c.graphic) < 0)
			{
				seen.push(c.graphic);
				bytes = c.graphic.bitmap.width * c.graphic.bitmap.height * 4;
			}

			var frames:Int = (c.animation != null) ? c.animation.numFrames : 0;
			charLines.push('${c.curCharacter}  ${frames}f  ${FlxStringUtil.formatBytes(bytes)}');
		}

		if (charLines.length == 0) return;
		var buf = new StringBuf();
		buf.add('chars');
		for (line in charLines) buf.add('\n' + line);
		charBlock = buf.toString();
	}

	function collectScripts():Void
	{
		scriptBlock = '';
		luaCount = 0;
		hxCount = 0;
		jsCount = 0;
		scriptUs = 0;

		var ps = PlayState.instance;
		if (ps == null) return;

		var hosts:Array<IScriptHost> = ps.allScripts();
		var rows:Array<{name:String, bytes:Float, us:Float, calls:Int}> = [];

		for (host in hosts)
		{
			if (host == null || host.isClosed()) continue;

			var id:String = host.scriptId();
			if (id == null) id = '?';
			var lower:String = id.toLowerCase();

			var bytes:Float = host.scriptBytes();
			if (lower.endsWith('.js')) jsCount++;
			else if (lower.endsWith('.hx')) hxCount++;
			else luaCount++;

			var us:Float = Perf.scriptUs(host);
			scriptUs += us;
			rows.push({name: shortName(id), bytes: bytes, us: us, calls: Perf.scriptCalls(host)});
		}

		rows.sort(function(a, b) return (a.us == b.us) ? Std.int(b.bytes - a.bytes) : (a.us < b.us ? 1 : -1));

		var buf = new StringBuf();
		buf.add('scripts   lua $luaCount · hx $hxCount · js $jsCount   ${fmtMs(scriptUs)}');
		if (jsHeap > 0) buf.add('\njs heap ${FlxStringUtil.formatBytes(jsHeap)}');

		// no cap on purpose: hiding half the scripts is how a slow one stays unnoticed
		for (i in 0...rows.length)
		{
			var r = rows[i];
			// HScript and JS can't report their own heap, so say nothing instead of "0 B"
			var size:String = (r.bytes > 0) ? FlxStringUtil.formatBytes(r.bytes) : '-';
			buf.add('\n${r.name}  ${size}  ${fmtMs(r.us)}  x${r.calls}');
		}

		scriptBlock = buf.toString();
	}

	// Song, rhythm and judgement state. Everything here comes straight off PlayState, so it
	// is also the page that tells you whether a slow frame is engine work or mod work.
	function collectGame():Void
	{
		gameBlock = '';
		var ps = PlayState.instance;
		if (ps == null) return;

		var buf = new StringBuf();
		var song:Dynamic = PlayState.SONG;
		var songName:String = (song != null) ? Std.string(song.song) : '?';
		buf.add('song   $songName   stage ${PlayState.curStage}');

		var beats:Float = Conductor.songPosition / Conductor.crochet;
		var steps:Float = Conductor.songPosition / Conductor.stepCrochet;
		buf.add('\nbpm    ${CoolUtil.floorDecimal(Conductor.bpm, 2)}'
			+ '   beat ${CoolUtil.floorDecimal(beats, 2)}'
			+ '   step ${Std.int(steps)}');

		var len:Float = 0;
		var lenRaw:Dynamic = Reflect.getProperty(ps, 'songLength');
		if (lenRaw != null) len = cast lenRaw;

		buf.add('\npos    ${CoolUtil.floorDecimal(Conductor.songPosition / 1000, 2)}s'
			+ (len > 0 ? ' / ${CoolUtil.floorDecimal(len / 1000, 2)}s' : '')
			+ '   speed ${CoolUtil.floorDecimal(ps.songSpeed, 2)}');

		var live:Int = (ps.notes != null) ? ps.notes.length : 0;
		var waiting:Int = (ps.unspawnNotes != null) ? ps.unspawnNotes.length : 0;
		var queued:Int = (ps.killNotes != null) ? ps.killNotes.length : 0;
		buf.add('\nnotes  $live live   $waiting waiting   $queued queued');

		buf.add('\ncombo  ${ps.combo}   score ${ps.songScore}'
			+ '   acc ${CoolUtil.floorDecimal(ps.ratingPercent * 100, 2)}%'
			+ (ps.cpuControlled ? '   BOT' : ''));

		var m = FlxG.sound.music;
		if (m != null)
			buf.add('\naudio  ${CoolUtil.floorDecimal(m.volume, 2)}'
				+ '   pitch ${CoolUtil.floorDecimal(m.pitch, 2)}'
				+ '   ${m.playing ? 'playing' : 'stopped'}');

		gameBlock = buf.toString();
	}

	static function shortName(path:String):String
	{
		var s:String = path.split('\\').join('/');
		var cut:Int = s.lastIndexOf('/');
		if (cut >= 0) s = s.substr(cut + 1);
		if (s.length > 22) s = s.substr(0, 20) + '..';
		return s;
	}

	static function fmtMs(us:Float):String
	{
		// a bare Lua callback is a few microseconds, "0ms" would look like the probe is dead
		if (us <= 0) return '0us';
		if (us < 1000) return '${Math.round(us)}us';

		var ms:Float = us / 1000;
		if (ms < 10) return '${Math.round(ms * 100) / 100}ms';
		return '${Math.round(ms * 10) / 10}ms';
	}

	// Where you are + song name, in the same overlay. Reflect keeps this tree-free.
	static function whereAmI():String
	{
		var state:Dynamic = FlxG.state;
		if (state == null) return 'body/(no state)';

		var cls:Null<String> = Type.getClassName(Type.getClass(state));
		if (cls != null) cls = cls.split('.').pop();

		var out:String = 'body/' + cls;

		var song:Dynamic = Reflect.getProperty(state, 'SONG');
		if (song != null)
		{
			var name:Dynamic = Reflect.getProperty(song, 'song');
			if (name != null)
			{
				var s:String = Std.string(name);
				if (s.length > 0) out += ' · ' + s;
			}
		}
		return out;
	}

	inline function get_memoryMegas():Float
		return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);

	inline function get_totalMegas():Float
		return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_RESERVED);
}
