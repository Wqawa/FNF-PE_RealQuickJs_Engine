package backend;

import flixel.FlxG;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import openfl.display.BitmapData;

// What the "load options" picker decided for this run. Scoped to one visit to a song:
// choosing a difficulty, opening settings and coming back all keep the same choice, and
// only going back to freeplay / story throws it away.
//
// Skipped atlases still get their frame definitions, only the texture is a 1x1 red pixel -
// so a character keeps its exact bounds and just draws as a red box, for one pixel of
// memory. Skipped single images do get a full-size red bitmap, because their size lives in
// the texture itself and losing it would break every placement that reads width / height.
class LoadSkip
{
	public static inline var CAT_STAGE:String = 'stage';
	public static inline var CAT_CHARS:String = 'chars';
	public static inline var CAT_NOTES:String = 'notes';
	public static inline var CAT_SPLASH:String = 'splash';
	public static inline var CAT_UI:String = 'ui';
	public static inline var CAT_OTHER:String = 'other';

	public static var CATS:Array<String> = [CAT_STAGE, CAT_CHARS, CAT_NOTES, CAT_SPLASH, CAT_UI, CAT_OTHER];

	public static var CAT_LABELS:Map<String, String> = [
		CAT_STAGE => 'Stage',
		CAT_CHARS => 'Characters',
		CAT_NOTES => 'Arrows / notes',
		CAT_SPLASH => 'Note splashes',
		CAT_UI 	  => 'UI / icons / bars',
		CAT_OTHER => 'Other images'
	];

	// 'song|difficulty|mod' of the song the picker has already been shown for.
	public static var askedKey:String = null;

	// Categories to skip this run (only meaningful while active).
	public static var skipped:Map<String, Bool> = new Map();

	// Script paths to skip this run.
	public static var skippedScripts:Map<String, Bool> = new Map();

	// False means "no picker this run", which is the normal case: nothing is skipped.
	public static var active:Bool = false;

	static var placeholderGraphic:FlxGraphic = null;
	static var placeholderAtlasCache:Map<String, FlxAtlasFrames> = new Map();

	public static function reset():Void
	{
		active = false;
		skipped = new Map();
		skippedScripts = new Map();
	}

	/** Called when leaving the song menus, so the next visit asks again. */
	public static function forgetSong():Void
	{
		askedKey = null;
		reset();
	}

	// Difficulty is deliberately not part of the key: changing it from the pause menu is the
	// same visit to the song, so the answer from a moment ago still applies.
	public static function songKey(song:String, difficulty:String):String
	{
		var mod:String = (Mods.currentModDirectory == null) ? '' : Mods.currentModDirectory;
		return '$song|$mod';
	}

	public static function needsAsk(song:String, difficulty:String):Bool
	{
		// one answer per visit to a song. Base game songs get asked too - their list is just
		// empty on both columns, and pressing enter is the whole interaction.
		var key:String = songKey(song, difficulty);
		return askedKey != key;
	}

	/** Category an image key belongs to. Keys come in as the short form Paths takes. */
	public static function catOf(key:String):String
	{
		if (key == null) return CAT_OTHER;
		var k:String = key.toLowerCase();

		if (k.indexOf('characters/') >= 0) return CAT_CHARS;
		if (k.indexOf('noteskins/') >= 0 || k.indexOf('note_assets') >= 0) return CAT_NOTES;
		if (k.indexOf('notesplash') >= 0 || k.indexOf('splashes/') >= 0) return CAT_SPLASH;
		if (k.indexOf('stages/') >= 0 || k.indexOf('stage/') >= 0) return CAT_STAGE;
		if (k.indexOf('ui/') >= 0 || k.indexOf('icons/') >= 0 || k.indexOf('healthbar') >= 0
			|| k.indexOf('icon-') >= 0 || k.indexOf('timebar') >= 0) return CAT_UI;

		return CAT_OTHER;
	}

	public static function skipImage(key:String):Bool
	{
		if (!active || key == null) return false;
		return skipped.exists(catOf(key));
	}

	public static function skipScript(path:String):Bool
	{
		if (!active || path == null) return false;
		if (skippedScripts.exists(path)) return true;

		// also match on the file name alone: the engine hands over full paths
		var cut:Int = path.lastIndexOf('/');
		if (cut >= 0 && skippedScripts.exists(path.substr(cut + 1))) return true;
		return false;
	}

	// One transparent pixel for everything that was skipped.
	//
	// Deliberately NOT registered in FlxG.bitmap: Paths.clearStoredMemory() walks that cache
	// and destroys anything with useCount 0, which left this static field pointing at a dead
	// graphic. Every sprite built from it then had a null bitmap - the Null Object Reference
	// that only showed up once enough categories were skipped.
	public static function placeholder():FlxGraphic
	{
		if (placeholderGraphic != null && placeholderGraphic.bitmap != null) return placeholderGraphic;

		placeholderGraphic = FlxGraphic.fromBitmapData(new BitmapData(1, 1, true, 0x00000000), false, 'loadskip_transparent', false);
		placeholderGraphic.persist = true;
		return placeholderGraphic;
	}

