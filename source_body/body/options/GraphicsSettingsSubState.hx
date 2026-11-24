package options;

import backend.WindowSize;
import objects.Character;

class GraphicsSettingsSubState extends BaseOptionsMenu
{
	var antialiasingOption:Int;
	var boyfriend:Character = null;
	public function new()
	{
		title = Language.getPhrase('graphics_menu', 'Graphics Settings');
		rpcTitle = 'Graphics Settings Menu'; //for Discord Rich Presence

		boyfriend = new Character(840, 170, 'bf', true);
		boyfriend.setGraphicSize(Std.int(boyfriend.width * 0.75));
		boyfriend.updateHitbox();
		boyfriend.dance();
		boyfriend.animation.finishCallback = function (name:String) boyfriend.dance();
		boyfriend.visible = false;

		//I'd suggest using "Low Quality" as an example for making your own option since it is the simplest here
		var option:Option = new Option('Low Quality', //Name
			'If checked, disables some background details,\ndecreases loading times and improves performance.', //Description
			'lowQuality', //Save data variable name
			BOOL); //Variable type
		addOption(option);

		var option:Option = new Option('Anti-Aliasing',
			'If unchecked, disables anti-aliasing, increases performance\nat the cost of sharper visuals.',
			'antialiasing',
			BOOL);
		option.onChange = onChangeAntiAliasing; //Changing onChange is only needed if you want to make a special interaction after it changes the value
		addOption(option);
		antialiasingOption = optionsArray.length-1;

		var option:Option = new Option('Shaders', //Name
			"If unchecked, disables shaders.\nIt's used for some visual effects, and also CPU intensive for weaker PCs.", //Description
			'shaders',
			BOOL);
		addOption(option);

		var option:Option = new Option('GPU Caching', //Name
			"If checked, allows the GPU to be used for caching textures, decreasing RAM usage.\nDon't turn this on if you have a shitty Graphics Card.", //Description
			'cacheOnGPU',
			BOOL);
		addOption(option);

		var option:Option = new Option('Stream Audio',
			"If checked, song audio is read from disk while playing instead of\nbeing decoded into memory up front. Saves a lot of RAM.\nOnly affects the song tracks, not sound effects.",
			'streamAudio',
			BOOL);
		addOption(option);

		var option:Option = new Option('Segmented Loading',
			"If checked, files are loaded in small batches instead of all at once.\nMuch lower memory peak while loading, so heavy mods are less likely\nto run out of memory and crash. Loading takes a bit longer.",
			'segmentedLoading',
			BOOL);
		addOption(option);

		var option:Option = new Option('Clear Old Textures',
			"If checked, textures from the previous song are freed when a new\none starts. Saves a lot of RAM, but the next song loads a bit slower.",
			'clearOldAssets',
			BOOL);
		addOption(option);

		#if !html5 //Apparently other framerates isn't correctly supported on Browser? Probably it has some V-Sync shit enabled by default, idk
		var option:Option = new Option('Draw Framerate',
			"How many frames per second the game draws.\nLower values take load off the GPU while the game keeps running\nat the Upd. Framerate. Above that the extra frames just repeat.",
			'drawFramerate',
			INT);
		addOption(option);
		option.minValue = 10;
		option.maxValue = 240;
		option.displayFormat = '%v FPS';
		option.onChange = onChangeFramerate;

		var option:Option = new Option('Upd. Framerate',
			"How many times per second the game logic runs:\ninput, notes, scripts. 60 is the minimum, going lower\nmakes everything feel delayed.",
			'updateFramerate',
			INT);
		addOption(option);
		option.minValue = 60;
		option.maxValue = 240;
		option.displayFormat = '%v FPS';
		option.onChange = onChangeFramerate;

		var option:Option = new Option('Window Size',
			"How much of the screen the window takes, 10% to 100%.\n100% is as tall as your display, the game keeps its\n16:9 shape and stays centered while it resizes.",
			'windowScale',
			INT);
		addOption(option);
		option.minValue = 10;
		option.maxValue = 100;
		option.changeValue = 5;
		option.displayFormat = '%v%';
		option.onChange = onChangeWindowSize;
		#end

		super();
		insert(1, boyfriend);
	}

	function onChangeAntiAliasing()
	{
		for (sprite in members)
		{
			var sprite:FlxSprite = cast sprite;
			if(sprite != null && (sprite is FlxSprite) && !(sprite is FlxText)) {
				sprite.antialiasing = ClientPrefs.data.antialiasing;
			}
		}
	}

	function onChangeFramerate()
	{
		ClientPrefs.applyFramerate();
	}

	function onChangeWindowSize()
	{
		WindowSize.apply(ClientPrefs.data.windowScale);
	}

	override function changeSelection(change:Int = 0)
	{
		super.changeSelection(change);
		boyfriend.visible = (antialiasingOption == curSelected);
	}
}