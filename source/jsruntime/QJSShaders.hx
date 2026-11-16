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

/**
 * JS 通道的 runtime shader 表。
 *
 * 逻辑照 FunkinLua.initLuaShader / ShaderFunctions 抄：路径优先级一样（当前 mod → 全局 mod →
 * mods/body → 共享目录）、.frag 和 .vert 各读各的、只要有一个存在就算找到。
 * 区别只是不挂在 lua_State 上 —— QuickJS 这边一个 context 对一个文件，没有现成的实例字段可放。
 *
 * 相机上的 filter 故意和 Lua 共用 ShaderFunctions.storedFilters：这样 JS 能摘掉 Lua 挂上去的，
 * 反过来也一样。各存一份的话，同一个 tag 在两个通道里会互相看不见。
 */
class QJSShaders
{
	public static var runtimeShaders:Map<String, Array<String>> = new Map();

	/** 名字 → 找到并缓存了没有。缓存住就不再读盘（和 Lua 那边一样）。 */
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
			folders.insert(0, Paths.mods(Mods.currentModDirectory + '/shaders/'));
		for (mod in Mods.getGlobalMods())
			folders.insert(0, Paths.mods(mod + '/shaders/'));
		#end

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

		QuickJSHandler.log('[warn] initLuaShader: 找不到 ' + name + '.frag / .vert');
		return false;
	}

	/** 拿 [frag, vert]，没缓存就先 init 一次 */
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

		// 别碰 _filters：flixel 5.6 里那是被 deprecated 的 get/set 属性，Dynamic 上取不到
		// （报 Invalid field:_filters，ShaderFunctions 的老写法就栽在这）。真字段是 filters。
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
