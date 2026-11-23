package backend;

import lime.app.Application;
import lime.system.Display;
import lime.system.System;
import lime.ui.Window;

/**
 * Window sizing for the Graphics settings.
 *
 * The engine lays the game out for whatever size the window is (flixel resizes itself on
 * window resize), so "resolution" here really means "how many pixels the window has".
 * Picking a smaller one is cheaper, it just shows less of the stage.
 */
class WindowSize
{
	public static inline var ASPECT:Float = 16 / 9;
	public static inline var STEP:Int = 60; // 960x540, 1280x720, 1920x1080...
	public static inline var MIN_HEIGHT:Int = 180;

	static var applying:Bool = false;
	static var hooked:Bool = false;

	public static function window():Null<Window>
	{
		var app:Null<Application> = Application.current;
		return app != null ? app.window : null;
	}

	public static function display():Null<Display>
	{
		var win:Null<Window> = window();
		if (win != null && win.display != null) return win.display;
		return System.getDisplay(0);
	}

	// biggest 16:9 height the screen can hold
	public static function maxHeight():Int
	{
		var d:Null<Display> = display();
		if (d == null) return 1080;

		var byHeight:Float = d.bounds.height;
		var byWidth:Float = d.bounds.width / ASPECT;
		return Std.int(Math.min(byHeight, byWidth));
	}

	public static function clampHeight(h:Int):Int
	{
		var max:Int = maxHeight();
		if (h > max) h = max;
		if (h < MIN_HEIGHT) h = MIN_HEIGHT;
		return Std.int(Math.round(h / STEP)) * STEP;
	}

	// 0 means "never set": take whatever the window already is, so upgrading changes nothing
	public static function applyFromPrefs():Void
	{
		var win:Null<Window> = window();
		if (win == null) return;

		if (ClientPrefs.data.windowRes <= 0) ClientPrefs.data.windowRes = Std.int(win.height);
		if (ClientPrefs.data.windowScale <= 0) ClientPrefs.data.windowScale = 100;

		apply(ClientPrefs.data.windowRes, ClientPrefs.data.windowScale);
	}

	public static function apply(res:Int, scalePct:Int):Void
	{
		var win:Null<Window> = window();
		if (win == null) return;

		res = clampHeight(res);
		if (scalePct < 10) scalePct = 10;
		if (scalePct > 100) scalePct = 100;

		var h:Int = Std.int(Math.round(res * scalePct / 100));
		var w:Int = Std.int(Math.round(h * ASPECT));

		applying = true;
		win.resize(w, h); // one resize event instead of two
		keepOnScreen(win);
		applying = false;
	}

	static function keepOnScreen(win:Window):Void
	{
		var d:Null<Display> = display();
		if (d == null) return;

		var maxX:Float = d.bounds.x + d.bounds.width - win.width;
		var maxY:Float = d.bounds.y + d.bounds.height - win.height;
		if (win.x > maxX) win.x = Std.int(maxX);
		if (win.y > maxY) win.y = Std.int(maxY);
		if (win.x < d.bounds.x) win.x = Std.int(d.bounds.x);
		if (win.y < d.bounds.y) win.y = Std.int(d.bounds.y);
	}

	// The player can still drag the window edges. When they do, bend the prefs to what they
	// ended up with instead of snapping the window back on the next load.
	public static function installResizeHook():Void
	{
		var win:Null<Window> = window();
		if (win == null || hooked) return;
		hooked = true;

		win.onResize.add(function(w:Int, h:Int) {
			if (applying || h <= 0) return;
			syncFromWindow(h);
		});
	}

	static function syncFromWindow(h:Int):Void
	{
		var res:Int = ClientPrefs.data.windowRes;
		if (res <= 0) res = h;

		var pct:Int = Std.int(Math.round(h * 100 / res));
		if (pct > 100)
		{
			// dragged past the picked resolution: move the resolution up, stay at 100%
			ClientPrefs.data.windowRes = clampHeight(h);
			ClientPrefs.data.windowScale = 100;
		}
		else if (pct >= 10) ClientPrefs.data.windowScale = pct;
	}
}
