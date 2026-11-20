package pe063;

import pe063.Paths;
import flixel.FlxG;
import flixel.util.FlxColor;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.util.FlxTimer;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.text.FlxText;
import flixel.group.FlxGroup.FlxTypedGroup;
#if (!flash && sys)
import flixel.addons.display.FlxRuntimeShader;
#end
#if hscript
import hscript.Parser;
import hscript.Interp;
#end

using StringTools;

#if hscript
class HScript
{
	public static var parser:Parser = new Parser();
	public var interp:Interp;

	public var variables(get, never):Map<String, Dynamic>;

	public function get_variables()
	{
		return interp.variables;
	}

	public function new()
	{
		interp = new Interp();
		interp.variables.set('FlxG', FlxG);
		interp.variables.set('FlxSprite', FlxSprite);
		interp.variables.set('FlxCamera', FlxCamera);
		interp.variables.set('FlxTimer', FlxTimer);
		interp.variables.set('FlxTween', FlxTween);
		interp.variables.set('FlxEase', FlxEase);
		interp.variables.set('PlayState', PlayState);
		interp.variables.set('game', PlayState.instance);
		interp.variables.set('Paths', Paths);
		interp.variables.set('Conductor', Conductor);
		interp.variables.set('ClientPrefs', ClientPrefs);
		interp.variables.set('Character', Character);
		interp.variables.set('Alphabet', Alphabet);
		interp.variables.set('CustomSubstate', CustomSubstate);
		#if (!flash && sys)
		interp.variables.set('FlxRuntimeShader', FlxRuntimeShader);
		#end
		interp.variables.set('ShaderFilter', openfl.filters.ShaderFilter);
		interp.variables.set('StringTools', StringTools);

		interp.variables.set('setVar', function(name:String, value:Dynamic)
		{
			PlayState.instance.variables.set(name, value);
		});
		interp.variables.set('getVar', function(name:String)
		{
			var result:Dynamic = null;
			if(PlayState.instance.variables.exists(name)) result = PlayState.instance.variables.get(name);
			return result;
		});
		interp.variables.set('removeVar', function(name:String)
		{
			if(PlayState.instance.variables.exists(name))
			{
				PlayState.instance.variables.remove(name);
				return true;
			}
			return false;
		});
	}

	public function execute(codeToRun:String):Dynamic
	{
		@:privateAccess
		HScript.parser.line = 1;
		HScript.parser.allowTypes = true;
		return interp.execute(HScript.parser.parseString(codeToRun));
	}

	// Unknown global -> resolveClass -> retry (up to 8)
	public function executeAuto(codeToRun:String, resolver:String->Dynamic):Dynamic
	{
		var tries:Int = 0;
		while (true)
		{
			try {
				return execute(codeToRun);
			}
			catch (e:Dynamic) {
				if (tries >= 8) throw e;
				var msg:String = Std.string(e);
				var at:Int = msg.indexOf('Unknown variable');
				if (at < 0) throw e;
				var rest:String = msg.substr(at + 'Unknown variable'.length).trim();
				var name:String = rest.split(' ')[0].split('\n')[0].trim();
				if (name.length == 0) throw e;
				var cls:Dynamic = resolver(name);
				if (cls == null) throw e;
				interp.variables.set(name, cls);
				tries++;
			}
		}
		return null;
	}
}
#end
