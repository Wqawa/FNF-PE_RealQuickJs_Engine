package backend;

import flixel.graphics.frames.FlxFrame.FlxFrameAngle;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.FlxGraphic;
import flixel.math.FlxRect;
import flixel.system.FlxAssets;

import openfl.display.BitmapData;
import openfl.display3D.textures.RectangleTexture;
import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;
import openfl.system.System;
import openfl.geom.Rectangle;

import lime.utils.Assets;
import flash.media.Sound;

import haxe.Json;


#if MODS_ALLOWED
import backend.Mods;
#end

@:access(openfl.display.BitmapData)
class Paths
{
	inline public static var SOUND_EXT = #if web "mp3" #else "ogg" #end;
	inline public static var VIDEO_EXT = "mp4";

	public static function excludeAsset(key:String) {
		if (!dumpExclusions.contains(key))
			dumpExclusions.push(key);
	}

	// assets/<VERSION_DIR> and mods/<VERSION_DIR>, one dir per tree

	public static var VERSION_DIR:String = 'body';

	public static var dumpExclusions:Array<String> = ['assets/$VERSION_DIR/shared/music/freakyMenu.$SOUND_EXT'];
	// haya I love you for the base cache dump I took to the max
	public static function clearUnusedMemory()
	{
		// clear non local assets in the tracked assets list
		for (key in currentTrackedAssets.keys())
		{
			// if it is not currently contained within the used local assets
			if (!localTrackedAssets.contains(key) && !dumpExclusions.contains(key))
			{
				destroyGraphic(currentTrackedAssets.get(key)); // get rid of the graphic
				currentTrackedAssets.remove(key); // and remove the key from local cache map
			}
		}

		// run the garbage collector for good measure lmfao
		System.gc();
	}

	// define the locally tracked assets
	public static var localTrackedAssets:Array<String> = [];

	@:access(flixel.system.frontEnds.BitmapFrontEnd._cache)
	public static function clearStoredMemory()
	{
		// clear anything not in the tracked assets list
		for (key in FlxG.bitmap._cache.keys())
		{
			if (!currentTrackedAssets.exists(key))
				destroyGraphic(FlxG.bitmap.get(key));
		}

		// clear all sounds that are cached
		for (key => asset in currentTrackedSounds)
		{
			if (!localTrackedAssets.contains(key) && !dumpExclusions.contains(key) && asset != null)
			{
				Assets.cache.clear(key);
				currentTrackedSounds.remove(key);
			}
		}
		// flags everything to be cleared out next unused memory clear
		localTrackedAssets = [];
		#if !html5 openfl.Assets.cache.clear("songs"); #end
	}

	// drop the last song's sounds too. clearStoredMemory checks localTrackedAssets, which
	// still holds the old keys at that point, so those sounds never get removed
	public static function clearOldSounds()
	{
		for (key => asset in currentTrackedSounds)
		{
			if (dumpExclusions.contains(key) || asset == null) continue;
			Assets.cache.clear(key);
			currentTrackedSounds.remove(key);
		}
	}

	public static function freeGraphicsFromMemory()
	{
		var protectedGfx:Array<FlxGraphic> = [];
		function checkForGraphics(spr:Dynamic)
		{
			try
			{
				var grp:Array<Dynamic> = Reflect.getProperty(spr, 'members');
				if(grp != null)
				{
					//trace('is actually a group');
					for (member in grp)
					{
						checkForGraphics(member);
					}
					return;
				}
			}

			//trace('check...');
			try
			{
				var gfx:FlxGraphic = Reflect.getProperty(spr, 'graphic');
				if(gfx != null)
				{
					protectedGfx.push(gfx);
					//trace('gfx added to the list successfully!');
				}
			}
			//catch(haxe.Exception) {}
		}

		for (member in FlxG.state.members)
			checkForGraphics(member);

		if(FlxG.state.subState != null)
			for (member in FlxG.state.subState.members)
				checkForGraphics(member);

		for (key in currentTrackedAssets.keys())
		{
			// if it is not currently contained within the used local assets
			if (!dumpExclusions.contains(key))
			{
				var graphic:FlxGraphic = currentTrackedAssets.get(key);
				if(!protectedGfx.contains(graphic))
				{
					destroyGraphic(graphic); // get rid of the graphic
					currentTrackedAssets.remove(key); // and remove the key from local cache map
					//trace('deleted $key');
				}
			}
		}

		// that only drops the BitmapData, the objects stay on the heap until gc runs
		System.gc();
	}

