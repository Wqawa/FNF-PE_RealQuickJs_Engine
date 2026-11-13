package backend;

import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.input.gamepad.FlxGamepadInputID;

import states.TitleState;

// Add a variable here and it will get automatically saved
@:structInit class SaveVariables {
	public var downScroll:Bool = false;
	public var middleScroll:Bool = false;
	public var opponentStrums:Bool = true;
	public var showFPS:Bool = true;
	public var flashing:Bool = true;
	public var autoPause:Bool = true;
	public var antialiasing:Bool = true;
	public var noteSkin:String = 'Default';
	public var splashSkin:String = 'Psych';
	public var splashAlpha:Float = 0.6;
	public var lowQuality:Bool = false;
	public var shaders:Bool = true;
	public var cacheOnGPU:Bool = #if !switch false #else true #end; // GPU Caching made by Raltyro
	public var framerate:Int = 60;
	public var camZooms:Bool = true;
	public var hideHud:Bool = false;
	public var noteOffset:Int = 0;
	public var arrowRGB:Array<Array<FlxColor>> = [
		[0xFFC24B99, 0xFFFFFFFF, 0xFF3C1F56],
		[0xFF00FFFF, 0xFFFFFFFF, 0xFF1542B7],
		[0xFF12FA05, 0xFFFFFFFF, 0xFF0A4447],
		[0xFFF9393F, 0xFFFFFFFF, 0xFF651038]];
	public var arrowRGBPixel:Array<Array<FlxColor>> = [
		[0xFFE276FF, 0xFFFFF9FF, 0xFF60008D],
		[0xFF3DCAFF, 0xFFF4FFFF, 0xFF003060],
		[0xFF71E300, 0xFFF6FFE6, 0xFF003100],
		[0xFFFF884E, 0xFFFFFAF5, 0xFF6C0000]];

	public var ghostTapping:Bool = true;
	public var timeBarType:String = 'Time Left';
	public var scoreZoom:Bool = true;
	public var noReset:Bool = false;
	public var healthBarAlpha:Float = 1;
	public var hitsoundVolume:Float = 0;
	public var pauseMusic:String = 'Tea Time';
	public var checkForUpdates:Bool = true;
	public var comboStacking:Bool = true;
	public var gameplaySettings:Map<String, Dynamic> = [
		'scrollspeed' => 1.0,
		'scrolltype' => 'multiplicative', 
		// anyone reading this, amod is multiplicative speed mod, cmod is constant speed mod, and xmod is bpm based speed mod.
		// an amod example would be chartSpeed * multiplier
		// cmod would just be constantSpeed = chartSpeed
		// and xmod basically works by basing the speed on the bpm.
		// iirc (beatsPerSecond * (conductorToNoteDifference / 1000)) * noteSize (110 or something like that depending on it, prolly just use note.height)
		// bps is calculated by bpm / 60
		// oh yeah and you'd have to actually convert the difference to seconds which I already do, because this is based on beats and stuff. but it should work
		// just fine. but I wont implement it because I don't know how you handle sustains and other stuff like that.
		// oh yeah when you calculate the bps divide it by the songSpeed or rate because it wont scroll correctly when speeds exist.
		// -kade
		'songspeed' => 1.0,
		'healthgain' => 1.0,
		'healthloss' => 1.0,
		'instakill' => false,
		'practice' => false,
		'botplay' => false,
		'opponentplay' => false
	];

	public var comboOffset:Array<Int> = [0, 0, 0, 0];
	public var ratingOffset:Int = 0;
	public var sickWindow:Float = 45.0;
	public var goodWindow:Float = 90.0;
	public var badWindow:Float = 135.0;
	public var safeFrames:Float = 10.0;
	public var guitarHeroSustains:Bool = true;
	public var discordRPC:Bool = true;
	public var loadingScreen:Bool = true;
	public var language:String = 'en-US';
	// false = identical Lua errors are only printed once per script (less console spam);
	// true = every single occurrence gets printed, useful when debugging
	public var moreLuaErrors:Bool = false;

	// ------------------------------------------------------------------
	// 版本差异开关（只影响本仓的 body 树，原版树不受影响）
	// 全部默认 false = 保持 1.0.4 原本行为；打开才回退成 0.6.3 那套。
	// ------------------------------------------------------------------
	/** 0.6.3 式 HUD：把 uiGroup 展开成平铺 members（老脚本按索引排层级要靠它） */
	public var compatLegacyUI:Bool = false;
	/** 0.6.3 式回血：命中音符 +0.023（1.0.4 调低了） */
	public var compatLegacyHealth:Bool = false;
	/** 0.6.3 式小图标：换一套裁剪/缩放算法，修 1.0.4 上图标被裁边 */
	public var compatLegacyIcons:Bool = false;
}

