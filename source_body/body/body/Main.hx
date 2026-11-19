package body;

import debug.FPSCounter;

import flixel.graphics.FlxGraphic;
import flixel.FlxGame;
import flixel.FlxState;
import haxe.io.Path;
import openfl.Assets;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.display.StageScaleMode;
import lime.app.Application;
import states.TitleState;

#if HSCRIPT_ALLOWED
import crowplexus.iris.Iris;
import psychlua.HScript.HScriptInfos;
#end

#if (linux || mac)
import lime.graphics.Image;
#end

#if desktop
import backend.ALSoftConfig; // Just to make sure DCE doesn't remove this, since it's not directly referenced anywhere else.
#end

//crash handler stuff
#if CRASH_HANDLER
import openfl.events.UncaughtErrorEvent;
import haxe.CallStack;
import haxe.io.Path;
#end

import backend.Highscore;

// NATIVE API STUFF, YOU CAN IGNORE THIS AND SCROLL //
#if (linux && !debug)
@:cppInclude('./external/gamemode_client.h')
@:cppFileCode('#define GAMEMODE_AUTO')
#end

// // // // // // // // //
class Main extends Sprite
{
	public static final game = {
		width: 1280, // WINDOW width
		height: 720, // WINDOW height
		initialState: TitleState, // initial game state
		framerate: 60, // default framerate
		skipSplash: true, // if the default flixel splash screen should be skipped
		startFullscreen: false // if the game should start at fullscreen mode
	};

	public static var fpsVar:FPSCounter;
	
	// You can pretty much ignore everything from here on - your code should go in your states.

	// Entry point lives in the shared layer, source/Main.hx: crash handler, engine.txt, fork.
	// This class sits under body.* so the three trees name their boot classes alike
	// (body.Main / vanilla.Main / pe063.Main). It boots body only: window, saves, script bridge.

