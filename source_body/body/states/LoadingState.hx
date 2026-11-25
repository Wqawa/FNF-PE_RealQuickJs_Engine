package states;

import lime.app.Future;
import sys.thread.FixedThreadPool;
import haxe.Json;
import lime.utils.Assets;
import openfl.display.BitmapData;
import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;
import flixel.graphics.FlxGraphic;
import flixel.system.FlxAssets;
import flixel.FlxState;

import flash.media.Sound;

import backend.Song;
import backend.StageData;
import objects.Character;

import sys.thread.Thread;
import sys.thread.Mutex;

import objects.Note;
import objects.NoteSplash;

#if HSCRIPT_ALLOWED
import psychlua.HScript;
import crowplexus.iris.Iris;
import crowplexus.hscript.Expr.Error as IrisError;
import crowplexus.hscript.Printer;
#end

#if cpp
@:headerCode('
#include <iostream>
#include <thread>
')
#end
class LoadingState extends MusicBeatState
{
	public static var loaded:Int = 0;
	public static var loadMax:Int = 0;

	// what the corner text shows: the last file handed to a worker, its size on disk,
	// and how many bytes have come back so far. Written by worker threads, read by update()
	public static var currentLabel:String = '';
	public static var currentBytes:Float = 0;
	public static var loadedBytes:Float = 0;
	public static var totalBytes:Float = 0;

	static var originalBitmapKeys:Map<String, String> = [];
	static var requestedBitmaps:Map<String, BitmapData> = [];
	static var mutex:Mutex;
	static var threadPool:FixedThreadPool = null;

	// Segmented loading: jobs sit in this queue and update() hands them to the pool
	// a few at a time. Empty (and unused) when the pref is off.
	static var loadQueue:Array<LoadingJob> = [];
	static var segmented:Bool = false;
	static var segmentActive:Int = 0;
	static final SEGMENT_FILES:Int = 3;
	static final SEGMENT_BYTES:Float = 24 * 1024 * 1024;

	function new(target:FlxState, stopMusic:Bool)
	{
		this.target = target;
		this.stopMusic = stopMusic;
		
		super();
	}

	inline static public function loadAndSwitchState(target:FlxState, stopMusic = false, intrusive:Bool = true)
		MusicBeatState.switchState(getNextState(target, stopMusic, intrusive));
	
	var target:FlxState = null;
	var stopMusic:Bool = false;
	var dontUpdate:Bool = false;

	var barGroup:FlxSpriteGroup;
	var bar:FlxSprite;
	var barWidth:Int = 0;
	var intendedPercent:Float = 0;
	var curPercent:Float = 0;
	var stateChangeDelay:Float = 0;

	// top-left readout: file being loaded right now, its size, files done, bytes done
	var detailText:FlxText;
	var detailCache:String = '';

	// "this is taking forever, what do you want to do" prompt
	static final STALL_SECONDS:Float = 30;
	var stallTimer:Float = 0;
	var stallPromptOpen:Bool = false;
	var stallSelected:Int = 0;
	var stallMembers:Array<flixel.FlxBasic> = [];
	var stallInfo:FlxText;
	var stallChoices:FlxText;
	var stallHint:FlxText;

	#if PSYCH_WATERMARKS
	var logo:FlxSprite;
	var pessy:FlxSprite;
	var loadingText:FlxText;

	var timePassed:Float;
	var shakeFl:Float;
	var shakeMult:Float = 0;
	
	var isSpinning:Bool = false;
	var spawnedPessy:Bool = false;
	var pressedTimes:Int = 0;
	#else
	var funkay:FlxSprite;
	#end

	#if HSCRIPT_ALLOWED
	var hscript:HScript;
	#end
	override function create()
	{
		persistentUpdate = true;
		barGroup = new FlxSpriteGroup();
		add(barGroup);

		var barBack:FlxSprite = new FlxSprite(0, 660).makeGraphic(1, 1, FlxColor.BLACK);
		barBack.scale.set(FlxG.width - 300, 25);
		barBack.updateHitbox();
		barBack.screenCenter(X);
		barGroup.add(barBack);

		bar = new FlxSprite(barBack.x + 5, barBack.y + 5).makeGraphic(1, 1, FlxColor.WHITE);
		bar.scale.set(0, 15);
		bar.updateHitbox();
		barGroup.add(bar);
		barWidth = Std.int(barBack.width - 10);

		#if HSCRIPT_ALLOWED
		if(Mods.currentModDirectory != null && Mods.currentModDirectory.trim().length > 0)
		{
			var scriptPath:String = 'mods/${Mods.currentModDirectory}/data/LoadingScreen.hx'; //mods/My-Mod/data/LoadingScreen.hx
			if(FileSystem.exists(scriptPath))
			{
				try
				{
					hscript = new HScript(null, scriptPath);
					hscript.set('getLoaded', function() return loaded);
					hscript.set('getLoadMax', function() return loadMax);
					hscript.set('barBack', barBack);
					hscript.set('bar', bar);
	
					if(hscript.exists('onCreate'))
					{
						hscript.call('onCreate');
						trace('initialized hscript interp successfully: $scriptPath');
						return super.create();
					}
					else
					{
						trace('"$scriptPath" contains no \"onCreate" function, stopping script.');
					}
				}
				catch(e:IrisError)
				{
					var pos:HScriptInfos = cast {fileName: scriptPath, showLine: false};
					Iris.error(Printer.errorToString(e, false), pos);
					var hscript:HScript = cast (Iris.instances.get(scriptPath), HScript);
				}
				if(hscript != null) hscript.destroy();
				hscript = null;
			}
		}
		#end

		// mods with their own LoadingScreen.hx took over above, they get the plain screen.
		// The FPS overlay also lives in this corner, so drop below it when it's showing
		var fpsShown:Bool = body.Main.fpsVar != null && body.Main.fpsVar.visible;
		detailText = new FlxText(8, fpsShown ? 78 : 4, FlxG.width - 16, '', 14);
		detailText.setFormat(Paths.font("vcr.ttf"), 14, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		detailText.borderSize = 1.6;
		detailText.scrollFactor.set();
		add(detailText);

		#if PSYCH_WATERMARKS // PSYCH LOADING SCREEN
		var bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.setGraphicSize(Std.int(FlxG.width));
		bg.color = 0xFFD16FFF;
		bg.updateHitbox();
		addBehindBar(bg);
	
		loadingText = new FlxText(520, 600, 400, Language.getPhrase('now_loading', 'Now Loading', ['...']), 32);
		loadingText.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, LEFT, OUTLINE_FAST, FlxColor.BLACK);
		loadingText.borderSize = 2;
		addBehindBar(loadingText);
	
		logo = new FlxSprite(0, 0).loadGraphic(Paths.image('loading_screen/icon'));
		logo.antialiasing = ClientPrefs.data.antialiasing;
		logo.scale.set(0.75, 0.75);
		logo.updateHitbox();
		logo.screenCenter();
		logo.x -= 50;
		logo.y -= 40;
		addBehindBar(logo);

		#else // BASE GAME LOADING SCREEN
		var bg = new FlxSprite().makeGraphic(1, 1, 0xFFCAFF4D);
		bg.scale.set(FlxG.width, FlxG.height);
		bg.updateHitbox();
		bg.screenCenter();
		addBehindBar(bg);

		funkay = new FlxSprite(0, 0).loadGraphic(Paths.image('funkay'));
		funkay.antialiasing = ClientPrefs.data.antialiasing;
		funkay.setGraphicSize(0, FlxG.height);
		funkay.updateHitbox();
		addBehindBar(funkay);
		#end
		super.create();

		buildStallPrompt();
		refreshDetails();

		if (stateChangeDelay <= 0 && checkLoaded())
		{
			dontUpdate = true;
			onLoad();
		}
	}

	function addBehindBar(obj:flixel.FlxBasic)
	{
		insert(members.indexOf(barGroup), obj);
	}

	inline function hasModLoadScreen():Bool
	{
		#if HSCRIPT_ALLOWED
		return hscript != null;
		#else
		return false;
		#end
	}

	static function byteText(bytes:Float):String
	{
		if (bytes >= 1048576) return (Std.int(bytes / 104857.6) / 10) + ' MB';
		if (bytes >= 1024) return Std.int(bytes / 1024) + ' KB';
		return Std.int(bytes) + ' B';
	}

	// rebuilt only when something actually changed, it's a per frame call otherwise
	function refreshDetails():Void
	{
		if (detailText == null) return;

		var filesPct:Int = loadMax > 0 ? Std.int(Math.min(1, loaded / loadMax) * 100) : 0;
		var text:String = 'Now loading: ' + (currentLabel.length > 0 ? currentLabel : 'starting up');
		text += '\nSize: ' + byteText(currentBytes) + '     Files: ' + loaded + ' / ' + loadMax + ' (' + filesPct + '%)';
		text += '\nTotal: ' + byteText(loadedBytes) + ' / ' + byteText(totalBytes);
		if (totalBytes > 0) text += ' (' + Std.int(Math.min(1, loadedBytes / totalBytes) * 100) + '%)';

		if (text != detailCache)
		{
			detailCache = text;
			detailText.text = text;
		}
	}

	static final STALL_LABELS:Array<String> = ['Continue Loading', 'Quit Game', 'Quit and Restart Game'];

	function buildStallPrompt():Void
	{
		var dim:FlxSprite = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		dim.scale.set(FlxG.width, FlxG.height);
		dim.updateHitbox();
		dim.screenCenter();
		dim.alpha = 0.85;
		stallAdd(dim);

		var box:FlxSprite = new FlxSprite().makeGraphic(1, 1, 0xFF141414);
		box.scale.set(780, 280);
		box.updateHitbox();
		box.screenCenter();
		stallAdd(box);

		stallInfo = new FlxText(box.x + 30, box.y + 24, 720, '', 18);
		stallInfo.setFormat(Paths.font('vcr.ttf'), 18, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		stallInfo.borderSize = 1.5;
		stallAdd(stallInfo);

		stallChoices = new FlxText(box.x + 40, box.y + 130, 700, '', 22);
		stallChoices.setFormat(Paths.font('vcr.ttf'), 22, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		stallChoices.borderSize = 1.5;
		stallAdd(stallChoices);

		stallHint = new FlxText(box.x + 30, box.y + box.height - 42, 720, 'UP / DOWN to pick, ACCEPT to confirm.', 16);
		stallHint.setFormat(Paths.font('vcr.ttf'), 16, 0xFFB0B0B0, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		stallHint.borderSize = 1.5;
		stallAdd(stallHint);
	}

	function stallAdd(obj:flixel.FlxBasic):Void
	{
		add(obj);
		stallMembers.push(obj);
		obj.visible = false;
	}

	function showStallPrompt():Void
	{
		if (stallPromptOpen || stallInfo == null) return;

		stallPromptOpen = true;
		stallSelected = 0;
		stallInfo.text = 'This screen has been loading for ' + Std.int(stallTimer) + ' seconds.\n'
			+ 'It may be stuck, or the mod is just very heavy.\n'
			+ 'Current file: ' + (currentLabel.length > 0 ? currentLabel : '-') + '\n'
			+ 'Files: ' + loaded + ' / ' + loadMax + '     ' + byteText(loadedBytes) + ' read';
		refreshStallChoices();
		for (obj in stallMembers) obj.visible = true;
	}

	function hideStallPrompt():Void
	{
		if (!stallPromptOpen) return;

		stallPromptOpen = false;
		stallTimer = 0;
		for (obj in stallMembers) obj.visible = false;
	}

	function changeStallSelection(change:Int):Void
	{
		stallSelected = FlxMath.wrap(stallSelected + change, 0, STALL_LABELS.length - 1);
		refreshStallChoices();
	}

	function refreshStallChoices():Void
	{
		var text:String = '';
		for (i in 0...STALL_LABELS.length)
			text += (i == stallSelected ? '> ' : '  ') + STALL_LABELS[i] + '\n';
		stallChoices.text = text;
	}

	function confirmStallSelection():Void
	{
		switch(stallSelected)
		{
			case 1:
				#if sys Sys.exit(0); #end
			case 2:
				restartGame();
			case 0:
				hideStallPrompt();
			default:
		}
	}

	// start a second copy and let this one die; whatever is half loaded is not coming back
	static function restartGame():Void
	{
		#if sys
		try
		{
			var exe:String = Sys.programPath();
			#if windows
			// Process launches the exe straight through CreateProcess, so no console window
			// pops up the way `cmd /c start` would. It also doesn't wait for it to quit.
			new sys.io.Process(exe, []);
			#else
			Sys.command('"' + exe + '"');
			#end
		}
		catch(e:Dynamic)
		{
			trace('could not restart the game: $e');
			lime.system.System.openFile(Sys.programPath());
		}
		Sys.exit(0);
		#end
	}

	var transitioning:Bool = false;
	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if (dontUpdate) return;

		// the prompt owns the input while it's up; if the load quietly finished behind it,
		// drop the prompt and let the normal path switch states
		if (stallPromptOpen)
		{
			if (checkLoaded()) hideStallPrompt();
			else
			{
				if (controls.UI_UP_P) changeStallSelection(-1);
				if (controls.UI_DOWN_P) changeStallSelection(1);
				if (controls.ACCEPT) confirmStallSelection();
				refreshDetails();
				return;
			}
		}

		// segmented loading hands out the next batch only after the last one is done
		if (!transitioning && !finishedLoading) dispatchSegment();

		if (!transitioning)
		{
			if (!finishedLoading && checkLoaded())
			{
				if(stateChangeDelay <= 0)
				{
					transitioning = true;
					onLoad();
					return;
				}
				else stateChangeDelay = Math.max(0, stateChangeDelay - elapsed);
			}
			intendedPercent = loaded / loadMax;
		}

		refreshDetails();
		if (!transitioning && !finishedLoading && !hasModLoadScreen())
		{
			stallTimer += elapsed;
			if (stallTimer >= STALL_SECONDS) showStallPrompt();
		}

		if (curPercent != intendedPercent)
		{
			if (Math.abs(curPercent - intendedPercent) < 0.001) curPercent = intendedPercent;
			else curPercent = FlxMath.lerp(intendedPercent, curPercent, Math.exp(-elapsed * 15));

			bar.scale.x = barWidth * curPercent;
			bar.updateHitbox();
		}
		
		#if HSCRIPT_ALLOWED
		if(hscript != null)
		{
			if(hscript.exists('onUpdate')) hscript.call('onUpdate', [elapsed]);
			return;
		}
		#end

		#if PSYCH_WATERMARKS // PSYCH LOADING SCREEN
		timePassed += elapsed;
		shakeFl += elapsed * 3000;
		var dots:String = '';
		switch(Math.floor(timePassed % 1 * 3))
		{
			case 0:
				dots = '.';
			case 1:
				dots = '..';
			case 2:
				dots = '...';
		}
		loadingText.text = Language.getPhrase('now_loading', 'Now Loading{1}', [dots]);

		if(!spawnedPessy)
		{
			if(!transitioning && controls.ACCEPT)
			{
				shakeMult = 1;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				pressedTimes++;
			}
			shakeMult = Math.max(0, shakeMult - elapsed * 5);
			logo.offset.x = Math.sin(shakeFl * Math.PI / 180) * shakeMult * 100;

			if(pressedTimes >= 5)
			{
				FlxG.camera.fade(0xAAFFFFFF, 0.5, true);
				logo.visible = false;
				spawnedPessy = true;
				stateChangeDelay = 5;
				FlxG.sound.play(Paths.sound('secret'));

				pessy = new FlxSprite(700, 140);
				pessy.frames = Paths.getSparrowAtlas('loading_screen/pessy');
				pessy.animation.addByPrefix('run', 'run', 24, true);
				pessy.animation.addByPrefix('spin', 'spin', 24, true);
				pessy.antialiasing = ClientPrefs.data.antialiasing;
				pessy.flipX = (logo.offset.x > 0);
				pessy.visible = false;

				new FlxTimer().start(0.01, function(tmr:FlxTimer) {
					pessy.x = FlxG.width + 200;
					pessy.velocity.x = -1100;
					if(pessy.flipX)
					{
						pessy.x = -pessy.width - 200;
						pessy.velocity.x *= -1;
					}
		
					pessy.visible = true;
					pessy.animation.play('run', true);
					#if ACHIEVEMENTS_ALLOWED Achievements.unlock('pessy_easter_egg'); #end
					
					insert(members.indexOf(loadingText), pessy);
				});
			}
		}
		else if(!isSpinning && (pessy.flipX && pessy.x > FlxG.width) || (!pessy.flipX && pessy.x < -pessy.width))
		{
			isSpinning = true;
			pessy.animation.play('spin', true);
			pessy.flipX = false;
			pessy.x = 500;
			pessy.y = FlxG.height + 500;
			pessy.velocity.x = 0;
			FlxTween.tween(pessy, {y: 10}, 0.65, {ease: FlxEase.quadOut});
		}
		#end
	}

	#if HSCRIPT_ALLOWED
	override function destroy()
	{
		if(hscript != null)
		{
			if(hscript.exists('onDestroy')) hscript.call('onDestroy');
			hscript.destroy();
		}
		hscript = null;
		super.destroy();
	}
	#end
	
	var finishedLoading:Bool = false;
	function onLoad()
	{
		_loaded();

		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();

		FlxG.camera.visible = false;
		MusicBeatState.switchState(target);
		transitioning = true;
		finishedLoading = true;
	}

	static function _loaded()
	{
		loaded = 0;
		loadMax = 0;
		initialThreadCompleted = true;
		isIntrusive = false;

		FlxTransitionableState.skipNextTransIn = true;
		if (threadPool != null) threadPool.shutdown(); // kill all workers safely
		threadPool = null;
		mutex = null;

		segmented = false;
		loadQueue = [];
		segmentActive = 0;
		currentLabel = '';
		currentBytes = 0;
		loadedBytes = 0;
		totalBytes = 0;
	}

	public static function checkLoaded():Bool
	{
		for (key => bitmap in requestedBitmaps)
		{
			if (bitmap != null && Paths.cacheBitmap(originalBitmapKeys.get(key), bitmap) != null) {} //trace('finished preloading image $key');
			else trace('failed to cache image $key');
		}
		requestedBitmaps.clear();
		originalBitmapKeys.clear();
		// trace('we checked if loaded');
		return (loaded >= loadMax && initialThreadCompleted);
	}

	public static function loadNextDirectory()
	{
		var directory:String = 'shared';
		var weekDir:String = StageData.forceNextDirectory;
		StageData.forceNextDirectory = null;

		if (weekDir != null && weekDir.length > 0 && weekDir != '') directory = weekDir;

		Paths.setCurrentLevel(directory);
		trace('Setting asset folder to ' + directory);
	}

	static var isIntrusive:Bool = false;
	static function getNextState(target:FlxState, stopMusic = false, intrusive:Bool = true):FlxState
	{
		#if !SHOW_LOADING_SCREEN
		intrusive = false;
		#end

		LoadingState.isIntrusive = intrusive;
		_startPool();
		loadNextDirectory();

		if(intrusive)
			return new LoadingState(target, stopMusic);
		
		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();

		while(true)
		{
			dispatchSegment(); // no-op unless the pref is on and a batch just finished
			if(checkLoaded())
			{
				_loaded();
				break;
			}
			else Sys.sleep(0.001);
		}
		return target;
	}

	static var imagesToPrepare:Array<String> = [];
	static var soundsToPrepare:Array<String> = [];
	static var musicToPrepare:Array<String> = [];
	static var songsToPrepare:Array<String> = [];
	public static function prepare(images:Array<String> = null, sounds:Array<String> = null, music:Array<String> = null)
	{
		if (images != null) imagesToPrepare = imagesToPrepare.concat(images);
		if (sounds != null) soundsToPrepare = soundsToPrepare.concat(sounds);
		if (music != null) musicToPrepare = musicToPrepare.concat(music);
	}

	static var initialThreadCompleted:Bool = true;
	static var dontPreloadDefaultVoices:Bool = false;
	static function _startPool()
	{
		#if MULTITHREADED_LOADING
		// Due to the Main thread and Discord thread, we decrease it by 2.
		var threadCount:Int = Std.int(Math.max(1, getCPUThreadsCount() - #if DISCORD_ALLOWED 2 #else 1 #end));
		#else
		var threadCount:Int = 1;
		#end
		threadPool = new FixedThreadPool(threadCount);
	}

	public static function prepareToSong()
	{
		if(PlayState.SONG == null)
		{
			imagesToPrepare = [];
			soundsToPrepare = [];
			musicToPrepare = [];
			songsToPrepare = [];
			loaded = 0;
			loadMax = 0;
			initialThreadCompleted = true;
			isIntrusive = false;
			return;
		}

		_startPool();
		imagesToPrepare = [];
		soundsToPrepare = [];
		musicToPrepare = [];
		songsToPrepare = [];

		initialThreadCompleted = false;
		var threadsCompleted:Int = 0;
		var threadsMax:Int = 0;
		function completedThread()
		{
			threadsCompleted++;
			if(threadsCompleted == threadsMax)
			{
				clearInvalids();
				// skip what the picker ruled out, so the threads never decode it.
				// same rule as Paths.image, so preload and runtime agree
				if (backend.LoadSkip.active)
					imagesToPrepare = imagesToPrepare.filter(function(k) return !Paths.skippedByPicker('images/$k.png'));
				startThreads();
				initialThreadCompleted = true;
			}
		}

		var song:SwagSong = PlayState.SONG;
		var folder:String = Paths.formatToSongPath(Song.loadedSongName);
		new Future<Bool>(() -> {
			// LOAD NOTE IMAGE
			var noteSkin:String = Note.defaultNoteSkin;
			if(PlayState.SONG.arrowSkin != null && PlayState.SONG.arrowSkin.length > 1) noteSkin = PlayState.SONG.arrowSkin;
			noteSkin = Note.resolveNoteSkin(noteSkin); // bare old chart name -> noteSkins/, else preload misses
	
			var customSkin:String = noteSkin + Note.getNoteSkinPostfix();
			if(Paths.fileExists('images/$customSkin.png', IMAGE)) noteSkin = customSkin;
			imagesToPrepare.push(noteSkin);
			//

			// LOAD NOTE SPLASH IMAGE
			var noteSplash:String = NoteSplash.defaultNoteSplash;
			if(PlayState.SONG.splashSkin != null && PlayState.SONG.splashSkin.length > 0) noteSplash = PlayState.SONG.splashSkin;
			else noteSplash += NoteSplash.getSplashSkinPostfix();
			imagesToPrepare.push(noteSplash);

			try
			{
				var path:String = Paths.json('$folder/preload');
				var json:Dynamic = null;

				#if MODS_ALLOWED
				var moddyFile:String = Paths.modsJson('$folder/preload');
				if (FileSystem.exists(moddyFile)) json = Json.parse(File.getContent(moddyFile));
				else json = Json.parse(File.getContent(path));
				#else
				json = Json.parse(Assets.getText(path));
				#end

				if(json != null)
				{
					var imgs:Array<String> = [];
					var snds:Array<String> = [];
					var mscs:Array<String> = [];
					for (asset in Reflect.fields(json))
					{
						var filters:Int = Reflect.field(json, asset);
						var asset:String = asset.trim();

						if(filters < 0 || StageData.validateVisibility(filters))
						{
							if(asset.startsWith('images/'))
								imgs.push(asset.substr('images/'.length));
							else if(asset.startsWith('sounds/'))
								snds.push(asset.substr('sounds/'.length));
							else if(asset.startsWith('music/'))
								mscs.push(asset.substr('music/'.length));
						}
					}
					prepare(imgs, snds, mscs);
				}
			}
			catch(e:Dynamic) {}
			return true;
		}, isIntrusive)
		.then((_) -> new Future<Bool>(() -> {
			if (song.stage == null || song.stage.length < 1)
				song.stage = StageData.vanillaSongStage(folder);

			var stageData:StageFile = StageData.getStageFile(song.stage);
			if (stageData != null)
			{
				var imgs:Array<String> = [];
				var snds:Array<String> = [];
				var mscs:Array<String> = [];
				if(stageData.preload != null)
				{
					for (asset in Reflect.fields(stageData.preload))
					{
						var filters:Int = Reflect.field(stageData.preload, asset);
						var asset:String = asset.trim();

						if(filters < 0 || StageData.validateVisibility(filters))
						{
							if(asset.startsWith('images/'))
								imgs.push(asset.substr('images/'.length));
							else if(asset.startsWith('sounds/'))
								snds.push(asset.substr('sounds/'.length));
							else if(asset.startsWith('music/'))
								mscs.push(asset.substr('music/'.length));
						}
					}
				}
				
				if (stageData.objects != null)
				{
					for (sprite in stageData.objects)
					{
						if(sprite.type == 'sprite' || sprite.type == 'animatedSprite')
							if((sprite.filters < 0 || StageData.validateVisibility(sprite.filters)) && !imgs.contains(sprite.image))
								imgs.push(sprite.image);
					}
				}
				prepare(imgs, snds, mscs);
			}

			songsToPrepare.push('$folder/Inst');

			var player1:String = song.player1;
			var player2:String = song.player2;
			var gfVersion:String = song.gfVersion;
			var prefixVocals:String = song.needsVoices ? '$folder/Voices' : null;
			if (gfVersion == null) gfVersion = 'gf';

			dontPreloadDefaultVoices = false;
			preloadCharacter(player1, prefixVocals);
			if (!dontPreloadDefaultVoices && prefixVocals != null)
			{
				if(Paths.fileExists('$prefixVocals-Player.${Paths.SOUND_EXT}', SOUND, false, 'songs') && Paths.fileExists('$prefixVocals-Opponent.${Paths.SOUND_EXT}', SOUND, false, 'songs'))
				{
					songsToPrepare.push('$prefixVocals-Player');
					songsToPrepare.push('$prefixVocals-Opponent');
				}
				else if(Paths.fileExists('$prefixVocals.${Paths.SOUND_EXT}', SOUND, false, 'songs'))
					songsToPrepare.push(prefixVocals);
			}

			if (player2 != player1)
			{
				threadsMax++;
				threadPool.run(() -> {
					try { preloadCharacter(player2, prefixVocals); } catch (e:Dynamic) {}
					completedThread();
				});
			}
			if (!stageData.hide_girlfriend && gfVersion != player2 && gfVersion != player1)
			{
				threadsMax++;
				threadPool.run(() -> {
					try { preloadCharacter(gfVersion); } catch (e:Dynamic) {}
					completedThread();
				});
			}

			if(threadsCompleted == threadsMax)
			{
				clearInvalids();
				startThreads();
				initialThreadCompleted = true;
			}
			return true;
		}, isIntrusive))
		.onError((err:Dynamic) -> {
			trace('ERROR! while preparing song: $err');
		});
	}

	public static function clearInvalids()
	{
		clearInvalidFrom(imagesToPrepare, 'images', '.png', IMAGE);
		clearInvalidFrom(soundsToPrepare, 'sounds', '.${Paths.SOUND_EXT}', SOUND);
		clearInvalidFrom(musicToPrepare, 'music',' .${Paths.SOUND_EXT}', SOUND);
		clearInvalidFrom(songsToPrepare, 'songs', '.${Paths.SOUND_EXT}', SOUND, 'songs');

		for (arr in [imagesToPrepare, soundsToPrepare, musicToPrepare, songsToPrepare])
			while (arr.contains(null))
				arr.remove(null);
	}

	static function clearInvalidFrom(arr:Array<String>, prefix:String, ext:String, type:AssetType, ?parentFolder:String = null)
	{
		for (folder in arr.copy())
		{
			var nam:String = folder.trim();
			if(nam.endsWith('/'))
			{
				for (subfolder in Mods.directoriesWithFile(Paths.getSharedPath(), '$prefix/$nam'))
				{
					for (file in FileSystem.readDirectory(subfolder))
					{
						if(file.endsWith(ext))
						{
							var toAdd:String = nam + haxe.io.Path.withoutExtension(file);
							if(!arr.contains(toAdd)) arr.push(toAdd);
						}
					}
				}

				//trace('Folder detected! ' + folder);
			}
		}

		var i:Int = 0;
		while(i < arr.length)
		{

			var member:String = arr[i];
			var myKey = '$prefix/$member$ext';
			if(parentFolder == 'songs') myKey = '$member$ext';

			//trace('attempting on $prefix: $myKey');
			var doTrace:Bool = false;
			if(member.endsWith('/') || (!Paths.fileExists(myKey, type, false, parentFolder) && (doTrace = true)))
			{
				arr.remove(member);
				if(doTrace) trace('Removed invalid $prefix: $member');
			}
			else i++;
		}
	}

	public static function startThreads()
	{
		mutex = new Mutex();
		loadMax = imagesToPrepare.length + soundsToPrepare.length + musicToPrepare.length
			+ (skipSongPreload() ? 0 : songsToPrepare.length);
		loaded = 0;

		//then start threads
		_threadFunc();
	}

	static function _threadFunc()
	{
		_startPool();
		segmented = ClientPrefs.data.segmentedLoading;
		loadQueue = [];
		segmentActive = 0;
		loadedBytes = 0;
		currentLabel = '';
		currentBytes = 0;

		// same order as ever: effects, then music, then the long song tracks, images last.
		// Sizes are read here once so the screen can show a real total; failed lookups count
		// as zero and the file gets dropped later anyway.
		for (sound in soundsToPrepare) queueSound('sounds/$sound', null);
		for (music in musicToPrepare) queueSound('music/$music', 'music');
		if (!skipSongPreload())
			for (song in songsToPrepare) queueSound(song, 'songs', null, true, false);

		// for images, they get to have their own thread
		for (image in imagesToPrepare) queueGraphic(image);

		totalBytes = 0;
		for (job in loadQueue) totalBytes += job.bytes;

		if (!segmented)
		{
			// the whole list goes to the pool at once, like it always did
			var jobs:Array<LoadingJob> = loadQueue;
			loadQueue = [];
			for (job in jobs) startJob(job);
		}
		else dispatchSegment();
	}

	// Segmented mode: hand out SEGMENT_FILES entries (or SEGMENT_BYTES worth of them) and
	// wait for those to finish before the next batch. Called from update(), and from the
	// blocking wait in getNextState() when the loading screen is skipped.
	public static function dispatchSegment():Void
	{
		if (!segmented || loadQueue.length == 0 || threadPool == null) return;

		var batch:Array<LoadingJob> = [];
		if (mutex != null) mutex.acquire();
		if (segmentActive == 0 && loadQueue.length > 0)
		{
			var bytes:Float = 0;
			while (loadQueue.length > 0 && batch.length < SEGMENT_FILES)
			{
				var job:LoadingJob = loadQueue[0];
				if (batch.length > 0 && bytes + job.bytes > SEGMENT_BYTES) break;

				loadQueue.shift();
				bytes += job.bytes;
				batch.push(job);
			}
			segmentActive += batch.length;
		}
		if (mutex != null) mutex.release();

		// handed to the pool outside the lock, the workers take it from here
		for (job in batch) startJob(job);
	}

	static function queueSound(key:String, parent:Null<String>, ?label:String = null, ?modsAllowed:Bool = true, ?beepOnNull:Bool = true):Void
	{
		if (label == null) label = key;
		var file:String = soundPath(key, parent, modsAllowed);
		loadQueue.push(new LoadingJob(label, fileSize(file), () -> preloadSound(key, parent, modsAllowed, beepOnNull)));
	}

	static function queueGraphic(key:String):Void
	{
		var file:String = Paths.getPath(graphicKey(key), IMAGE);
		loadQueue.push(new LoadingJob(graphicKey(key), fileSize(file), () -> preloadGraphic(key)));
	}

	static function fileSize(path:String):Float
	{
		#if sys
		try
		{
			if (FileSystem.exists(path)) return FileSystem.stat(path).size;
		}
		catch(e:Dynamic) {}
		#end
		return 0;
	}

	// Streaming reads the song tracks off disk while playing, so decoding them here would
	// just leave a second copy in memory. Viz stages still need the pcm, they keep the preload.
	static function skipSongPreload():Bool
		return ClientPrefs.data.streamAudio
			&& !PlayState.stageWantsAudioViz(PlayState.SONG != null ? PlayState.SONG.stage : null);

	static function startJob(job:LoadingJob):Void
	{
		#if debug
		var threadSchedule = Sys.time();
		#end
		threadPool.run(() -> {
			#if debug
			var threadStart = Sys.time();
			trace('${job.label} took ${threadStart - threadSchedule}s to start preloading');
			#end
			currentLabel = job.label;
			currentBytes = job.bytes;

			try {
				if (job.run() != null) {
					#if debug
					trace('finished preloading ${job.label} in ${Sys.time() - threadStart}s');
					#end
				} else trace('ERROR! fail on preloading ${job.label} ');
			}
			catch(e:Dynamic) {
				trace('ERROR! fail on preloading ${job.label}: $e');
			}

			// several jobs run at once, so the counters go through the same mutex the
			// loaders use. _loaded() nulls it out when the pool is torn down
			if (mutex != null)
			{
				mutex.acquire();
				loadedBytes += job.bytes;
				loaded++;
				if (segmentActive > 0) segmentActive--; // only counted up in segmented mode
				mutex.release();
			}
		});
	}

	inline private static function preloadCharacter(char:String, ?prefixVocals:String)
	{
		try
		{
			var path:String = Paths.getPath('characters/$char.json', TEXT);
			#if MODS_ALLOWED
			var character:Dynamic = Json.parse(File.getContent(path));
			#else
			var character:Dynamic = Json.parse(Assets.getText(path));
			#end

			var isAnimateAtlas:Bool = false;
			var img:String = character.image;
			img = img.trim();
			#if flxanimate
			var animToFind:String = Paths.getPath('images/$img/Animation.json', TEXT);
			if (#if MODS_ALLOWED FileSystem.exists(animToFind) || #end Assets.exists(animToFind))
				isAnimateAtlas = true;
			#end

			if(!isAnimateAtlas)
			{
				var split:Array<String> = img.split(',');
				for (file in split)
				{
					imagesToPrepare.push(file.trim());
				}
			}
			#if flxanimate
			else
			{
				for (i in 0...10)
				{
					var st:String = '$i';
					if(i == 0) st = '';
	
					if(Paths.fileExists('images/$img/spritemap$st.png', IMAGE))
					{
						//trace('found Sprite PNG');
						imagesToPrepare.push('$img/spritemap$st');
						break;
					}
				}
			}
			#end
	
			if (prefixVocals != null && character.vocals_file != null && character.vocals_file.length > 0)
			{
				songsToPrepare.push(prefixVocals + "-" + character.vocals_file);
				if(char == PlayState.SONG.player1) dontPreloadDefaultVoices = true;
			}
		}
		catch(e:haxe.Exception)
		{
			trace(e.details());
		}
	}

	static inline function soundPath(key:String, parent:Null<String>, ?modsAllowed:Bool = true):String
		return Paths.getPath(Language.getFileTranslation(key) + '.${Paths.SOUND_EXT}', SOUND, parent, modsAllowed);

	static inline function graphicKey(key:String):String
	{
		var requestKey:String = 'images/$key';
		#if TRANSLATIONS_ALLOWED requestKey = Language.getFileTranslation(requestKey); #end
		if(requestKey.lastIndexOf('.') < 0) requestKey += '.png';
		return requestKey;
	}

	// thread safe sound loader
	static function preloadSound(key:String, ?path:String, ?modsAllowed:Bool = true, ?beepOnNull:Bool = true):Null<Sound>
	{
		var file:String = soundPath(key, path, modsAllowed);

		//trace('precaching sound: $file');
		if(!Paths.currentTrackedSounds.exists(file))
		{
			if (#if sys FileSystem.exists(file) || #end OpenFlAssets.exists(file, SOUND))
			{
				var sound:Sound = #if sys Sound.fromFile(file) #else OpenFlAssets.getSound(file, false) #end;
				mutex.acquire();
				Paths.currentTrackedSounds.set(file, sound);
				mutex.release();
			}
			else if (beepOnNull)
			{
				trace('SOUND NOT FOUND: $key, PATH: $path');
				FlxG.log.error('SOUND NOT FOUND: $key, PATH: $path');
				return FlxAssets.getSound('flixel/sounds/beep');
			}
		}
		mutex.acquire();
		Paths.localTrackedAssets.push(file);
		mutex.release();

		return Paths.currentTrackedSounds.get(file);
	}

	// thread safe sound loader
	static function preloadGraphic(key:String):Null<BitmapData>
	{
		try {
			var requestKey:String = graphicKey(key);

			if (!Paths.currentTrackedAssets.exists(requestKey))
			{
				var file:String = Paths.getPath(requestKey, IMAGE);
				if (#if sys FileSystem.exists(file) || #end OpenFlAssets.exists(file, IMAGE))
				{
					#if sys
					var bitmap:BitmapData = BitmapData.fromFile(file);
					#else
					var bitmap:BitmapData = OpenFlAssets.getBitmapData(file, false);
					#end

					mutex.acquire();
					requestedBitmaps.set(file, bitmap);
					originalBitmapKeys.set(file, requestKey);
					mutex.release();
					return bitmap;
				}
				else trace('no such image $key exists');
			}

			return Paths.currentTrackedAssets.get(requestKey).bitmap;
		}
		catch(e:haxe.Exception)
		{
			trace('ERROR! fail on preloading image $key');
		}

		return null;
	}
	
	#if cpp
	@:functionCode('
		return std::thread::hardware_concurrency();
    	')
	@:noCompletion
    	public static function getCPUThreadsCount():Int
    	{
        	return -1;
    	}
    	#end
}

// one file waiting on the loading queue; the size is kept so the screen can show it
private class LoadingJob
{
	public var label:String;
	public var bytes:Float;
	public var run:Void->Dynamic;

	public function new(label:String, bytes:Float, run:Void->Dynamic)
	{
		this.label = label;
		this.bytes = bytes;
		this.run = run;
	}
}