class ClientPrefs {
	// ------------------------------------------------------------------------------------
	// Psych 0.6.3 compatibility
	// Up to 0.6.3 every setting was a plain static field right here; 0.7 moved them into
	// `data`. Mods from that era still read/write ClientPrefs.downScroll directly (via
	// getPropertyFromClass or plain HScript), so the old names stay alive as forwarders.
	// ------------------------------------------------------------------------------------
	public static var downScroll(get, set):Bool;
	static inline function get_downScroll():Bool return data.downScroll;
	static inline function set_downScroll(v:Bool):Bool return data.downScroll = v;

	public static var middleScroll(get, set):Bool;
	static inline function get_middleScroll():Bool return data.middleScroll;
	static inline function set_middleScroll(v:Bool):Bool return data.middleScroll = v;

	public static var opponentStrums(get, set):Bool;
	static inline function get_opponentStrums():Bool return data.opponentStrums;
	static inline function set_opponentStrums(v:Bool):Bool return data.opponentStrums = v;

	public static var showFPS(get, set):Bool;
	static inline function get_showFPS():Bool return data.showFPS;
	static inline function set_showFPS(v:Bool):Bool return data.showFPS = v;

	public static var flashing(get, set):Bool;
	static inline function get_flashing():Bool return data.flashing;
	static inline function set_flashing(v:Bool):Bool return data.flashing = v;

	public static var globalAntialiasing(get, set):Bool;
	static inline function get_globalAntialiasing():Bool return data.antialiasing;
	static inline function set_globalAntialiasing(v:Bool):Bool return data.antialiasing = v;

	public static var lowQuality(get, set):Bool;
	static inline function get_lowQuality():Bool return data.lowQuality;
	static inline function set_lowQuality(v:Bool):Bool return data.lowQuality = v;

	public static var shaders(get, set):Bool;
	static inline function get_shaders():Bool return data.shaders;
	static inline function set_shaders(v:Bool):Bool return data.shaders = v;

	public static var framerate(get, set):Int;
	static inline function get_framerate():Int return data.framerate;
	static inline function set_framerate(v:Int):Int return data.framerate = v;

	public static var camZooms(get, set):Bool;
	static inline function get_camZooms():Bool return data.camZooms;
	static inline function set_camZooms(v:Bool):Bool return data.camZooms = v;

	public static var hideHud(get, set):Bool;
	static inline function get_hideHud():Bool return data.hideHud;
	static inline function set_hideHud(v:Bool):Bool return data.hideHud = v;

	public static var noteOffset(get, set):Int;
	static inline function get_noteOffset():Int return data.noteOffset;
	static inline function set_noteOffset(v:Int):Int return data.noteOffset = v;

	public static var ghostTapping(get, set):Bool;
	static inline function get_ghostTapping():Bool return data.ghostTapping;
	static inline function set_ghostTapping(v:Bool):Bool return data.ghostTapping = v;

	public static var timeBarType(get, set):String;
	static inline function get_timeBarType():String return data.timeBarType;
	static inline function set_timeBarType(v:String):String return data.timeBarType = v;

	public static var scoreZoom(get, set):Bool;
	static inline function get_scoreZoom():Bool return data.scoreZoom;
	static inline function set_scoreZoom(v:Bool):Bool return data.scoreZoom = v;

	public static var noReset(get, set):Bool;
	static inline function get_noReset():Bool return data.noReset;
	static inline function set_noReset(v:Bool):Bool return data.noReset = v;