	public function new()
	{
		super();

		// Used to live in Main.main()'s body branch; moved into the constructor with the entry split
		#if sys
		psychlua.FunkinJS.verifyUtilsIntegrity();
		#end

		#if (cpp && windows)
		backend.Native.fixScaling();
		#end

		// 手机上的工作目录：<应用存储>/.realQuickJSEngine（见 backend.MobileStorage）。
		// 上游那行 android.content.Context.getExternalFilesDir() 本来就编不过 —— Haxe 侧没有
		// android.* 的 extern。lime 能给的只有内置目录，MobileStorage 会在能识别外置目录时优先用它。
		#if (android || ios)
		backend.MobileStorage.init();
		#end
		#if VIDEOS_ALLOWED
		hxvlc.util.Handle.init(#if (hxvlc >= "1.8.0")  ['--no-lua'] #end);
		#end

		#if LUA_ALLOWED
		#end
		Mods.loadTopMod();

		FlxG.save.bind('funkin', CoolUtil.getSavePath());
		Highscore.load();

		#if HSCRIPT_ALLOWED
		Iris.warn = function(x, ?pos:haxe.PosInfos) {
			Iris.logLevel(WARN, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null) newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '')  + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true) {
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true) {
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('WARNING: $msgInfo', FlxColor.YELLOW);
		}
		Iris.error = function(x, ?pos:haxe.PosInfos) {
			Iris.logLevel(ERROR, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null) newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '')  + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true) {
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true) {
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('ERROR: $msgInfo', FlxColor.RED);
		}
		Iris.fatal = function(x, ?pos:haxe.PosInfos) {
			Iris.logLevel(FATAL, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null) newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '')  + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true) {
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true) {
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('FATAL: $msgInfo', 0xFFBB0000);
		}
		#end

		#if LUA_ALLOWED Lua.set_callbacks_function(cpp.Callable.fromStaticFunction(psychlua.CallbackHandler.call)); #end
		Controls.instance = new Controls();
		ClientPrefs.loadDefaultKeys();
		#if ACHIEVEMENTS_ALLOWED Achievements.load(); #end

		// QuickJS-NG link self-test (prints once, just to confirm the static lib linked)
		trace('[quickjs-ng] smoke: ' + jsruntime.QuickJS.smokeTest());
		// The probe runs in PlayState because getProperty('health') only means something there;
		// during the menu health does not exist and would be null.
		var jsProbed:Bool = false;
		flixel.FlxG.signals.postUpdate.add(function() {
			// Drives real scripts every frame (only does anything with jsEngine=QuickJS)
			jsruntime.JSPlayer.update();
			if (jsProbed) return;
			var st:Dynamic = flixel.FlxG.state;
			if (st == null) return;
			var cn:Null<String> = Type.getClassName(Type.getClass(st));
			if (cn == null || cn.indexOf('PlayState') < 0) return;
			jsProbed = true;
			// Do not interfere while real scripts run: this probe evals into the same context and
			// sets camZooming to false, which looks like a bug in the mod's own script.
			if (jsruntime.JSPlayer.active) return;

			// Bridge self-test: throwaway context, discarded afterwards, never touches real scripts
			var hProbe:Int = jsruntime.QuickJSHandler.newContext(64);
			if (hProbe < 0) return;
			jsruntime.QuickJSHandler.installHostFunctions(hProbe);
			jsruntime.QuickJSHandler.eval(hProbe,
				"globalThis.__a = getProperty('health');"
				+ "setProperty('camZooming', 'false');"
				+ "globalThis.__b = getProperty('camZooming');"
				+ "globalThis.__c = getPropertyFromClass('ClientPrefs', 'downScroll');"
				+ "globalThis.__d = playSound('scrollMenu', '0.5');"
				+ "globalThis.__e = makeLuaSprite('__probeSpr', 'menuDesat', '100', '100');"
				+ "globalThis.__f = addLuaSprite('__probeSpr', 'false');"
				+ "globalThis.__g = setObjectCamera('__probeSpr', 'hud');", "<probe>");
			try {
				sys.FileSystem.createDirectory('./testout');
				var bf = sys.io.File.write('./testout/js_bridge.txt', false);
				bf.writeString('health=' + jsruntime.QuickJSHandler.globalString(hProbe, '__a')
					+ ' camZooming=' + jsruntime.QuickJSHandler.globalString(hProbe, '__b')
					+ ' downScroll=' + jsruntime.QuickJSHandler.globalString(hProbe, '__c')
					+ ' playSound=' + jsruntime.QuickJSHandler.globalString(hProbe, '__d')
					+ ' makeSprite=' + jsruntime.QuickJSHandler.globalString(hProbe, '__e')
					+ ' addSprite=' + jsruntime.QuickJSHandler.globalString(hProbe, '__f')
					+ ' setCam=' + jsruntime.QuickJSHandler.globalString(hProbe, '__g') + '\n');
				bf.close();
			} catch (e:Dynamic) {}
			jsruntime.QuickJSHandler.dispose(hProbe);

		});
		addChild(new FlxGame(game.width, game.height, game.initialState, game.framerate, game.framerate, game.skipSplash, game.startFullscreen));

		#if !mobile
		fpsVar = new FPSCounter(10, 3, 0xFFFFFF);
		addChild(fpsVar);
		Lib.current.stage.align = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;
		if(fpsVar != null) {
			fpsVar.visible = ClientPrefs.data.showFPS;
		}
		#end

		#if (linux || mac) // fix the app icon not showing up on the Linux Panel / Mac Dock
		var icon = Image.fromFile("icon.png");
		Lib.current.stage.window.setIcon(icon);
		#end

		#if html5
		FlxG.autoPause = false;
		FlxG.mouse.visible = false;
		#end

		FlxG.fixedTimestep = false;
		FlxG.game.focusLostFramerate = 60;
		FlxG.keys.preventDefaultKeys = [TAB];
		
		#if DISCORD_ALLOWED
		DiscordClient.prepare();
		#end

		// shader coords fix
		FlxG.signals.gameResized.add(function (w, h) {
		     if (FlxG.cameras != null) {
			   for (cam in FlxG.cameras.list) {
				if (cam != null && cam.filters != null)
					resetSpriteCache(cam.flashSprite);
			   }
			}

			if (FlxG.game != null)
			resetSpriteCache(FlxG.game);
		});
	}

	static function resetSpriteCache(sprite:Sprite):Void {		@:privateAccess {
		        sprite.__cacheBitmap = null;
			sprite.__cacheBitmapData = null;
		}
	}

}
