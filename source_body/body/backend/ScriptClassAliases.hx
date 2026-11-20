package backend;

#if HSCRIPT_ALLOWED
import crowplexus.iris.Iris;
#end

// Old 0.6.3 scripts use bare class names; map them back onto the packaged ones.
class ScriptClassAliases
{
	public static var initialized:Bool = false;

	static var table:Map<String, Dynamic> = new Map<String, Dynamic>();

	public static function init():Void
	{
		if(initialized) return;
		initialized = true;

		// ---------------------------------------------------------------- root
		// Scripts still write Main.fpsVar / new Main(). The process entry class owns the
		// bare name Main now, and it has no fpsVar, so point the name back at the game class.
		bind('Main', body.Main);

		// ---------------------------------------------------------------- backend
		bind('Achievements', backend.Achievements);
		bind('BaseStage', backend.BaseStage);
		bind('ClientPrefs', backend.ClientPrefs);
		bind('Conductor', backend.Conductor);
		bind('Controls', backend.Controls);
		bind('CoolUtil', backend.CoolUtil);
		bind('CustomFadeTransition', backend.CustomFadeTransition);
		bind('Difficulty', backend.Difficulty);
		bind('Highscore', backend.Highscore);
		bind('InputFormatter', backend.InputFormatter);
		bind('Language', backend.Language);
		bind('Mods', backend.Mods);
		bind('MusicBeatState', backend.MusicBeatState);
		bind('MusicBeatSubstate', backend.MusicBeatSubstate);
		bind('NoteTypesConfig', backend.NoteTypesConfig);
		bind('Paths', backend.Paths);
		bind('PsychCamera', backend.PsychCamera);
		bind('Rating', backend.Rating);
		bind('Song', backend.Song);
		bind('StageData', backend.StageData);
		bind('WeekData', backend.WeekData);

		#if DISCORD_ALLOWED
		bind('Discord', backend.DiscordClient);
		bind('DiscordClient', backend.DiscordClient);
		#end

		// ---------------------------------------------------------------- objects
		bind('AchievementPopup', objects.AchievementPopup);
		bind('Alphabet', objects.Alphabet);
		bind('AttachedSprite', objects.AttachedSprite);
		bind('AttachedText', objects.AttachedText);
		bind('Bar', objects.Bar);
		bind('BGSprite', objects.BGSprite);
		bind('Character', objects.Character);
		bind('CheckboxThingie', objects.CheckboxThingie);
		bind('HealthIcon', objects.HealthIcon);
		bind('MenuCharacter', objects.MenuCharacter);
		bind('MenuItem', objects.MenuItem);
		bind('MusicPlayer', objects.MusicPlayer);
		bind('Note', objects.Note);
		bind('NoteSplash', objects.NoteSplash);
		bind('StrumNote', objects.StrumNote);
		bind('TypedAlphabet', objects.TypedAlphabet);
		bind('VideoSprite', objects.VideoSprite);

		// 0.6.3 kept BF in his own class, 0.7 merged him into Character
		bind('Boyfriend', objects.Character);

		// attachment classes that dropped their Flx prefix in 1.0
		bind('AttachedFlxText', objects.AttachedText);

		// 0.6.3 had a separate text class; 1.0 uses FlxText, which makeLuaText returns
		bind('ModchartText', flixel.text.FlxText);

		// -------------------------------------------------------------- cutscenes
		bind('CutsceneHandler', cutscenes.CutsceneHandler);
		bind('DialogueBox', cutscenes.DialogueBox);
		bind('DialogueBoxPsych', cutscenes.DialogueBoxPsych);
		bind('DialogueCharacter', cutscenes.DialogueCharacter);

		// ---------------------------------------------------------------- options
		bind('BaseOptionsMenu', options.BaseOptionsMenu);
		bind('ControlsSubState', options.ControlsSubState);
		bind('GameplayChangersSubstate', options.GameplayChangersSubstate);
		bind('GameplaySettingsSubState', options.GameplaySettingsSubState);
		bind('GraphicsSettingsSubState', options.GraphicsSettingsSubState);
		bind('LanguageSubState', options.LanguageSubState);
		bind('ModSettingsSubState', options.ModSettingsSubState);
		bind('NoteOffsetState', options.NoteOffsetState);
		bind('NotesColorSubState', options.NotesColorSubState);
		bind('Option', options.Option);
		bind('OptionsState', options.OptionsState);
		bind('VisualsSettingsSubState', options.VisualsSettingsSubState);

		// 0.6.3 had a dedicated latency calibration state, 1.0 folded it into NoteOffsetState
		bind('LatencyState', options.NoteOffsetState);

		// ---------------------------------------------------------------- shaders
		bind('BlendModeEffect', shaders.BlendModeEffect);
		bind('ColorSwap', shaders.ColorSwap);
		bind('OverlayShader', shaders.OverlayShader);
		bind('RGBPalette', shaders.RGBPalette);
		bind('RainShader', shaders.RainShader);
		bind('WiggleEffect', shaders.WiggleEffect);

		// In 0.6.3 PhillyGlow.hx was a module name (the two classes below live in it),
		// so the bare name PhillyGlow was never a class. Do not map it back.

		// ----------------------------------------------------------------- states
		bind('AchievementsMenuState', states.AchievementsMenuState);
		bind('CreditsState', states.CreditsState);
		bind('ErrorState', states.ErrorState);
		bind('FlashingState', states.FlashingState);
		bind('FreeplayState', states.FreeplayState);
		bind('LoadingState', states.LoadingState);
		bind('MainMenuState', states.MainMenuState);
		bind('ModsMenuState', states.ModsMenuState);
		bind('PlayState', states.PlayState);
		bind('StoryMenuState', states.StoryMenuState);
		bind('TitleState', states.TitleState);

		// -------------------------------------------------------------- substates
		bind('GameOverSubstate', substates.GameOverSubstate);
		bind('OutdatedSubState', substates.OutdatedSubState);
		bind('PauseSubState', substates.PauseSubState);
		bind('ResetScoreSubState', substates.ResetScoreSubState);

		// 0.6.3 shipped a Gitaroo-Man style pause, 1.0 just uses the normal pause
		bind('GitarooPause', substates.PauseSubState);

		// Both names changed in 1.0: OutdatedState -> OutdatedSubState,
		// VisualsUISubState → VisualsSettingsSubState
		bind('OutdatedState', substates.OutdatedSubState);
		bind('VisualsUISubState', options.VisualsSettingsSubState);

		// ---------------------------------------------------------------- legacy module paths
		// 0.6.3 / 0.7.3 had stages/ and editors/ at the source root; 1.0 moved them under
		// states/. Old `import stages.Spooky;` / `import editors.ChartingState;` is redirected
		// here, same idea as NovaFlare's Iris.proxyImports mapping in InitScriptData.
		bind('stages.Spooky', states.stages.Spooky);
		bind('stages.School', states.stages.School);
		bind('stages.SchoolEvil', states.stages.SchoolEvil);
		bind('stages.Philly', states.stages.Philly);
		bind('stages.Limo', states.stages.Limo);
		bind('stages.Mall', states.stages.Mall);
		bind('stages.MallEvil', states.stages.MallEvil);
		bind('stages.Tank', states.stages.Tank);
		bind('stages.StageWeek1', states.stages.StageWeek1);
		bind('stages.Template', states.stages.Template);
		bind('stages.objects.TankmenBG', states.stages.objects.TankmenBG);
		bind('stages.objects.BackgroundDancer', states.stages.objects.BackgroundDancer);
		bind('stages.objects.BackgroundGirls', states.stages.objects.BackgroundGirls);
		bind('stages.objects.BackgroundTank', states.stages.objects.BackgroundTank);
		bind('stages.objects.DadBattleFog', states.stages.objects.DadBattleFog);
		bind('stages.objects.MallCrowd', states.stages.objects.MallCrowd);
		bind('stages.objects.PhillyGlowGradient', states.stages.objects.PhillyGlowGradient);
		bind('stages.objects.PhillyGlowParticle', states.stages.objects.PhillyGlowParticle);
		bind('stages.objects.PhillyTrain', states.stages.objects.PhillyTrain);
		// these were bare names in 0.6.3
		bind('TankmenBG', states.stages.objects.TankmenBG);
		bind('BackgroundDancer', states.stages.objects.BackgroundDancer);
		bind('BackgroundGirls', states.stages.objects.BackgroundGirls);

		bind('editors.ChartingState', states.editors.ChartingState);
		bind('editors.CharacterEditorState', states.editors.CharacterEditorState);
		bind('editors.DialogueCharacterEditorState', states.editors.DialogueCharacterEditorState);
		bind('editors.DialogueEditorState', states.editors.DialogueEditorState);
		bind('editors.EditorPlayState', states.editors.content.EditorPlayState);
		bind('editors.MasterEditorMenu', states.editors.MasterEditorMenu);
		bind('editors.MenuCharacterEditorState', states.editors.MenuCharacterEditorState);
		bind('editors.NoteSplashEditorState', states.editors.NoteSplashEditorState);
		bind('editors.WeekEditorState', states.editors.WeekEditorState);

		// 0.6.3 option substates now live under options/
		bind('substates.GameplayChangersSubstate', options.GameplayChangersSubstate);

		// Section was a class in 0.6.3; 1.0 only has the SwagSection typedef (shell in backend/Song.hx)
		bind('Section', backend.Section);
		// PhillyGlow's two sprites, bare names in 0.6.3
		bind('PhillyGlowParticle', states.stages.objects.PhillyGlowParticle);
		bind('PhillyGlowGradient', states.stages.objects.PhillyGlowGradient);

		// ---------------------------------------------------------------- editors
		bind('ChartingState', states.editors.ChartingState);
		bind('CharacterEditorState', states.editors.CharacterEditorState);
		bind('DialogueCharacterEditorState', states.editors.DialogueCharacterEditorState);
		bind('DialogueEditorState', states.editors.DialogueEditorState);
		bind('MasterEditorMenu', states.editors.MasterEditorMenu);
		bind('MenuCharacterEditorState', states.editors.MenuCharacterEditorState);
		bind('NoteSplashEditorState', states.editors.NoteSplashEditorState);
		bind('StageEditorState', states.editors.StageEditorState);
		bind('WeekEditorState', states.editors.WeekEditorState);

		// 0.6.3 ran .lua scripts from the chart editor through a separate EditorLua
		bind('EditorLua', psychlua.FunkinLua);

		// --------------------------------------------------------------- psychlua
		// these lived at the source root in 0.6.3, mods reach them via addHaxeLibrary()
		bind('FunkinLua', psychlua.FunkinLua);
		bind('LuaUtils', psychlua.LuaUtils);
		bind('CustomSubstate', psychlua.CustomSubstate);

		// ------------------------------------------------------------------ video
		// 1.0 replaced hxcodec with hxvlc; old mods' `import hxcodec.flixel.FlxVideo;`
		// and `import hxcodec.VideoHandler;` still resolve (implemented in source_body/body/hxcodec/)
		#if VIDEOS_ALLOWED
		bind('hxcodec.flixel.FlxVideo', hxcodec.flixel.FlxVideo);
		bind('hxcodec.VideoHandler', hxcodec.VideoHandler);
		bind('vlc.MP4Handler', vlc.MP4Handler);
		#end

		// in vanilla mode the whole table points at the original engine's classes
		if(Engine.isVanilla()) remapToVanilla();
		else sweepForeignImports();
	}

// proxyImports is global, first writer wins. Drop other-tree entries before ours go in.
	static function sweepForeignImports():Void
	{
		#if HSCRIPT_ALLOWED
		var stale:Array<String> = [];
		for (key in Iris.proxyImports.keys())
		{
			var fqn:String = Type.getClassName(Iris.proxyImports.get(key));
			if (fqn == null) continue;
			if (StringTools.startsWith(fqn, 'vanilla.') || StringTools.startsWith(fqn, 'pe063.')) stale.push(key);
		}
		for (key in stale)
			Iris.proxyImports.remove(key);
		#end
	}

