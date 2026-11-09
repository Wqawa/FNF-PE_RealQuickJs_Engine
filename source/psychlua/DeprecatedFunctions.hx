package psychlua;

//
// This is simply where i store deprecated functions for it to be more organized.
// I would suggest not messing with these, as it could break mods.
//

class DeprecatedFunctions
{
	public static function implement(funk:FunkinLua)
	{
		var lua:State = funk.lua;
		// DEPRECATED, DONT MESS WITH THESE SHITS, ITS JUST THERE FOR BACKWARD COMPATIBILITY
		Lua_helper.add_callback(lua, "addAnimationByIndicesLoop", function(obj:String, name:String, prefix:String, indices:String, framerate:Int = 24) {
			FunkinLua.luaTrace("addAnimationByIndicesLoop is deprecated! Use addAnimationByIndices instead", false, true);
			return LuaUtils.addAnimByIndices(obj, name, prefix, indices, framerate, true);
		});

		Lua_helper.add_callback(lua, "objectPlayAnimation", function(obj:String, name:String, forced:Bool = false, ?startFrame:Int = 0) {
			FunkinLua.luaTrace("objectPlayAnimation is deprecated! Use playAnim instead", false, true);
			if(PlayState.instance.getLuaObject(obj) != null) {
				PlayState.instance.getLuaObject(obj).animation.play(name, forced, false, startFrame);
				return true;
			}

			var spr:FlxSprite = Reflect.getProperty(LuaUtils.getTargetInstance(), obj);
			if(spr != null) {
				spr.animation.play(name, forced, false, startFrame);
				return true;
			}
			return false;
		});
		Lua_helper.add_callback(lua, "characterPlayAnim", function(character:String, anim:String, ?forced:Bool = false) {
			FunkinLua.luaTrace("characterPlayAnim is deprecated! Use playAnim instead", false, true);
			switch(character.toLowerCase()) {
				case 'dad':
					if(PlayState.instance.dad.hasAnimation(anim))
						PlayState.instance.dad.playAnim(anim, forced);
				case 'gf' | 'girlfriend':
					if(PlayState.instance.gf != null && PlayState.instance.gf.hasAnimation(anim))
						PlayState.instance.gf.playAnim(anim, forced);
				default:
					if(PlayState.instance.boyfriend.hasAnimation(anim))
						PlayState.instance.boyfriend.playAnim(anim, forced);
			}
		});
		Lua_helper.add_callback(lua, "luaSpriteMakeGraphic", function(tag:String, width:Int, height:Int, color:String) {
			FunkinLua.luaTrace("luaSpriteMakeGraphic is deprecated! Use makeGraphic instead", false, true);
			if(MusicBeatState.getVariables().exists(tag))
				MusicBeatState.getVariables().get(tag).makeGraphic(width, height, CoolUtil.colorFromString(color));
		});
		Lua_helper.add_callback(lua, "luaSpriteAddAnimationByPrefix", function(tag:String, name:String, prefix:String, framerate:Int = 24, loop:Bool = true) {
			FunkinLua.luaTrace("luaSpriteAddAnimationByPrefix is deprecated! Use addAnimationByPrefix instead", false, true);
			if(MusicBeatState.getVariables().exists(tag)) {
				var cock:ModchartSprite = MusicBeatState.getVariables().get(tag);
				cock.animation.addByPrefix(name, prefix, framerate, loop);
				if(cock.animation.curAnim == null) {
					cock.animation.play(name, true);
				}
			}
		});
		Lua_helper.add_callback(lua, "luaSpriteAddAnimationByIndices", function(tag:String, name:String, prefix:String, indices:String, framerate:Int = 24) {
			FunkinLua.luaTrace("luaSpriteAddAnimationByIndices is deprecated! Use addAnimationByIndices instead", false, true);
			if(MusicBeatState.getVariables().exists(tag)) {
				var strIndices:Array<String> = indices.trim().split(',');
				var die:Array<Int> = [];
				for (i in 0...strIndices.length) {
					die.push(Std.parseInt(strIndices[i]));
				}
				var pussy:ModchartSprite = MusicBeatState.getVariables().get(tag);
				pussy.animation.addByIndices(name, prefix, die, '', framerate, false);
				if(pussy.animation.curAnim == null) {
					pussy.animation.play(name, true);
				}
			}
		});
		Lua_helper.add_callback(lua, "luaSpritePlayAnimation", function(tag:String, name:String, forced:Bool = false) {
			FunkinLua.luaTrace("luaSpritePlayAnimation is deprecated! Use playAnim instead", false, true);
			if(MusicBeatState.getVariables().exists(tag)) {
				MusicBeatState.getVariables().get(tag).animation.play(name, forced);
			}
		});
		Lua_helper.add_callback(lua, "setLuaSpriteCamera", function(tag:String, camera:String = '') {
			FunkinLua.luaTrace("setLuaSpriteCamera is deprecated! Use setObjectCamera instead", false, true);
			if(MusicBeatState.getVariables().exists(tag)) {
				// variables is Map<String, Dynamic>; assigning .cameras on an untyped value
				// throws "Invalid field:cameras" (it's a get/set property, not a real field),
				// so it has to go through a typed reference first.
				var spr:flixel.FlxBasic = cast MusicBeatState.getVariables().get(tag);
				spr.cameras = [LuaUtils.cameraFromString(camera)];
				return true;
			}
			FunkinLua.luaTrace("Lua sprite with tag: " + tag + " doesn't exist!");
			return false;
		});
		Lua_helper.add_callback(lua, "setLuaSpriteScrollFactor", function(tag:String, scrollX:Float, scrollY:Float) {
			FunkinLua.luaTrace("setLuaSpriteScrollFactor is deprecated! Use setScrollFactor instead", false, true);
			if(MusicBeatState.getVariables().exists(tag)) {
				MusicBeatState.getVariables().get(tag).scrollFactor.set(scrollX, scrollY);
				return true;
			}
			return false;
		});
		Lua_helper.add_callback(lua, "scaleLuaSprite", function(tag:String, x:Float, y:Float) {
			FunkinLua.luaTrace("scaleLuaSprite is deprecated! Use scaleObject instead", false, true);
			if(MusicBeatState.getVariables().exists(tag)) {
				var shit:ModchartSprite = MusicBeatState.getVariables().get(tag);
				shit.scale.set(x, y);
				shit.updateHitbox();
				return true;
			}
			return false;
		});
		Lua_helper.add_callback(lua, "getPropertyLuaSprite", function(tag:String, variable:String) {
			FunkinLua.luaTrace("getPropertyLuaSprite is deprecated! Use getProperty instead", false, true);
			if(MusicBeatState.getVariables().exists(tag)) {
				var killMe:Array<String> = variable.split('.');
				if(killMe.length > 1) {
					var coverMeInPiss:Dynamic = Reflect.getProperty(MusicBeatState.getVariables().get(tag), killMe[0]);
					for (i in 1...killMe.length-1) {
						coverMeInPiss = Reflect.getProperty(coverMeInPiss, killMe[i]);
					}
					return Reflect.getProperty(coverMeInPiss, killMe[killMe.length-1]);
				}
				return Reflect.getProperty(MusicBeatState.getVariables().get(tag), variable);
			}
			return null;
		});
		Lua_helper.add_callback(lua, "setPropertyLuaSprite", function(tag:String, variable:String, value:Dynamic) {
			FunkinLua.luaTrace("setPropertyLuaSprite is deprecated! Use setProperty instead", false, true);
			if(MusicBeatState.getVariables().exists(tag)) {
				var killMe:Array<String> = variable.split('.');
				if(killMe.length > 1) {
					var coverMeInPiss:Dynamic = Reflect.getProperty(MusicBeatState.getVariables().get(tag), killMe[0]);
					for (i in 1...killMe.length-1) {
						coverMeInPiss = Reflect.getProperty(coverMeInPiss, killMe[i]);
					}
					Reflect.setProperty(coverMeInPiss, killMe[killMe.length-1], value);
					return true;
				}
				Reflect.setProperty(MusicBeatState.getVariables().get(tag), variable, value);
				return true;
			}
			FunkinLua.luaTrace("setPropertyLuaSprite: Lua sprite with tag: " + tag + " doesn't exist!");
			return false;
		});
		Lua_helper.add_callback(lua, "musicFadeIn", function(duration:Float, fromValue:Float = 0, toValue:Float = 1) {
			FlxG.sound.music.fadeIn(duration, fromValue, toValue);
			FunkinLua.luaTrace('musicFadeIn is deprecated! Use soundFadeIn instead.', false, true);

		});
		Lua_helper.add_callback(lua, "musicFadeOut", function(duration:Float, toValue:Float = 0) {
			FlxG.sound.music.fadeOut(duration, toValue);
			FunkinLua.luaTrace('musicFadeOut is deprecated! Use soundFadeOut instead.', false, true);
		});
		Lua_helper.add_callback(lua, "updateHitboxFromGroup", function(group:String, index:Int) {
			if(Std.isOfType(Reflect.getProperty(LuaUtils.getTargetInstance(), group), FlxTypedGroup)) {
				Reflect.getProperty(LuaUtils.getTargetInstance(), group).members[index].updateHitbox();
				return;
			}
			Reflect.getProperty(LuaUtils.getTargetInstance(), group)[index].updateHitbox();
			FunkinLua.luaTrace('updateHitboxFromGroup is deprecated! Use updateHitbox instead.', false, true);
		});

		// 0.6.3: debugPrint(text1, text2, text3, text4, text5) —— 全拼成一行
		// 1.0.4: debugPrint(text, color)
		// 老 mod 的 debugPrint('hp', hp) 按新签名会把 hp 当颜色名吞掉，文本还在、数值没了。
		// 这里按"第二个参数像不像颜色"分流，两种写法都认。
		// 注册得比 FunkinLua 里那次晚，同名会覆盖，所以不用去动原实现。
		//
		// 数字（Int/Float）一律不进颜色分支：1.0.4 的 color 参数本来就是 String，
		// 数字永远不可能是合法的新语义颜色；反过来 8 位十进制数全是合法 hex 字符，
		// 不排除的话 debugPrint('id', 16711680) 的数值会被当颜色吞掉。
		// 实在猜不中的 mod 还有逃生门：环境变量 PE_DEBUGPRINT_LEGACY=1 强制老拼接语义。
		Lua_helper.add_callback(lua, "debugPrint", function(text1:Dynamic = '', ?text2:Dynamic = null,
				?text3:Dynamic = null, ?text4:Dynamic = null, ?text5:Dynamic = null) {
			var extra:Array<Dynamic> = [];
			for (v in [text2, text3, text4, text5])
				if(v != null) extra.push(v);

			if(!forceLegacyDebugPrint() && extra.length == 1
				&& !Std.isOfType(extra[0], Int) && !Std.isOfType(extra[0], Float)
				&& looksLikeColor('' + extra[0]))
			{
				// 新写法
				if(PlayState.instance != null)
					PlayState.instance.addTextToDebug('' + text1, CoolUtil.colorFromString('' + extra[0]));
				return;
			}

			// 老写法：全拼起来
			var text:String = '' + text1;
			for (v in extra) text += '' + v;

			if(PlayState.instance != null)
				PlayState.instance.addTextToDebug(text, FlxColor.WHITE);
			else
				trace(text);
		});
	}

