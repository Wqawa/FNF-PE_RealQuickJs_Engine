package backend;

import haxe.Json;
import lime.utils.Assets;

import objects.Note;

typedef SwagSong =
{
	var song:String;
	var notes:Array<SwagSection>;
	var events:Array<Dynamic>;
	var bpm:Float;
	var needsVoices:Bool;
	var speed:Float;
	var offset:Float;

	var player1:String;
	var player2:String;
	var gfVersion:String;
	var stage:String;
	var format:String;

	@:optional var gameOverChar:String;
	@:optional var gameOverSound:String;
	@:optional var gameOverLoop:String;
	@:optional var gameOverEnd:String;
	
	@:optional var disableNoteRGB:Bool;

	@:optional var arrowSkin:String;
	@:optional var splashSkin:String;
}

typedef SwagSection =
{
	var sectionNotes:Array<Dynamic>;
	var sectionBeats:Float;
	var mustHitSection:Bool;
	@:optional var altAnim:Bool;
	@:optional var gfSection:Bool;
	@:optional var bpm:Float;
	@:optional var changeBPM:Bool;
}

class Song
{
	public var song:String;
	public var notes:Array<SwagSection>;
	public var events:Array<Dynamic>;
	public var bpm:Float;
	public var needsVoices:Bool = true;
	public var arrowSkin:String;
	public var splashSkin:String;
	public var gameOverChar:String;
	public var gameOverSound:String;
	public var gameOverLoop:String;
	public var gameOverEnd:String;
	public var disableNoteRGB:Bool = false;
	public var speed:Float = 1;
	public var stage:String;
	public var player1:String = 'bf';
	public var player2:String = 'dad';
	public var gfVersion:String = 'gf';
	public var format:String = 'psych_v1';

	// --- Chart format compatibility (ported from NovaFlare) ---
	// detectedFormat: what the chart file on disk actually is.
	// chartEngineVersion: which lane semantics the chart currently in memory is interpreted with.
	// 'Pe-1.0.x' / 'Pe-1.0.4' -> absolute lanes (0..cols-1 = player, cols.. = opponent)
	// 'Pe-0.7.3' -> relative lanes + mustHitSection decides the side
	public static var detectedFormat:String = 'unknown';
	public static var chartEngineVersion:String = 'Pe-1.0.4';
	public static var forceEngineVersion:Null<String> = null;

	public static function isLegacyChart():Bool
		return chartEngineVersion == 'Pe-0.7.3';

	// Convert old charts to psych_v1 format.
	// convertLanes can be turned off to keep the original relative lanes on disk-shape,
	// PlayState then has to resolve the note side itself using Song.isLegacyChart().
	public static function convert(songJson:Dynamic, convertLanes:Bool = true) 
	{
		if(songJson.gfVersion == null)
		{
			songJson.gfVersion = songJson.player3;
			if(Reflect.hasField(songJson, 'player3')) Reflect.deleteField(songJson, 'player3');
		}

		if(songJson.events == null)
		{
			songJson.events = [];
			for (secNum in 0...songJson.notes.length)
			{
				var sec:SwagSection = songJson.notes[secNum];

				var i:Int = 0;
				var notes:Array<Dynamic> = sec.sectionNotes;
				var len:Int = notes.length;
				while(i < len)
				{
					var note:Array<Dynamic> = notes[i];
					if(note[1] < 0)
					{
						songJson.events.push([note[0], [[note[2], note[3], note[4]]]]);
						notes.remove(note);
						len = notes.length;
					}
					else i++;
				}
			}
		}

		var sectionsData:Array<SwagSection> = songJson.notes;
		if(sectionsData == null) return;

		for (section in sectionsData)
		{
			var beats:Null<Float> = cast section.sectionBeats;
			if (beats == null || Math.isNaN(beats))
			{
				section.sectionBeats = 4;
				if(Reflect.hasField(section, 'lengthInSteps')) Reflect.deleteField(section, 'lengthInSteps');
			}

			for (note in section.sectionNotes)
			{
				if(convertLanes)
				{
					var gottaHitNote:Bool = (note[1] < 4) ? section.mustHitSection : !section.mustHitSection;
					note[1] = (note[1] % 4) + (gottaHitNote ? 0 : 4);
				}

				if(!Std.isOfType(note[3], String))
					note[3] = Note.defaultNoteTypes[note[3]]; //compatibility with Week 7 and 0.1-0.3 psych charts
			}
		}
	}

	public static var chartPath:String;
	public static var loadedSongName:String;
	public static function loadFromJson(jsonInput:String, ?folder:String):SwagSong
	{
		if(folder == null) folder = jsonInput;
		PlayState.SONG = getChart(jsonInput, folder);
		loadedSongName = folder;
		chartPath = _lastPath;
		#if windows
		// prevent any saving errors by fixing the path on Windows (being the only OS to ever use backslashes instead of forward slashes for paths)
		chartPath = chartPath.replace('/', '\\');
		#end
		StageData.loadDirectory(PlayState.SONG);
		return PlayState.SONG;
	}