	static function bind(name:String, cl:Dynamic):Void
	{
		if(cl == null) return;

		table.set(name, cl);
		#if HSCRIPT_ALLOWED
		Iris.proxyImports.set(name, cl);
		#end
	}

// vanilla mode: point the whole table at vanilla.* classes, FQNs included.
	static function remapToVanilla():Void
	{
		if(remapped) return;
		remapped = true;

		var pairs:Array<Array<Dynamic>> = [];
		for(name in table.keys()) pairs.push([name, table.get(name)]);

		for(pair in pairs)
		{
			var name:String = pair[0];
			var cl:Dynamic = pair[1];
			var fqn:String = Type.getClassName(cl);
			if(fqn == null) continue;

			var van:Dynamic = Type.resolveClass('vanilla.' + fqn);
			if(van == null) continue;

			table.set(name, van);
			#if HSCRIPT_ALLOWED
			Iris.proxyImports.set(name, van);
			Iris.proxyImports.set(fqn, van);
			#end
		}
	}

	static var remapped:Bool = false;

// No classes from another tree: their Paths point at the wrong assets.
	public static function isForeignTree(cl:Dynamic):Bool
	{
		if (cl == null) return false;
		var fqn:String = Type.getClassName(cl);
		if (fqn == null) return false;

		if (Engine.isVanilla())
			return isEngineClass(fqn) && !StringTools.startsWith(fqn, 'vanilla.');

		return StringTools.startsWith(fqn, 'vanilla.') || StringTools.startsWith(fqn, 'pe063.');
	}

