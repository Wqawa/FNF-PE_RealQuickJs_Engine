package jsruntime;

import psychlua.IScriptHost;

/**
 * 一个 .js 文件在 QuickJS 里的落脚点。
 *
 * 原来 JSPlayer 把 handle 和 path 存成两个平行数组，取归属、判重、发事件
 * 全靠下标对位 —— 加一个脚本就得同步推三个数组，删一个要三处 remove。
 * 改成对象之后每个脚本自己带着 handle / 路径 / 归属 mod，和 Lua 那条
 * 「一个文件一个 lua_State」的结构对齐。
 */
class JSScriptHost implements IScriptHost
{
	public var handle:Int;
	public var path:String;
	public var modFolder:String;
	public var closed:Bool = false;

	public function new(handle:Int, path:String, ?mod:String)
	{
		this.handle = handle;
		this.path = path;
		this.modFolder = mod;
	}

	// ------------------------------------------------------------- IScriptHost
	public function scriptId():String return path;
	public function scriptMod():String return modFolder;
	public function isClosed():Bool return closed;

	public function emit(func:String, args:Array<Dynamic>):Dynamic
		return JSPlayer.emitTo(this, func, args);

	public function setVar(name:String, value:Dynamic):Void
	{
		if (!closed) QuickJSHandler.setGlobal(handle, name, value);
	}

	/**
	 * QuickJS 这侧只有 setGlobal，没有反着读的宿主函数。
	 * 要读脚本内部的变量，走 QuickJSHandler 里 getGlobalFromScript 那条通道。
	 */
	public function getVar(name:String):Dynamic
		return null;

	public function shutdown():Void
	{
		if (closed) return;
		closed = true;
		QuickJSHandler.dispose(handle);
	}
}
