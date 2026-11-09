package backend;

#if HSCRIPT_ALLOWED
import crowplexus.iris.Iris;
#end

/**
 * Psych 0.6.3 and older shipped a completely flat source tree, so every script written
 * back then uses bare class names:
 *
 *   import Boyfriend;
 *   getPropertyFromClass('ClientPrefs', 'downScroll')
 *   getPropertyFromClass('GitarooPause', 'instance')
 *
 * From 0.7 on those classes live in packages (objects.Character, backend.ClientPrefs, ...),
 * which makes every one of those calls fail. This table puts the old names back and is
 * consumed by two places: HScript looks them up through Iris.proxyImports, the Lua
 * reflection API goes through resolve() below.
 */
class ScriptClassAliases
{
	public static var initialized:Bool = false;

	static var table:Map<String, Dynamic> = new Map<String, Dynamic>();

	public static function init():Void
	{
		if(initialized) return;
		initialized = true;

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

		// 名字带 Flx 前缀的那几个附件类，1.0 去掉了前缀
		bind('AttachedFlxText', objects.AttachedText);

		// 0.6.3 的 lua 文本是独立类，1.0 直接用 FlxText（makeLuaText 返回的就是它）
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

		// PhillyGlow 在 0.6.3 的 PhillyGlow.hx 里只是模块名（下面那两个类在它里面），
		// 裸名 PhillyGlow 从来不是类，别给它挂映射——之前错挂 BlendModeEffect 的那条已删。

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

		// 0.6.3 的这两个名字在 1.0 都改了：OutdatedState → OutdatedSubState，
		// VisualsUISubState → VisualsSettingsSubState
		bind('OutdatedState', substates.OutdatedSubState);
		bind('VisualsUISubState', options.VisualsSettingsSubState);

		// ---------------------------------------------------------------- 老模块路径
		// 0.6.3 / 0.7.3 的 stages/、editors/ 是源码根目录下的包，1.0 挪进了 states/。
		// 老 HScript 里的 `import stages.Spooky;`、`import editors.ChartingState;` 靠这些接回来。
		// 等价于 NovaFlare 的 InitScriptData 里那套 Iris.proxyImports 路径映射。
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
		// 这几个 0.6.3 是裸名
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

		// 0.6.3 的选项子状态现在在 options/ 下
		bind('substates.GameplayChangersSubstate', options.GameplayChangersSubstate);

		// 0.6.3 的 Section 是个独立类，1.0 只剩 SwagSection typedef（壳子在 backend/Song.hx 里）
		bind('Section', backend.Section);
		// PhillyGlow 的两个 sprite，0.6.3 是裸名
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
		// 1.0 把 hxcodec 换成了 hxvlc，老 mod 里 `import hxcodec.flixel.FlxVideo;`
		// 和 `import hxcodec.VideoHandler;` 都还能解析（实现在 source/hxcodec/）
		#if VIDEOS_ALLOWED
		bind('hxcodec.flixel.FlxVideo', hxcodec.flixel.FlxVideo);
		bind('hxcodec.VideoHandler', hxcodec.VideoHandler);
		bind('vlc.MP4Handler', vlc.MP4Handler);
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

	/**
	 * Resolve a class by name. Old bare names win, everything else falls through to the
	 * normal haxe class lookup so modern scripts keep working.
	 */
	public static function resolve(className:String):Dynamic
	{
		if(className == null || className.length < 1) return null;
		init();

		if(table.exists(className)) return table.get(className);
		return Type.resolveClass(className);
	}

	/**
	 * 把整张表倒进 HScript 的变量表。
	 * `import` 只能让类型引用生效，但 0.6.x 的脚本还会把类名当值用
	 * （`Type.getClassName(Boyfriend)`、`GitarooPause.instance`），那种得是变量。
	 *
	 * 带点的 key（`stages.Spooky` 这种）是模块路径，hscript 里按字段路径表达式解析，
	 * 根本不会来查变量表，倒进去也取不出来，跳过。
	 */
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
}