	// set when a graphic is freed. atlas caches clear themselves before reuse, otherwise
	// a frame keeps pointing at a dead texture and draws black
	public static var graphicsDirty:Bool = false;

	inline static function destroyGraphic(graphic:FlxGraphic)
	{
		// free some gpu memory
		if (graphic != null && graphic.bitmap != null && graphic.bitmap.__texture != null)
			graphic.bitmap.__texture.dispose();
		FlxG.bitmap.remove(graphic);
		graphicsDirty = true;
	}

	static public var currentLevel:String;
	static public function setCurrentLevel(name:String)
		currentLevel = name.toLowerCase();

	public static function getPath(file:String, ?type:AssetType = TEXT, ?parentfolder:String, ?modsAllowed:Bool = true):String
	{
		#if MODS_ALLOWED
		if(modsAllowed)
		{
			var customFile:String = file;
			if (parentfolder != null) customFile = '$parentfolder/$file';

			var modded:String = modFolders(customFile);
			if(FileSystem.exists(modded)) return modded;
		}
		#end

		if (parentfolder != null)
			return getFolderPath(file, parentfolder);

		if (currentLevel != null && currentLevel != 'shared')
		{
			var levelPath = getFolderPath(file, currentLevel);
			if (existsOnDiskOrManifest(levelPath, type))
				return levelPath;
		}
		return getSharedPath(file);
	}

	// disk first: base_game / quick-test files land in bin after the build, never in
	// the manifest. cacheBitmap already did this.
	public static function existsOnDiskOrManifest(path:String, ?type:AssetType = null):Bool
	{
		#if MODS_ALLOWED
		#end
		// keep desktop as it was, don't look inside the package
		#if MODS_ALLOWED
		return FileSystem.exists(path);
		#else
		return Assets.exists(path, type);
		#end
	}

	// Same idea for text: read the file if it's really there (mods, dropped-in files),
	// otherwise pull it out of the apk. Android has no assets on disk at all.
	public static function getTextFile(path:String, ?type:AssetType = TEXT):String
	{
		#if MODS_ALLOWED
		#end
		#if MODS_ALLOWED
		return FileSystem.exists(path) ? File.getContent(path) : null;
		#else
		return Assets.exists(path, type) ? Assets.getText(path) : null;
		#end
	}

	// mods -> level -> shared -> root; 0.6.x keeps base assets at the root.
	// On sys, retry from the exe dir when CWD is not bin, and return an absolute path.
	public static function findScriptFile(file:String):String
	{
		#if MODS_ALLOWED
		var modded:String = modFolders(file);
		if(FileSystem.exists(modded)) return modded;
		#end

		if(currentLevel != null && currentLevel != 'shared')
		{
			var levelPath:String = getFolderPath(file, currentLevel);
			if(existsOnDiskOrManifest(levelPath)) return levelPath;
		}

		var shared:String = getSharedPath(file);
		if(existsOnDiskOrManifest(shared)) return shared;

		var root:String = 'assets/$VERSION_DIR/$file';
		if(existsOnDiskOrManifest(root)) return root;

		// applicationDirectory can be read-only and crash liblime in some setups,
		// so only touch it on sys
		#if sys
		var appDir:String = lime.system.System.applicationDirectory;
		if(appDir != null)
		{
			var absShared:String = appDir + shared;
			if(FileSystem.exists(absShared)) return absShared;

			var absRoot:String = appDir + root;
			if(FileSystem.exists(absRoot)) return absRoot;

			#if MODS_ALLOWED
			var absMods:String = appDir + modFolders(file);
			if(FileSystem.exists(absMods)) return absMods;
			#end
		}
		#end

		return null;
	}

	inline static public function getFolderPath(file:String, folder = "shared")
		return 'assets/$VERSION_DIR/$folder/$file';

	inline public static function getSharedPath(file:String = '')
		return 'assets/$VERSION_DIR/shared/$file';

	inline static public function txt(key:String, ?folder:String)
		return getPath('data/$key.txt', TEXT, folder, true);

	inline static public function xml(key:String, ?folder:String)
		return getPath('data/$key.xml', TEXT, folder, true);

	inline static public function json(key:String, ?folder:String)
		return getPath('data/$key.json', TEXT, folder, true);

