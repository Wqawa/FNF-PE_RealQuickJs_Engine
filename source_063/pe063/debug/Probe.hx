package pe063.debug;

import openfl.utils.AssetType;
import pe063.Paths;
import pe063.animateatlas.AtlasFrameMaker;
import sys.FileSystem;
import sys.io.File;

/**
 * Path probe for the 0.6.3 tree.
 *
 * With PE_063_PROBE=1, Main.main() skips the game and runs this: resolve the paths lua
 * texture mode (AtlasFrameMaker) uses, build the atlas for real, write the result to
 * .workbuddy/testout/pe063_probe.txt and exit.
 *
 * Why: this tree has no automated entry (the test hook lives on the body branch), so
 * Paths or atlas changes could not be verified. It creates no window and makes no sound.
 */
class Probe
{
	static var out:StringBuf;

	static function log(s:String)
	{
		out.add(s + '\n');
		Sys.println('[probe] ' + s);
	}

	static final OUT_PATH:String = 'D:/FNF/FNF-PE_RealQuickJs_Engine/.workbuddy/testout/pe063_probe.txt';

	public static function run():Void
	{
		// lime builds the window before main(); hide it first so nothing flashes on screen
		try lime.app.Application.current.window.visible = false catch (e:Dynamic) {}

		out = new StringBuf();
		var oldLevel:String = Paths.currentLevel;
		var oldMod:String = Paths.currentModDirectory;

		// 1. official atlas found through the week folder (how 0.6.3 calls it)
		Paths.setCurrentLevel('week7');
		probeAtlas('cutscenes/stressPico');

		// 2. atlas inside a mod (real lua texture usage): copy one into mods/0.6.3/probe
		var src:String = 'assets/0.6.3/week7/images/cutscenes/stressPico';
		var dst:String = 'mods/0.6.3/probe/images/characters/stressPico';
		try
		{
			FileSystem.createDirectory(dst);
			for (f in ['Animation.json', 'spritemap.json', 'spritemap.png'])
				File.saveBytes('$dst/$f', File.getBytes('$src/$f'));

			Paths.currentModDirectory = 'probe';
			Paths.setCurrentLevel('shared');
			probeAtlas('characters/stressPico');
		}
		catch (e:Dynamic)
			log('could not prepare the mod case: ' + e);

		// 3. clean up: remove the probe mod from the player's mods folder
		Paths.currentModDirectory = oldMod;
		Paths.currentLevel = oldLevel;
		try
		{
			for (f in ['Animation.json', 'spritemap.json', 'spritemap.png'])
				FileSystem.deleteFile('$dst/$f');
			FileSystem.deleteDirectory(dst);
			FileSystem.deleteDirectory('mods/0.6.3/probe/images/characters');
			FileSystem.deleteDirectory('mods/0.6.3/probe/images');
			FileSystem.deleteDirectory('mods/0.6.3/probe');
		}
		catch (e:Dynamic)
			log('cleanup failed (does not affect the result): ' + e);

		File.saveContent(OUT_PATH, out.toString());
		Sys.exit(0);
	}

	static function probeAtlas(key:String):Void
	{
		log('--- key=' + key + '  level=' + Paths.currentLevel + '  mod=' + Paths.currentModDirectory);
		log('  fileExists(images/$key/spritemap.json) = ' + Paths.fileExists('images/$key/spritemap.json', AssetType.TEXT));
		log('  getTextFromFile(images/$key/Animation.json) != null = ' + (Paths.getTextFromFile('images/$key/Animation.json') != null));
		log('  getPath(images/$key/spritemap.png) = ' + Paths.getPath('images/$key/spritemap.png', AssetType.IMAGE));

		try
		{
			var frames = AtlasFrameMaker.construct(key);
			log('  construct = ' + (frames == null ? 'null' : frames.numFrames + ' frames'));
		}
		catch (e:Dynamic)
			log('  construct ERROR: ' + e);
	}
}
