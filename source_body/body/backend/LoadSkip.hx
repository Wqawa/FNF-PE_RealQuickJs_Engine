package backend;

import flixel.FlxG;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import openfl.display.BitmapData;

// What the load picker decided for this song visit. Changing difficulty or opening a
// substate keeps the answer; going back to freeplay / story clears it.
// Skipped art keeps its frame rects but draws as one transparent pixel, so bounds stay put.
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
		CAT_UI => 'UI / icons / bars',
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

	// called when leaving the song menus, so the next visit asks again
	public static function forgetSong():Void
	{
		askedKey = null;
		imageIndex = null; // the next song can be from another mod, rescan its images
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
		// one answer per song visit. base game songs get asked too, with empty lists
		var key:String = songKey(song, difficulty);
		return askedKey != key;
	}

	// category for a short image key, the form Paths uses
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

		// the engine's path and the picker's path can differ, so match the bare name too
		var cut:Int = path.lastIndexOf('/');
		if (cut >= 0 && skippedScripts.exists(path.substr(cut + 1))) return true;
		return false;
	}

	// one transparent pixel shared by everything that was skipped.
	// not in FlxG.bitmap: clearStoredMemory() destroys unused cached graphics and left this
	// static field pointing at a dead one.
	public static function placeholder():FlxGraphic
	{
		if (placeholderGraphic != null && placeholderGraphic.bitmap != null) return placeholderGraphic;

		placeholderGraphic = FlxGraphic.fromBitmapData(new BitmapData(1, 1, true, 0x00000000), false, 'loadskip_transparent', false);
		placeholderGraphic.persist = true;
		return placeholderGraphic;
	}

	// frame rects come from the atlas text, so bounds stay correct on a 1x1 texture
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

	// run fn with skipping off, so a fallback can load for real
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

	// preview rows for a category. scanned from disk: the engine has no stage / character
	// keys resolved yet at picker time
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

	// mod folder for this song, with a trailing slash
	static function modRoot():String
	{
		var d:String = Mods.currentModDirectory;
		if (d == null || d.length < 1) return Paths.mods('');
		return Paths.mods(d + '/');
	}

	static function walkImages(dir:String, rel:String):Void
	{
		#if sys
		var names:Array<String> = null;
		try
		{
			if (!sys.FileSystem.exists(dir)) return;
			names = sys.FileSystem.readDirectory(dir);
		}
		catch (e:Dynamic) return;

		if (names == null) return;
		for (name in names)
		{
			var full:String = dir + '/' + name;
			var key:String = (rel.length > 0) ? rel + '/' + name : name;

			var isDir:Bool = false;
			try
			{
				isDir = sys.FileSystem.isDirectory(full);
			}
			catch (e:Dynamic) {}
			if (isDir)
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
		#end
	}

	// same folders PlayState reads, grouped. paths here are the ones skipScript gets later
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
	// flat read, same as PlayState: subfolders never load, so don't list them
	static function addFromDirectories(out:Array<{path:String, label:String, group:String}>, sub:String, group:String):Void
	{
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), sub))
		{
			// engine / base folders are not ours to skip
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