	static var _lastPath:String;
	public static function getChart(jsonInput:String, ?folder:String):SwagSong
	{
		if(folder == null) folder = jsonInput;
		var rawData:String = null;
		
		var formattedFolder:String = Paths.formatToSongPath(folder);
		var formattedSong:String = Paths.formatToSongPath(jsonInput);
		_lastPath = Paths.json('$formattedFolder/$formattedSong');

		#if MODS_ALLOWED
		if(FileSystem.exists(_lastPath))
			rawData = File.getContent(_lastPath);
		else
		#end
			rawData = Assets.getText(_lastPath);

		return rawData != null ? parseJSON(rawData, jsonInput) : null;
	}

	public static function parseJSON(rawData:String, ?nameForError:String = null, ?convertTo:String = 'psych_v1'):SwagSong
	{
		var parsedJson:Dynamic = Json.parse(rawData);
		var hasWrapper:Bool = Reflect.hasField(parsedJson, 'song');

		var songJson:SwagSong = cast parsedJson;
		if(hasWrapper)
		{
			var subSong:SwagSong = Reflect.field(parsedJson, 'song');
			if(subSong != null && Type.typeof(subSong) == TObject)
				songJson = subSong;
		}

		// Identify the chart format. `format` is not always trustworthy (old editors wrote
		// "psych_v1" even when the chart still had the {"song": {...}} wrapper), so the
		// wrapper itself is what decides legacy vs 1.0.
		var fmt:String = cast Reflect.field(songJson, 'format');
		if(fmt == null) fmt = 'unknown';

		// Sidecar files (events.json, picospeaker.json) must not overwrite the version we
		// detected for the real chart, otherwise a wrapped events file flips the whole song.
		var isSidecar:Bool = (nameForError == 'events' || nameForError == 'picospeaker');

		var forcedLegacy:Bool = (forceEngineVersion == 'Pe-0.7.3');
		if(!isSidecar)
		{
			detectedFormat = fmt.startsWith('psych_v1') ? 'Pe-1.0.x' : (hasWrapper ? 'Pe-0.7.3' : 'Pe-1.0.x');

			if(forcedLegacy)
				chartEngineVersion = 'Pe-0.7.3';
			else
				// Legacy charts get their lanes converted below, so in memory they are 1.0 semantics.
				chartEngineVersion = 'Pe-1.0.4';
		}

		if(!forcedLegacy && convertTo != null && convertTo.length > 0)
		{
			switch(convertTo)
			{
				case 'psych_v1':
					if(!fmt.startsWith('psych_v1')) //Convert to Psych 1.0 format
					{
						if(!isSidecar) trace('converting chart $nameForError with format $fmt to psych_v1 format...');
						Reflect.setField(songJson, 'format', 'psych_v1_convert');
						convert(songJson);
					}
			}
		}
		else if(forcedLegacy)
			convert(songJson, false); //still normalize fields, but keep the relative lanes

		fixMissingFields(songJson);
		return songJson;
	}

	// Fill in whatever an old chart may be missing. Older engines were a lot more forgiving
	// about absent fields, and a null bpm in particular turns every note into NaN.
	static function fixMissingFields(songJson:SwagSong)
	{
		if(songJson == null) return;

		var bpm:Null<Float> = cast Reflect.field(songJson, 'bpm');
		if(bpm == null || bpm <= 0) Reflect.setField(songJson, 'bpm', 120.0);

		var speed:Null<Float> = cast Reflect.field(songJson, 'speed');
		if(speed == null) Reflect.setField(songJson, 'speed', 1.0);

		if(Reflect.field(songJson, 'needsVoices') == null) Reflect.setField(songJson, 'needsVoices', true);
		if(Reflect.field(songJson, 'player1') == null) Reflect.setField(songJson, 'player1', 'bf');
		if(Reflect.field(songJson, 'player2') == null) Reflect.setField(songJson, 'player2', 'dad');
		if(Reflect.field(songJson, 'gfVersion') == null) Reflect.setField(songJson, 'gfVersion', 'gf');
		if(Reflect.field(songJson, 'stage') == null) Reflect.setField(songJson, 'stage', 'stage');
		if(Reflect.field(songJson, 'format') == null) Reflect.setField(songJson, 'format', 'psych_v1_convert');
		if(Reflect.field(songJson, 'events') == null) Reflect.setField(songJson, 'events', []);
		if(Reflect.field(songJson, 'notes') == null) Reflect.setField(songJson, 'notes', []);
	}
}