	public static var healthBarAlpha(get, set):Float;
	static inline function get_healthBarAlpha():Float return data.healthBarAlpha;
	static inline function set_healthBarAlpha(v:Float):Float return data.healthBarAlpha = v;

	public static var hitsoundVolume(get, set):Float;
	static inline function get_hitsoundVolume():Float return data.hitsoundVolume;
	static inline function set_hitsoundVolume(v:Float):Float return data.hitsoundVolume = v;

	public static var pauseMusic(get, set):String;
	static inline function get_pauseMusic():String return data.pauseMusic;
	static inline function set_pauseMusic(v:String):String return data.pauseMusic = v;

	public static var checkForUpdates(get, set):Bool;
	static inline function get_checkForUpdates():Bool return data.checkForUpdates;
	static inline function set_checkForUpdates(v:Bool):Bool return data.checkForUpdates = v;

	public static var gameplaySettings(get, set):Map<String, Dynamic>;
	static inline function get_gameplaySettings():Map<String, Dynamic> return data.gameplaySettings;
	static inline function set_gameplaySettings(v:Map<String, Dynamic>):Map<String, Dynamic> return data.gameplaySettings = v;

	public static var comboOffset(get, set):Array<Int>;
	static inline function get_comboOffset():Array<Int> return data.comboOffset;
	static inline function set_comboOffset(v:Array<Int>):Array<Int> return data.comboOffset = v;

	public static var ratingOffset(get, set):Int;
	static inline function get_ratingOffset():Int return data.ratingOffset;
	static inline function set_ratingOffset(v:Int):Int return data.ratingOffset = v;

	public static var goodWindow(get, set):Int;
	static inline function get_goodWindow():Int return Std.int(data.goodWindow);
	static inline function set_goodWindow(v:Int):Int return Std.int(data.goodWindow = v);

	public static var badWindow(get, set):Int;
	static inline function get_badWindow():Int return Std.int(data.badWindow);
	static inline function set_badWindow(v:Int):Int return Std.int(data.badWindow = v);

	public static var sickWindow(get, set):Int;
	static inline function get_sickWindow():Int return Std.int(data.sickWindow);
	static inline function set_sickWindow(v:Int):Int return Std.int(data.sickWindow = v);

	public static var safeFrames(get, set):Float;
	static inline function get_safeFrames():Float return data.safeFrames;
	static inline function set_safeFrames(v:Float):Float return data.safeFrames = v;

	// 0.6.3 有、1.0 的 data 里也还有，只是当年是静态字段
	public static var comboStacking(get, set):Bool;
	static inline function get_comboStacking():Bool return data.comboStacking;
	static inline function set_comboStacking(v:Bool):Bool return data.comboStacking = v;

	// 0.6.3 stored arrow colours as HSV triplets, 1.0 keeps FlxColor arrays
	public static var arrowHSV(get, set):Array<Array<Int>>;
	static function get_arrowHSV():Array<Array<Int>>
	{
		var out:Array<Array<Int>> = [];
		if(data.arrowRGB == null) return out;

		for (col in data.arrowRGB)
		{
			if(col == null || col.length < 1) continue;
			var rgb:FlxColor = col[0];
			out.push([Std.int(rgb.hue), Std.int(rgb.saturation * 255), Std.int(rgb.brightness * 255)]);
		}
		return out;
	}
	static function set_arrowHSV(v:Array<Array<Int>>):Array<Array<Int>>
	{
		if(v == null || v.length < 1 || data.arrowRGB == null) return get_arrowHSV();

		for (i in 0...v.length)
		{
			if(i >= data.arrowRGB.length) break;
			data.arrowRGB[i][0] = FlxColor.fromHSB(v[i][0], v[i][1] / 255, v[i][2] / 255);
		}
		return v;
	}

	// --- settings that no longer exist in 1.0, kept so old mods don't blow up ---
	public static var noteSplashes(get, set):Bool;
	static var _legacyNoteSplashes:Bool = true;
	static function get_noteSplashes():Bool return _legacyNoteSplashes;
	static function set_noteSplashes(v:Bool):Bool return _legacyNoteSplashes = v;