	// other tree's engine class? shared list decides
	static function isEngineClass(fqn:String):Bool
	{
		return backend.ScriptConstants.isEngineClass(fqn);
	}

// Old bare names win, then fall through to the normal class lookup.
	public static function resolve(className:String):Dynamic
	{
		if(className == null || className.length < 1) return null;
		init();

		if(table.exists(className))
		{
			var bound:Dynamic = table.get(className);
			if(!isForeignTree(bound)) return bound;
		}

		// in vanilla mode scripts want the original engine's classes, not the body ones
		if(Engine.isVanilla() && !className.startsWith('vanilla.'))
		{
			var van:Dynamic = Type.resolveClass('vanilla.' + className);
			if(van != null) return van;
		}

		// Dotted names resolve directly; bare names are guessed over the package list.
		// (addHaxeLibrary / getPropertyFromClass come through here, so bare names must resolve)
		var cls:Dynamic = (className.indexOf('.') > -1) ? Type.resolveClass(className) : resolveDeep(className);
		return isForeignTree(cls) ? null : cls;
	}

// Scripts use class names as values too, so copy the table into their scope.
	public static function applyToHScript(interp:Dynamic):Void
	{
		init();
		for(name in table.keys())
		{
			if(name.indexOf('.') != -1) continue;
			interp.set(name, table.get(name));
		}
	}

