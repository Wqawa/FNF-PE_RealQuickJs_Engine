package pe063;

import Sys.sleep;
import sys.thread.Thread;

import hxdiscord_rpc.Discord;
import hxdiscord_rpc.Types;

#if LUA_ALLOWED
import llua.Lua;
import llua.State;
#end

using StringTools;

class DiscordClient
{
	public static var isInitialized:Bool = false;
	public static var clientID:String = "863222024192262205";

	private static var presence:DiscordPresence = new DiscordPresence();
	@:unreflective private static var __thread:Thread;

	public static function initialize()
	{
		trace("Discord Client starting...");

		var discordHandlers:DiscordEventHandlers = DiscordEventHandlers.create();
		discordHandlers.ready = cpp.Function.fromStaticFunction(onReady);
		discordHandlers.disconnected = cpp.Function.fromStaticFunction(onDisconnected);
		discordHandlers.errored = cpp.Function.fromStaticFunction(onError);
		Discord.Initialize(clientID, cpp.RawPointer.addressOf(discordHandlers), 1, null);

		if (!isInitialized) trace("Discord Client started.");

		if (__thread == null)
		{
			__thread = Thread.create(() ->
			{
				while (true)
				{
					if (isInitialized) Discord.RunCallbacks();
					sleep(1.0);
				}
			});
		}
		isInitialized = true;
	}

	public static function shutdown()
	{
		isInitialized = false;
		Discord.Shutdown();
	}

	static function onReady(request:cpp.RawConstPointer<DiscordUser>):Void
	{
		var user = cast (request[0].username, String);
		trace('(Discord) Connected to User ($user)');
		changePresence("In the Menus", null);
	}

	static function onError(errorCode:Int, message:cpp.ConstCharStar):Void
	{
		trace('Discord: Error ($errorCode: ${cast(message, String)})');
	}

	static function onDisconnected(errorCode:Int, message:cpp.ConstCharStar):Void
	{
		trace('Discord: Disconnected ($errorCode: ${cast(message, String)})');
	}

	public static function changePresence(details:String, state:Null<String>, ?smallImageKey:String, ?hasStartTimestamp:Bool, ?endTimestamp:Float)
	{
		var startTimestamp:Float = 0;
		if (hasStartTimestamp) startTimestamp = Date.now().getTime();
		if (endTimestamp > 0) endTimestamp = startTimestamp + endTimestamp;

		presence.details = details;
		presence.state = state;
		presence.largeImageKey = 'icon';
		presence.largeImageText = "Engine Version: " + MainMenuState.psychEngineVersion;
		presence.smallImageKey = smallImageKey;
		// Obtained times are in milliseconds so they are divided so Discord can use it
		presence.startTimestamp = Std.int(startTimestamp / 1000);
		presence.endTimestamp = Std.int(endTimestamp / 1000);

		Discord.UpdatePresence(cpp.RawConstPointer.addressOf(presence.__presence));

		//trace('Discord RPC Updated. Arguments: $details, $state, $smallImageKey, $hasStartTimestamp, $endTimestamp');
	}

	#if LUA_ALLOWED
	public static function addLuaCallbacks(lua:State)
	{
		Lua_helper.add_callback(lua, "changePresence", function(details:String, state:Null<String>, ?smallImageKey:String, ?hasStartTimestamp:Bool, ?endTimestamp:Float)
		{
			changePresence(details, state, smallImageKey, hasStartTimestamp, endTimestamp);
		});
	}
	#end
}

@:allow(pe063.DiscordClient)
private final class DiscordPresence
{
	public var state(get, set):Null<String>;
	public var details(get, set):Null<String>;
	public var smallImageKey(get, set):Null<String>;
	public var largeImageKey(get, set):Null<String>;
	public var largeImageText(get, set):Null<String>;
	public var startTimestamp(get, set):Int;
	public var endTimestamp(get, set):Int;

	@:noCompletion public var __presence:DiscordRichPresence;

	function new()
	{
		__presence = DiscordRichPresence.create();
	}

	inline function get_state():Null<String>
		return __presence.state;

	inline function set_state(value:Null<String>):Null<String>
		return __presence.state = cast value;

	inline function get_details():Null<String>
		return __presence.details;

	inline function set_details(value:Null<String>):Null<String>
		return __presence.details = cast value;

	inline function get_smallImageKey():Null<String>
		return __presence.smallImageKey;

	inline function set_smallImageKey(value:Null<String>):Null<String>
		return __presence.smallImageKey = cast value;

	inline function get_largeImageKey():Null<String>
		return __presence.largeImageKey;

	inline function set_largeImageKey(value:Null<String>):Null<String>
		return __presence.largeImageKey = cast value;

	inline function get_largeImageText():Null<String>
		return __presence.largeImageText;

	inline function set_largeImageText(value:Null<String>):Null<String>
		return __presence.largeImageText = cast value;

	inline function get_startTimestamp():Int
		return __presence.startTimestamp;

	inline function set_startTimestamp(value:Int):Int
		return __presence.startTimestamp = value;

	inline function get_endTimestamp():Int
		return __presence.endTimestamp;

	inline function set_endTimestamp(value:Int):Int
		return __presence.endTimestamp = value;
}