	public static var cursing(get, set):Bool;
	static var _legacyCursing:Bool = true;
	static function get_cursing():Bool return _legacyCursing;
	static function set_cursing(v:Bool):Bool return _legacyCursing = v;

	public static var violence(get, set):Bool;
	static var _legacyViolence:Bool = true;
	static function get_violence():Bool return _legacyViolence;
	static function set_violence(v:Bool):Bool return _legacyViolence = v;

	public static var controllerMode(get, set):Bool;
	static var _legacyControllerMode:Bool = false;
	static function get_controllerMode():Bool return _legacyControllerMode;
	static function set_controllerMode(v:Bool):Bool return _legacyControllerMode = v;

	public static var data:SaveVariables = {};
	public static var defaultData:SaveVariables = {};

	//Every key has two binds, add your key bind down here and then add your control on options/ControlsSubState.hx and Controls.hx
	public static var keyBinds:Map<String, Array<FlxKey>> = [
		//Key Bind, Name for ControlsSubState
		'note_up'		=> [W, UP],
		'note_left'		=> [A, LEFT],
		'note_down'		=> [S, DOWN],
		'note_right'	=> [D, RIGHT],
		
		'ui_up'			=> [W, UP],
		'ui_left'		=> [A, LEFT],
		'ui_down'		=> [S, DOWN],
		'ui_right'		=> [D, RIGHT],
		
		'accept'		=> [SPACE, ENTER],
		'back'			=> [BACKSPACE, ESCAPE],
		'pause'			=> [ENTER, ESCAPE],
		'reset'			=> [R],
		
		'volume_mute'	=> [ZERO],
		'volume_up'		=> [NUMPADPLUS, PLUS],
		'volume_down'	=> [NUMPADMINUS, MINUS],
		
		'debug_1'		=> [SEVEN],
		'debug_2'		=> [EIGHT]
	];
	public static var gamepadBinds:Map<String, Array<FlxGamepadInputID>> = [
		'note_up'		=> [DPAD_UP, Y],
		'note_left'		=> [DPAD_LEFT, X],
		'note_down'		=> [DPAD_DOWN, A],
		'note_right'	=> [DPAD_RIGHT, B],
		
		'ui_up'			=> [DPAD_UP, LEFT_STICK_DIGITAL_UP],
		'ui_left'		=> [DPAD_LEFT, LEFT_STICK_DIGITAL_LEFT],
		'ui_down'		=> [DPAD_DOWN, LEFT_STICK_DIGITAL_DOWN],
		'ui_right'		=> [DPAD_RIGHT, LEFT_STICK_DIGITAL_RIGHT],
		
		'accept'		=> [A, START],
		'back'			=> [B],
		'pause'			=> [START],
		'reset'			=> [BACK]
	];
	public static var defaultKeys:Map<String, Array<FlxKey>> = null;
	public static var defaultButtons:Map<String, Array<FlxGamepadInputID>> = null;

	public static function resetKeys(controller:Null<Bool> = null) //Null = both, False = Keyboard, True = Controller
	{
		if(controller != true)
			for (key in keyBinds.keys())
				if(defaultKeys.exists(key))
					keyBinds.set(key, defaultKeys.get(key).copy());

		if(controller != false)
			for (button in gamepadBinds.keys())
				if(defaultButtons.exists(button))
					gamepadBinds.set(button, defaultButtons.get(button).copy());
	}

	public static function clearInvalidKeys(key:String)
	{
		var keyBind:Array<FlxKey> = keyBinds.get(key);
		var gamepadBind:Array<FlxGamepadInputID> = gamepadBinds.get(key);
		while(keyBind != null && keyBind.contains(NONE)) keyBind.remove(NONE);
		while(gamepadBind != null && gamepadBind.contains(NONE)) gamepadBind.remove(NONE);
	}

	public static function loadDefaultKeys()
	{
		defaultKeys = keyBinds.copy();
		defaultButtons = gamepadBinds.copy();
	}