	inline static public function shaderFragment(key:String, ?folder:String)
		return getPath('shaders/$key.frag', TEXT, folder, true);

	inline static public function shaderVertex(key:String, ?folder:String)
		return getPath('shaders/$key.vert', TEXT, folder, true);

	inline static public function lua(key:String, ?folder:String)
		return getPath('$key.lua', TEXT, folder, true);

	static public function video(key:String)
	{
		#if MODS_ALLOWED
		var file:String = modsVideo(key);
		if(FileSystem.exists(file)) return file;
		#end
		return 'assets/$VERSION_DIR/videos/$key.$VIDEO_EXT';
	}

	inline static public function sound(key:String, ?modsAllowed:Bool = true):Sound
		return returnSound('sounds/$key', modsAllowed);

	inline static public function music(key:String, ?modsAllowed:Bool = true):Sound
		return returnSound('music/$key', modsAllowed);

	inline static public function inst(song:String, ?modsAllowed:Bool = true):Sound
		return returnSound('${formatToSongPath(song)}/Inst', 'songs', modsAllowed);

	inline static public function voices(song:String, postfix:String = null, ?modsAllowed:Bool = true):Sound
	{
		var songKey:String = '${formatToSongPath(song)}/Voices';
		if(postfix != null) songKey += '-' + postfix;
		//trace('songKey test: $songKey');
		return returnSound(songKey, 'songs', modsAllowed, false);
	}

	// Same lookup as returnSound, but the pcm stays on disk and lime feeds it through a
	// ring buffer while playing. Only the song tracks use this (see ClientPrefs.streamAudio);
	// effects and anything a script creates still go through returnSound.
	#if (desktop && lime_vorbis)
	public static function streamSound(key:String, ?path:String, ?modsAllowed:Bool = true):Sound
	{
		var file:String = getPath(Language.getFileTranslation(key) + '.$SOUND_EXT', SOUND, path, modsAllowed);
		if(!FileSystem.exists(file)) return null;

		var vorbis:lime.media.vorbis.VorbisFile = lime.media.vorbis.VorbisFile.fromFile(file);
		if(vorbis == null) return null;

		return Sound.fromAudioBuffer(lime.media.AudioBuffer.fromVorbisFile(vorbis));
	}

	inline static public function instStream(song:String, ?modsAllowed:Bool = true):Sound
		return streamSound('${formatToSongPath(song)}/Inst', 'songs', modsAllowed);

	inline static public function voicesStream(song:String, postfix:String = null, ?modsAllowed:Bool = true):Sound
	{
		var songKey:String = '${formatToSongPath(song)}/Voices';
		if(postfix != null) songKey += '-' + postfix;
		return streamSound(songKey, 'songs', modsAllowed);
	}
	#end

	inline static public function soundRandom(key:String, min:Int, max:Int, ?modsAllowed:Bool = true)
		return sound(key + FlxG.random.int(min, max), modsAllowed);

	public static var currentTrackedAssets:Map<String, FlxGraphic> = [];
	static public function image(key:String, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxGraphic
	{
		key = Language.getFileTranslation('images/$key') + '.png';

		// ticked category, but only mod files are fair game
		if (skippedByPicker(key, parentFolder))
			return LoadSkip.placeholder();

		var bitmap:BitmapData = null;
		if (currentTrackedAssets.exists(key))
		{
			localTrackedAssets.push(key);
			return currentTrackedAssets.get(key);
		}
		return cacheBitmap(key, parentFolder, bitmap, allowGPU);
	}

	public static function cacheBitmap(key:String, ?parentFolder:String = null, ?bitmap:BitmapData, ?allowGPU:Bool = true):FlxGraphic
	{
		if (bitmap == null)
		{
			var file:String = getPath(key, IMAGE, parentFolder, true);
			#if MODS_ALLOWED
			if (FileSystem.exists(file))
				bitmap = BitmapData.fromFile(file);
			else #end if (OpenFlAssets.exists(file, IMAGE))
				bitmap = OpenFlAssets.getBitmapData(file);

			if (bitmap == null)
			{
				trace('Bitmap not found: $file | key: $key');
				return null;
			}
		}

		if (allowGPU && ClientPrefs.data.cacheOnGPU && bitmap.image != null)
		{
			bitmap.lock();
			if (bitmap.__texture == null)
			{
				bitmap.image.premultiplied = true;
				bitmap.getTexture(FlxG.stage.context3D);
			}
			bitmap.getSurface();
			bitmap.disposeImage();
			bitmap.image.data = null;
			bitmap.image = null;
			bitmap.readable = true;
		}

		var graph:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, key);
		graph.persist = true;
		graph.destroyOnNoUse = false;

		currentTrackedAssets.set(key, graph);
		localTrackedAssets.push(key);
		return graph;
	}

