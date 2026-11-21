package;

import openfl.Lib;

// Entry point: install crash handler, read engine.txt, attach that tree's Sprite.
// Shared layer - only flixel/lime/std here, never a tree's classes.
class Main
{
	public static function main():Void
	{
		// The crash handler must be installed before the fork: one entry, all three trees.
		backend.EngineCrash.install();


		// engine.txt: vanilla = original 1.0.4, pe063 = 0.6.3, anything else = body
		// on Android the apk copy is read-only; Engine also tries the writable cwd
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