	// PE_DEBUGPRINT_LEGACY 设成 1/true 后 debugPrint 一律走老拼接语义，不再猜。
	static var legacyOnly:Null<Bool> = null;
	static function forceLegacyDebugPrint():Bool
	{
		if(legacyOnly != null) return legacyOnly;
		legacyOnly = false;
		#if sys
		var v:String = Sys.getEnv('PE_DEBUGPRINT_LEGACY');
		legacyOnly = (v == '1' || v == 'true');
		#end
		return legacyOnly;
	}

	// CoolUtil.colorFromString 对不认识的颜色静默返回白色，没法拿来判断"这是不是颜色"，
	// 所以这边自己认一遍：颜色名 / 6 或 8 位十六进制。
	static var COLOR_NAMES:Array<String> = [
		'WHITE', 'BLACK', 'RED', 'GREEN', 'BLUE', 'YELLOW', 'ORANGE', 'PURPLE', 'PINK', 'BROWN',
		'GRAY', 'GREY', 'CYAN', 'MAGENTA', 'LIME', 'NAVY', 'TEAL', 'OLIVE', 'MAROON', 'SILVER', 'GOLD'
	];

	static function looksLikeColor(raw:String):Bool
	{
		var s:String = raw.trim().toUpperCase();
		if(s.startsWith('0X') || s.startsWith('#')) s = s.substr(s.startsWith('0X') ? 2 : 1);

		if(s.length == 6 || s.length == 8)
		{
			var allHex:Bool = true;
			for (i in 0...s.length)
			{
				var c:Int = s.charCodeAt(i);
				if(!((c >= 48 && c <= 57) || (c >= 65 && c <= 70)))
				{
					allHex = false;
					break;
				}
			}
			if(allHex) return true;
		}
		return COLOR_NAMES.contains(raw.trim().toUpperCase());
	}
}