	inline static public function getTextFromFile(key:String, ?ignoreMods:Bool = false):String
	{
		var path:String = getPath(key, TEXT, !ignoreMods);
		return getTextFile(path);
	}

	inline static public function font(key:String)
	{
		var folderKey:String = Language.getFileTranslation('fonts/$key');
		#if MODS_ALLOWED
		var file:String = modFolders(folderKey);
		if(FileSystem.exists(file)) return file;
		#end
		return 'assets/$VERSION_DIR/$folderKey';
	}

	public static function fileExists(key:String, type:AssetType, ?ignoreMods:Bool = false, ?parentFolder:String = null)
	{
		#if MODS_ALLOWED
		if(!ignoreMods)
		{
			var modKey:String = key;
			if(parentFolder == 'songs') modKey = 'songs/$key';

			if (FileSystem.exists(mods(Mods.currentModDirectory + '/' + modKey)) || FileSystem.exists(mods(modKey)))
				return true;
		}
		#end
		return existsOnDiskOrManifest(getPath(key, type, parentFolder, false), type);
	}

	static public function getAtlas(key:String, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var useMod = false;
		var imageLoaded:FlxGraphic = image(key, parentFolder, allowGPU);

		var myXml:Dynamic = getPath('images/$key.xml', TEXT, parentFolder, true);
		if(OpenFlAssets.exists(myXml) #if MODS_ALLOWED || (FileSystem.exists(myXml) && (useMod = true)) #end )
		{
			#if MODS_ALLOWED
			return FlxAtlasFrames.fromSparrow(imageLoaded, (useMod ? File.getContent(myXml) : myXml));
			#else
			return FlxAtlasFrames.fromSparrow(imageLoaded, myXml);
			#end
		}
		else
		{
			var myJson:Dynamic = getPath('images/$key.json', TEXT, parentFolder, true);
			if(OpenFlAssets.exists(myJson) #if MODS_ALLOWED || (FileSystem.exists(myJson) && (useMod = true)) #end )
			{
				#if MODS_ALLOWED
				return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, (useMod ? File.getContent(myJson) : myJson));
				#else
				return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, myJson);
				#end
			}
		}
		return getPackerAtlas(key, parentFolder);
	}
	
	static public function getMultiAtlas(keys:Array<String>, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		
		var parentFrames:FlxAtlasFrames = Paths.getAtlas(keys[0].trim());
		if(keys.length > 1)
		{
			var original:FlxAtlasFrames = parentFrames;
			parentFrames = new FlxAtlasFrames(parentFrames.parent);
			parentFrames.addAtlas(original, true);
			for (i in 1...keys.length)
			{
				var extraFrames:FlxAtlasFrames = Paths.getAtlas(keys[i].trim(), parentFolder, allowGPU);
				if(extraFrames != null)
					parentFrames.addAtlas(extraFrames, true);
			}
		}
		return parentFrames;
	}

		// atlas xml: read off disk, FlxAtlasFrames would parse the path as an asset id
	static function readTextOrPath(path:String):String
	{
		#if MODS_ALLOWED
		if(FileSystem.exists(path))
			return File.getContent(path);
		#end
		return path;
	}

	// only mod files get a placeholder; engine art must survive a whole category being ticked
	public static function skippedByPicker(fullKey:String, ?parentFolder:String):Bool
	{
		if (!LoadSkip.skipImage(fullKey)) return false;
		var file:String = getPath(fullKey, IMAGE, parentFolder);
		return file != null && file.indexOf('mods/') >= 0;
	}

