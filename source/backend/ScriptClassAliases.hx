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

		// PhillyGlow used to be its own shader-ish sprite, 1.0 does it with BlendModeEffect
		bind('PhillyGlow', shaders.BlendModeEffect);

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

	public static function exists(className:String):Bool
		return resolve(className) != null;
}