	public static function saveSettings() {
		for (key in Reflect.fields(data))
			Reflect.setField(FlxG.save.data, key, Reflect.field(data, key));

		#if ACHIEVEMENTS_ALLOWED Achievements.save(); #end
		FlxG.save.flush();

		//Placing this in a separate save so that it can be manually deleted without removing your Score and stuff
		var save:FlxSave = new FlxSave();
		save.bind('controls_v3', CoolUtil.getSavePath());
		save.data.keyboard = keyBinds;
		save.data.gamepad = gamepadBinds;
		save.flush();
		FlxG.log.add("Settings saved!");
	}

	public static function loadPrefs() {
		#if ACHIEVEMENTS_ALLOWED Achievements.load(); #end

		for (key in Reflect.fields(data))
			if (key != 'gameplaySettings' && Reflect.hasField(FlxG.save.data, key))
				Reflect.setField(data, key, Reflect.field(FlxG.save.data, key));
		
		if(Main.fpsVar != null)
			Main.fpsVar.visible = data.showFPS;

		#if (!html5 && !switch)
		FlxG.autoPause = ClientPrefs.data.autoPause;

		if(FlxG.save.data.framerate == null) {
			final refreshRate:Int = FlxG.stage.application.window.displayMode.refreshRate;
			data.framerate = Std.int(FlxMath.bound(refreshRate, 60, 240));
		}
		#end

		if(data.framerate > FlxG.drawFramerate)
		{
			FlxG.updateFramerate = data.framerate;
			FlxG.drawFramerate = data.framerate;
		}
		else
		{
			FlxG.drawFramerate = data.framerate;
			FlxG.updateFramerate = data.framerate;
		}

		if(FlxG.save.data.gameplaySettings != null)
		{
			var savedMap:Map<String, Dynamic> = FlxG.save.data.gameplaySettings;
			for (name => value in savedMap)
				data.gameplaySettings.set(name, value);
		}
		
		// flixel automatically saves your volume!
		if(FlxG.save.data.volume != null)
			FlxG.sound.volume = FlxG.save.data.volume;
		if (FlxG.save.data.mute != null)
			FlxG.sound.muted = FlxG.save.data.mute;

		#if DISCORD_ALLOWED DiscordClient.check(); #end

		// controls on a separate save file
		var save:FlxSave = new FlxSave();
		save.bind('controls_v3', CoolUtil.getSavePath());
		if(save != null)
		{
			if(save.data.keyboard != null)
			{
				var loadedControls:Map<String, Array<FlxKey>> = save.data.keyboard;
				for (control => keys in loadedControls)
					if(keyBinds.exists(control)) keyBinds.set(control, keys);
			}
			if(save.data.gamepad != null)
			{
				var loadedControls:Map<String, Array<FlxGamepadInputID>> = save.data.gamepad;
				for (control => keys in loadedControls)
					if(gamepadBinds.exists(control)) gamepadBinds.set(control, keys);
			}
			reloadVolumeKeys();
		}
	}

	inline public static function getGameplaySetting(name:String, defaultValue:Dynamic = null, ?customDefaultValue:Bool = false):Dynamic
	{
		if(!customDefaultValue) defaultValue = defaultData.gameplaySettings.get(name);
		return /*PlayState.isStoryMode ? defaultValue : */ (data.gameplaySettings.exists(name) ? data.gameplaySettings.get(name) : defaultValue);
	}

	public static function reloadVolumeKeys()
	{
		TitleState.muteKeys = keyBinds.get('volume_mute').copy();
		TitleState.volumeDownKeys = keyBinds.get('volume_down').copy();
		TitleState.volumeUpKeys = keyBinds.get('volume_up').copy();
		toggleVolumeKeys(true);
	}
	public static function toggleVolumeKeys(?turnOn:Bool = true)
	{
		final emptyArray = [];
		FlxG.sound.muteKeys = turnOn ? TitleState.muteKeys : emptyArray;
		FlxG.sound.volumeDownKeys = turnOn ? TitleState.volumeDownKeys : emptyArray;
		FlxG.sound.volumeUpKeys = turnOn ? TitleState.volumeUpKeys : emptyArray;
	}
}