	static public function getSparrowAtlas(key:String, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		#if MODS_ALLOWED
		var xmlExists:Bool = false;

		var xml:String = modsXml(key);
		if(FileSystem.exists(xml)) xmlExists = true;

		var xmlText:String = (xmlExists ? File.getContent(xml) : readTextOrPath(getPath(Language.getFileTranslation('images/$key') + '.xml', TEXT, parentFolder)));
		#else
		var xmlText:String = readTextOrPath(getPath(Language.getFileTranslation('images/$key') + '.xml', TEXT, parentFolder));
		#end

		// skipped: real frame rects, transparent texture. note skins are handled in Note.noteAtlas
		var fullKey:String = Language.getFileTranslation('images/$key') + '.png';
		if (skippedByPicker(fullKey, parentFolder))
			return LoadSkip.placeholderAtlas(xmlText, key, LoadSkip.KIND_SPARROW);

		var imageLoaded:FlxGraphic = image(key, parentFolder, allowGPU);
		return FlxAtlasFrames.fromSparrow(imageLoaded, xmlText);
	}

	static public function getPackerAtlas(key:String, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		#if MODS_ALLOWED
		var txtExists:Bool = false;

		var txt:String = modsTxt(key);
		if(FileSystem.exists(txt)) txtExists = true;

		var txtText:String = (txtExists ? File.getContent(txt) : readTextOrPath(getPath(Language.getFileTranslation('images/$key') + '.txt', TEXT, parentFolder)));
		#else
		var txtText:String = readTextOrPath(getPath(Language.getFileTranslation('images/$key') + '.txt', TEXT, parentFolder));
		#end

		var fullKey:String = Language.getFileTranslation('images/$key') + '.png';
		if (skippedByPicker(fullKey, parentFolder))
			return LoadSkip.placeholderAtlas(txtText, key, LoadSkip.KIND_PACKER);

		var imageLoaded:FlxGraphic = image(key, parentFolder, allowGPU);
		return FlxAtlasFrames.fromSpriteSheetPacker(imageLoaded, txtText);
	}