	// Frame rects come straight from the atlas text, so bounds stay correct; the texture
	// behind them is a single transparent pixel and every uv lands inside it.
	public static inline var KIND_SPARROW:String = 'sparrow';
	public static inline var KIND_PACKER:String = 'packer';
	public static inline var KIND_JSON:String = 'json';

	public static function placeholderAtlas(text:String, key:String, kind:String = KIND_SPARROW):FlxAtlasFrames
	{
		if (text == null) return null;

		var cacheKey:String = kind + '|' + key;
		var cached:FlxAtlasFrames = placeholderAtlasCache.get(cacheKey);
		if (cached != null && cached.parent != null && cached.parent.bitmap != null) return cached;

		var graphic:FlxGraphic = placeholder();
		var frames:FlxAtlasFrames = null;
		switch (kind)
		{
			case 'packer':
				frames = FlxAtlasFrames.fromSpriteSheetPacker(graphic, text);
			case 'json':
				frames = FlxAtlasFrames.fromTexturePackerJson(graphic, text);
			default:
				frames = FlxAtlasFrames.fromSparrow(graphic, text);
		}
		if (frames != null) placeholderAtlasCache.set(cacheKey, frames);
		return frames;
	}

	/** Runs fn with skipping temporarily off, so a fallback can load for real. */
	public static function withSkipDisabled<T>(fn:Void->T):T
	{
		var wasActive:Bool = active;
		active = false;
		var out:T = null;
		try
		{
			out = fn();
		}
		catch (e:Dynamic) {}
		active = wasActive;
		return out;
	}

	// Preview only: what a category would actually cover. Scanned from disk because the
	// engine has not resolved stage / character keys yet at picker time.
	static var imageIndex:Map<String, Array<String>> = null;

	public static function listImages(cat:String):Array<String>
	{
		buildImageIndex();
		var out:Array<String> = imageIndex.get(cat);
		return (out == null) ? [] : out;
	}

	public static function buildImageIndex():Void
	{
		if (imageIndex != null) return;
		imageIndex = new Map();

		#if sys
		var root:String = modRoot() + 'images';
		walkImages(root, '');
		#end
	}

	/** The mod this song belongs to, as a path ending in a slash. */
	static function modRoot():String
	{
		var d:String = Mods.currentModDirectory;
		if (d == null || d.length < 1) return Paths.mods('');
		return Paths.mods(d + '/');
	}

	static function walkImages(dir:String, rel:String):Void
	{
		#if sys
		try
		{
			if (!sys.FileSystem.exists(dir)) return;
			for (name in sys.FileSystem.readDirectory(dir))
			{
				var full:String = dir + '/' + name;
				var key:String = (rel.length > 0) ? rel + '/' + name : name;

				if (sys.FileSystem.isDirectory(full))
				{
					walkImages(full, key);
					continue;
				}

				if (!name.toLowerCase().endsWith('.png')) continue;
				var cat:String = catOf('images/' + key);
				var list:Array<String> = imageIndex.get(cat);
				if (list == null) { list = []; imageIndex.set(cat, list); }
				list.push(key);
			}
		}
		catch (e:Dynamic) {}
		#end
	}

	// The folders PlayState actually reads scripts from, one group each. The enumeration is
	// the same call the engine makes, so every path listed here is a path skipScript gets
	// handed later - no guessing from the tree, and no rows for files that never load.
	public static function listScripts(song:String):Array<{path:String, label:String, group:String}>
	{
		var out:Array<{path:String, label:String, group:String}> = [];
		#if sys
		var songPath:String = Paths.formatToSongPath(song);
		addFromDirectories(out, 'scripts/', 'Scripts');
		addFromDirectories(out, 'custom_events/', 'Events');
		addFromDirectories(out, 'custom_notetypes/', 'Notetypes');
		addFromDirectories(out, 'stages/', 'Stage');
		addFromDirectories(out, 'data/$songPath/', 'Song data');

		out.sort(function(a, b)
		{
			if (a.group != b.group) return (a.group < b.group) ? -1 : 1;
			return (a.label < b.label) ? -1 : ((a.label > b.label) ? 1 : 0);
		});
		#end
		return out;
	}

	#if sys
	// Flat read, exactly like PlayState does it - it never recurses into subfolders either,
	// so listing those would only offer rows that never get loaded.
	static function addFromDirectories(out:Array<{path:String, label:String, group:String}>, sub:String, group:String):Void
	{
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), sub))
		{
			// engine / base game folders are not the user's to skip
			if (folder.indexOf('mods/') < 0) continue;

			var names:Array<String> = null;
			try
			{
				if (!sys.FileSystem.exists(folder) || !sys.FileSystem.isDirectory(folder)) continue;
				names = sys.FileSystem.readDirectory(folder);
			}
			catch (e:Dynamic) continue;

			if (names == null) continue;
			for (name in names)
			{
				if (!isScriptName(name)) continue;
				var path:String = folder + name;
				if (hasEntry(out, path)) continue;
				out.push({path: path, label: name, group: group});
			}
		}
	}

	static function hasEntry(out:Array<{path:String, label:String, group:String}>, path:String):Bool
	{
		for (e in out) if (e.path == path) return true;
		return false;
	}

	static function isScriptName(name:String):Bool
	{
		var low:String = name.toLowerCase();
		return low.endsWith('.lua') || low.endsWith('.hx') || low.endsWith('.js');
	}
	#end
}
