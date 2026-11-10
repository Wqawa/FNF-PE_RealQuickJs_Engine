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

	// --- 按谱面文件的创建时间判断该用哪套 lane 语义 ---
	// Psych Engine 1.0.0 的正式发布时刻（GitHub tag "1.0"，2024-10-15 01:54:44 UTC），单位毫秒
	// 以方便直接和 Date.getTime() 比。比它早写出来的谱面基本都是按 0.6.x / 0.7.x 的相对 lane 画的。
	public static final PE_100_RELEASE:Float = 1728957284000.0;
	// 当前谱面文件的创建时间（拿不到就是 null，比如谱面被打包进 assets）
	public static var chartCreated:Null<Date> = null;
	// 这次版本判定是从哪来的：'manual' / 'file date' / 'chart format'，暂停界面右上角会显示
	public static var chartVersionSource:String = 'chart format';
	// getChart() 读到的文件时间，交给紧接着的那次 parseJSON 消费。
	// 用一次性中转而不是直接读 chartCreated，是为了让编辑器直接调 parseJSON 时不会拿到上一首歌的残留值。
	static var _pendingCreated:Null<Date> = null;

	public static function isLegacyChart():Bool
		return chartEngineVersion == 'Pe-0.7.3';

	// 时间够老还不够，谱面形状也得对得上：没有 {"song": {...}} 包裹层的谱面不可能早于 1.0 那次格式变更，
	// 这种文件的 lane 一定是绝对坐标，套 mustHitSection 只会把整首歌左右镜像。两者矛盾时按 format 走。
	static function isLegacyByFileDate(hasWrapper:Bool):Bool
	{
		if(!hasWrapper) return false;
		var c:Null<Date> = chartCreated;
		if(c == null) return false;
		return c.getTime() < PE_100_RELEASE;
	}

	// 读文件创建时间。拿不到就返回 null（走 format 判定），不影响载入。
	static function readFileCreated(path:String):Null<Date>
	{
		#if sys
		try
		{
			var stat = FileSystem.stat(path);
			#if windows
			return stat.ctime; // Windows 的 ctime 就是创建时间
			#else
			return stat.mtime; // 其他系统 ctime 是 inode 变更时间，mtime 更接近"这文件什么时候来的"
			#end
		}
		catch(e:haxe.Exception) {} // 权限 / 文件被删之类，当没有时间处理
		#end
		return null;
	}

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
		var onDisk:Bool = FileSystem.exists(_lastPath);
		if(onDisk)
			rawData = File.getContent(_lastPath);
		else
		#end
			rawData = Assets.getText(_lastPath);

		// events.json / picospeaker.json 是 sidecar，它们的时间不是这首歌谱面的时间，
		// 跟着记会把主谱面的判定冲掉。
		var isSidecarFile:Bool = (jsonInput == 'events' || jsonInput == 'picospeaker');
		if(!isSidecarFile)
		{
			#if MODS_ALLOWED
			chartCreated = onDisk ? readFileCreated(_lastPath) : null;
			#else
			chartCreated = null;
			#end
			_pendingCreated = (rawData != null) ? chartCreated : null;
		}

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

		// 只认 getChart() 刚读到的那个时间；编辑器直接调 parseJSON 时这里是 null，
		// 不会拿上一首歌的文件时间去判。
		var created:Null<Date> = _pendingCreated;
		_pendingCreated = null;

		// 手动切换（暂停菜单 Change Chart Ver）> 文件创建时间 > 谱面自身的 format
		var manual:String = forceEngineVersion;
		var legacyMode:Bool = (manual == 'Pe-0.7.3');
		if(manual == null && !isSidecar) legacyMode = isLegacyByFileDate(hasWrapper);

		if(!isSidecar)
		{
			chartCreated = created;
			detectedFormat = fmt.startsWith('psych_v1') ? 'Pe-1.0.x' : (hasWrapper ? 'Pe-0.7.3' : 'Pe-1.0.x');

			// Legacy charts get their lanes converted below, so in memory they are 1.0 semantics.
			chartEngineVersion = legacyMode ? 'Pe-0.7.3' : 'Pe-1.0.4';
			chartVersionSource = (manual != null) ? 'manual' : (created != null ? 'file date' : 'chart format');
			if(created != null && manual == null)
				trace('chart engine: $chartEngineVersion from file date $created ($nameForError)');
		}

		if(!legacyMode && convertTo != null && convertTo.length > 0)
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
		else if(legacyMode)
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

		// 老谱面（0.6.x 那批本体的）根本没有 stage 字段。以前这里一律填 'stage'，
		// 结果全部走 Week 1 的舞台：背景永远是 stageback，舞台事件（Philly Glow 之类）也没人接。
		// 这里按曲名反推（spookeez→spooky、pico→philly…），推断不到才落回 'stage'。
		// 注意必须在 StageData.loadDirectory 之前定下来，否则 forceNextDirectory 会是空的，
		// LoadingState 就不会把 currentLevel 切到对应的 week 目录，图还是会找不到。
		var stageField:String = cast Reflect.field(songJson, 'stage');
		if(stageField == null || stageField.length < 1)
		{
			var songName:String = cast Reflect.field(songJson, 'song');
			if(songName != null && songName.length > 0)
				Reflect.setField(songJson, 'stage', StageData.vanillaSongStage(Paths.formatToSongPath(songName)));
		}
		if(Reflect.field(songJson, 'format') == null) Reflect.setField(songJson, 'format', 'psych_v1_convert');
		if(Reflect.field(songJson, 'events') == null) Reflect.setField(songJson, 'events', []);
		if(Reflect.field(songJson, 'notes') == null) Reflect.setField(songJson, 'notes', []);
	}
}
