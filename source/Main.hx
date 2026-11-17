package;

import openfl.Lib;

/**
 * Process entry point (Project.xml <app main="Main">): initialise, then follow engine.txt.
 *
 * It does three things: install the crash handler, read engine.txt, attach that tree's Sprite.
 * Do not add game code here. This is the shared layer and all three trees use it; the
 * moment it imports backend.* / states.* / objects.*, running vanilla or 0.6.3 means
 * body code running in another tree, with asset paths pointing at assets/body.
 *
 * Layout: source/ = shared, source_body/body/ = modified 1.0.4, source_vanilla/vanilla/ and
 * source_063/pe063/ = the other two trees. The shared layer may only use flixel / lime / std.
 */
class Main
{
	public static function main():Void
	{
		// The crash handler must be installed before the fork: one entry, all three trees.
		backend.EngineCrash.install();

		// engine.txt in the bin root: vanilla = original 1.0.4, pe063 = 0.6.3, anything else = body
		if (Engine.isVanilla())
		{
			Lib.current.addChild(new vanilla.Main());
			return;
		}

		if (Engine.isPe063())
		{
			Lib.current.addChild(new pe063.Main());
			return;
		}

		Lib.current.addChild(new body.Main());
	}
}