	static public function getAsepriteAtlas(key:String, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		#if MODS_ALLOWED
		var jsonExists:Bool = false;

		var json:String = modsImagesJson(key);
		if(FileSystem.exists(json)) jsonExists = true;

		var jsonText:String = (jsonExists ? File.getContent(json) : getPath(Language.getFileTranslation('images/$key') + '.json', TEXT, parentFolder));
		#else
		var jsonText:String = getPath(Language.getFileTranslation('images/$key') + '.json', TEXT, parentFolder);
		#end

		var fullKey:String = Language.getFileTranslation('images/$key') + '.png';
		if (skippedByPicker(fullKey, parentFolder))
			return LoadSkip.placeholderAtlas(jsonText, key, LoadSkip.KIND_JSON);

		var imageLoaded:FlxGraphic = image(key, parentFolder, allowGPU);
		return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, jsonText);
	}

	inline static public function formatToSongPath(path:String) {
		final invalidChars = ~/[~&;:<>#\s]/g;
		final hideChars = ~/[.,'"%?!]/g;

		return hideChars.replace(invalidChars.replace(path, '-'), '').trim().toLowerCase();
	}

	public static var currentTrackedSounds:Map<String, Sound> = [];
	public static function returnSound(key:String, ?path:String, ?modsAllowed:Bool = true, ?beepOnNull:Bool = true)
	{
		var file:String = getPath(Language.getFileTranslation(key) + '.$SOUND_EXT', SOUND, path, modsAllowed);

		//trace('precaching sound: $file');
		if(!currentTrackedSounds.exists(file))
		{
			#if sys
			if(FileSystem.exists(file))
				currentTrackedSounds.set(file, Sound.fromFile(file));
			#else
			if(OpenFlAssets.exists(file, SOUND))
				currentTrackedSounds.set(file, OpenFlAssets.getSound(file));
			#end
			else if(beepOnNull)
			{
				trace('SOUND NOT FOUND: $key, PATH: $path');
				FlxG.log.error('SOUND NOT FOUND: $key, PATH: $path');
				return FlxAssets.getSound('flixel/sounds/beep');
			}
		}
		localTrackedAssets.push(file);
		return currentTrackedSounds.get(file);
	}

	#if MODS_ALLOWED
	inline static public function mods(key:String = '')
		return 'mods/$VERSION_DIR/$key';

	/** This version's own modsList.txt; versions do not touch each other's. */
	inline static public function modsListPath():String
		return 'mods/$VERSION_DIR/modsList.txt';

	inline static public function modsJson(key:String)
		return modFolders('data/' + key + '.json');

	inline static public function modsVideo(key:String)
		return modFolders('videos/' + key + '.' + VIDEO_EXT);

	inline static public function modsSounds(path:String, key:String)
		return modFolders(path + '/' + key + '.' + SOUND_EXT);

	inline static public function modsImages(key:String)
		return modFolders('images/' + key + '.png');

	inline static public function modsXml(key:String)
		return modFolders('images/' + key + '.xml');

	inline static public function modsTxt(key:String)
		return modFolders('images/' + key + '.txt');

	inline static public function modsImagesJson(key:String)
		return modFolders('images/' + key + '.json');

	static public function modFolders(key:String)
	{
		if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
		{
			var fileToCheck:String = mods(Mods.currentModDirectory + '/' + key);
			if(FileSystem.exists(fileToCheck))
				return fileToCheck;
		}

		return mods(key);
	}
	#end

		// Which mod a script belongs to. mods/<version>/<mod>/ here, not flat mods/<mod>/.
	// Also takes absolute paths from findScriptFile.
	public static function modFromScriptPath(path:String):String
	{
		if(path == null || path.length == 0) return null;

		var p:String = path.replace('\\', '/');

		// absolute paths keep only the part after mods/
		var idx:Int = p.indexOf('/mods/');
		if(idx >= 0) p = p.substr(idx + 1);
		else if(!StringTools.startsWith(p, 'mods/')) return null;

		var rest:String = null;
		var versionPrefix:String = 'mods/$VERSION_DIR/';

		if(StringTools.startsWith(p, versionPrefix)) rest = p.substr(versionPrefix.length);
		else if(StringTools.startsWith(p, 'mods/')) rest = p.substr(5); // old layout: mods/<mod>/...

		if(rest == null) return null;

		var slash:Int = rest.indexOf('/');
		if(slash <= 0) return null;

		// mods/body/scripts/ is the global script folder, not a mod
		var name:String = rest.substr(0, slash);
		if(Mods.ignoreModFolders.contains(name.toLowerCase())) return null;
		if(name == Mods.currentModDirectory) return name;
		return null;
	}

		// Dedupe key: slashes + lower case. Windows exists() is case-insensitive
	// but returns what you passed, so string compare would load a script twice.
	public static function scriptKey(path:String):String
	{
		if(path == null) return null;
		return path.replace('\\', '/').toLowerCase();
	}

	/** Whether two script paths are the same file. Do not compare strings directly. */
	inline public static function sameScript(a:String, b:String):Bool
		return a != null && b != null && scriptKey(a) == scriptKey(b);

	#if flxanimate
	public static function loadAnimateAtlas(spr:FlxAnimate, folderOrImg:Dynamic, spriteJson:Dynamic = null, animationJson:Dynamic = null)
	{
		var changedAnimJson = false;
		var changedAtlasJson = false;
		var changedImage = false;
		
		if(spriteJson != null)
		{
			changedAtlasJson = true;
			spriteJson = File.getContent(spriteJson);
		}

		if(animationJson != null) 
		{
			changedAnimJson = true;
			animationJson = File.getContent(animationJson);
		}

		// is folder or image path
		if(Std.isOfType(folderOrImg, String))
		{
			var originalPath:String = folderOrImg;
			for (i in 0...10)
			{
				var st:String = '$i';
				if(i == 0) st = '';

				if(!changedAtlasJson)
				{
					spriteJson = getTextFromFile('images/$originalPath/spritemap$st.json');
					if(spriteJson != null)
					{
						//trace('found Sprite Json');
						changedImage = true;
						changedAtlasJson = true;
						folderOrImg = image('$originalPath/spritemap$st');
						break;
					}
				}
				else if(fileExists('images/$originalPath/spritemap$st.png', IMAGE))
				{
					//trace('found Sprite PNG');
					changedImage = true;
					folderOrImg = image('$originalPath/spritemap$st');
					break;
				}
			}

			if(!changedImage)
			{
				//trace('Changing folderOrImg to FlxGraphic');
				changedImage = true;
				folderOrImg = image(originalPath);
			}

			if(!changedAnimJson)
			{
				//trace('found Animation Json');
				changedAnimJson = true;
				animationJson = getTextFromFile('images/$originalPath/Animation.json');
			}
		}

		//trace(folderOrImg);
		//trace(spriteJson);
		//trace(animationJson);
		spr.loadAtlasEx(folderOrImg, spriteJson, animationJson);
	}
	#end
}