	public static function exists(className:String):Bool
		return resolve(className) != null;

// Search order for bare names (getPropertyFromClass / addHaxeLibrary).
	// Some names are renamed, not guessed.
	static final SEARCH_PACKAGES:Array<String> = [
		'',
		'backend.',
		'backend.animation.',
		'backend.ui.',
		'objects.',
		'states.',
		'states.play.',
		'states.stages.',
		'states.stages.objects.',
		'states.editors.',
		'states.editors.content.',
		'substates.',
		'options.',
		'psychlua.',
		'shaders.',
		'cutscenes.',
		'flxanimate.',
		'mobile.',
		'debug.',
		'unused.',
		'hxcodec.',
		'vlc.'
	];

	// cache misses, don't scan the package list every time
	static var misses:Map<String, Bool> = new Map<String, Bool>();

	public static function resolveDeep(className:String):Dynamic
	{
		if(className == null || className.length == 0) return null;
		init();

		// explicit table first: renamed entries only exist there
		if(table.exists(className))
		{
			var bound:Dynamic = table.get(className);
			if(!isForeignTree(bound)) return bound;
		}

		if(misses.exists(className)) return null;

		// vanilla mode only accepts the vanilla. prefix: the body tree's classes must not
		// stand in, or their Paths pull assets from assets/body.
		var prefix:String = Engine.isVanilla() ? 'vanilla.' : '';

		for(pkg in SEARCH_PACKAGES)
		{
			var cl:Dynamic = Type.resolveClass(prefix + pkg + className);
			if(cl != null && !isForeignTree(cl)) return cl;
		}

		misses.set(className, true);
		return null;
	}

	// cleared on song change
	public static function resetMissCache():Void
		misses = new Map<String, Bool>();
}
