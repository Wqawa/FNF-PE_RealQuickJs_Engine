package backend;

import lime.app.Application;
import lime.system.Display;
import lime.system.System;
import lime.ui.Window;

/**
 * Window sizing for the Graphics settings.
 *
 * One percentage, relative to the screen: 100% is as tall as the display can show in 16:9.
 * The engine lays the game out for whatever size the window is (flixel keeps 1280x720 and
 * scales the game sprite), so this is purely "how many pixels the window has".
 */
class WindowSize
{
	public static inline var ASPECT:Float = 16 / 9;
	public static inline var MIN_PCT:Int = 10;

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

	// biggest 16:9 height the screen can hold; this is what 100% means
	public static function maxHeight():Int
	{
		var d:Null<Display> = display();
		if (d == null) return 1080;

		var byHeight:Float = d.bounds.height;
		var byWidth:Float = d.bounds.width / ASPECT;
		return Std.int(Math.min(byHeight, byWidth));
	}

	public static function heightFor(pct:Int):Int
	{
		if (pct < MIN_PCT) pct = MIN_PCT;
		if (pct > 100) pct = 100;
		return Std.int(Math.round(maxHeight() * pct / 100));
	}

	// 0 means "never set": take whatever the window already is, so upgrading changes nothing
	public static function applyFromPrefs():Void
	{
		var win:Null<Window> = window();
		if (win == null) return;

		if (ClientPrefs.data.windowScale <= 0)
		{
			var max:Int = maxHeight();
			var pct:Int = max > 0 ? Std.int(Math.round(win.height * 100 / max)) : 100;
			if (pct < MIN_PCT) pct = MIN_PCT;
			if (pct > 100) pct = 100;
			ClientPrefs.data.windowScale = pct;
		}

		apply(ClientPrefs.data.windowScale);
	}

	public static function apply(pct:Int):Void
	{
		var win:Null<Window> = window();
		if (win == null) return;

		if (pct < MIN_PCT) pct = MIN_PCT;
		if (pct > 100) pct = 100;

		var h:Int = heightFor(pct);
		var w:Int = Std.int(Math.round(h * ASPECT));

		// grow/shrink around the middle of where the window already is, like a zoom, so it
		// doesn't crawl into the top-left corner every time
		var centerX:Float = win.x + win.width * 0.5;
		var centerY:Float = win.y + win.height * 0.5;

		applying = true;
		win.resize(w, h);
		win.x = Std.int(centerX - w * 0.5);
		win.y = Std.int(centerY - h * 0.5);
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

	// The player can still drag the window edges. When they do, bend the pref to what they
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
		var max:Int = maxHeight();
		if (max <= 0) return;

		var pct:Int = Std.int(Math.round(h * 100 / max));
		if (pct < MIN_PCT) pct = MIN_PCT;
		if (pct > 100) pct = 100;
		ClientPrefs.data.windowScale = pct;
	}
}
