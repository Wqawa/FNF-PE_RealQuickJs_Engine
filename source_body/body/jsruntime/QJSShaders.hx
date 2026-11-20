package jsruntime;

#if (!flash && sys)
import backend.ClientPrefs;
import backend.Mods;
import backend.Paths;
import psychlua.LuaUtils;
import psychlua.ShaderFunctions;
import flixel.FlxSprite;
import flixel.addons.display.FlxRuntimeShader;
import openfl.filters.ShaderFilter;

// JS shader table: same path order as Lua, but no lua_State to hang things off.
// Shares storedFilters with Lua so a tag is visible from both channels.
class QJSShaders
{
	public static var runtimeShaders:Map<String, Array<String>> = new Map();

	/** Name -> whether it was found and cached. Once cached, no more disk reads (same as Lua). */
	public static function init(name:String):Bool
	{
		if (name == null || name.length == 0) return false;
		if (!ClientPrefs.data.shaders) return false;

		var cached:Array<String> = runtimeShaders.get(name);
		if (cached != null && (cached[0] != null || cached[1] != null)) return true;

		var folders:Array<String> = [Paths.getSharedPath('shaders/')];
		#if MODS_ALLOWED
		folders.push(Paths.mods('shaders/'));
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			folders.insert(0, Paths.mods(Mods.currentModDirectory + '/shaders/'));		#end

		for (folder in folders)
		{
			if (!sys.FileSystem.exists(folder)) continue;

			var frag:String = null;
			var vert:String = null;
			var found:Bool = false;

			if (sys.FileSystem.exists(folder + name + '.frag'))
			{
				frag = sys.io.File.getContent(folder + name + '.frag');
				found = true;
			}
			if (sys.FileSystem.exists(folder + name + '.vert'))
			{
				vert = sys.io.File.getContent(folder + name + '.vert');
				found = true;
			}

			if (found)
			{
				runtimeShaders.set(name, [frag, vert]);
				return true;
			}
		}

		QuickJSHandler.log('[warn] initLuaShader: ' + name + '.frag / .vert not found');
		return false;
	}

	/** Returns [frag, vert], initialising once if needed. */
	public static function data(name:String):Array<String>
	{
		if (!runtimeShaders.exists(name) && !init(name)) return null;
		return runtimeShaders.get(name);
	}

	public static function setSprite(obj:String, shaderName:String):Bool
	{
		if (!ClientPrefs.data.shaders) return false;
		var d:Array<String> = data(shaderName);
		if (d == null) return false;

		var split:Array<String> = obj.split('.');
		var target:FlxSprite = cast LuaUtils.getObjectDirectly(split[0]);
		if (split.length > 1)
			target = cast LuaUtils.getVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1]);
		if (target == null) return false;

		target.shader = new shaders.ErrorHandledShader.ErrorHandledRuntimeShader(shaderName, d[0], d[1]);
		return true;
	}

	public static function addToCam(cam:String, shaderName:String, index:String):Bool
	{
		if (!ClientPrefs.data.shaders) return false;
		var d:Array<String> = data(shaderName);
		if (d == null) return false;

		var camera:Dynamic = ShaderFunctions.getCam(cam);
		if (camera == null) return false;
		if (index == null || index.length == 0) index = shaderName;

		// Do not touch _filters: it is a deprecated get/set pair in flixel 5.6 and reads null
		// through Dynamic (Invalid field:_filters - the old ShaderFunctions code died on it).
		var cur:Array<openfl.filters.BitmapFilter> = null;
		try cur = camera.filters catch (e:Dynamic) return false;

		var filter:ShaderFilter = new ShaderFilter(new FlxRuntimeShader(d[0], d[1]));
		var next:Array<openfl.filters.BitmapFilter> = (cur == null) ? [] : cur.copy();
		next.push(filter);
		try camera.setFilters(next) catch (e:Dynamic) return false;

		ShaderFunctions.storedFilters.set(index, filter);
		return true;
	}

	public static function removeFromCam(cam:String, index:String):Bool
	{
		var camera:Dynamic = ShaderFunctions.getCam(cam);
		if (camera == null) return false;
		if (!ShaderFunctions.storedFilters.exists(index)) return false;

		var cur:Array<openfl.filters.BitmapFilter> = null;
		try cur = camera.filters catch (e:Dynamic) return false;
		if (cur == null) return false;

		var dead:ShaderFilter = ShaderFunctions.storedFilters.get(index);
		var next:Array<openfl.filters.BitmapFilter> = [];
		for (f in cur)
			if (f != dead) next.push(f);
		try camera.setFilters(next) catch (e:Dynamic) return false;

		ShaderFunctions.storedFilters.remove(index);
		return true;
	}

	public static function clearCam(cam:String):Bool
	{
		var camera:Dynamic = ShaderFunctions.getCam(cam);
		if (camera == null) return false;
		camera.setFilters([]);
		return true;
	}
}
#end
