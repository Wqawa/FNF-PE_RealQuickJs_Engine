package psychlua;

/**
 * 三条脚本通道（Lua / HScript / QuickJS）的共同契约。
 *
 * 为什么要有这个：PlayState 里原来是三套遍历 —— `luaArray`、`hscriptArray`、
 * 还有 JSPlayer 的 handles+paths 两个并行静态数组。每加一个事件回调都要
 * 记得三处都发到，漏一处就是"这个事件只有 lua 收得到"的灵异现象。
 * 接口把「给某个脚本发一个回调」收敛成一个方法，分发方只认 IScriptHost。
 *
 * 各通道的差异**没有**被磨平，而是各自封在 emit 里：
 *   - Lua     ：直接 call，回调不存在时由 call 内部报 luaTrace
 *   - HScript ：先 exists 再 call，取 IrisCall.returnValue
 *   - QuickJS ：callGlobal，未定义的回调由 QuickJS 自己吃掉
 *
 * 停止语义（Function_StopLua / StopHScript / StopAll）也没有进接口 ——
 * 「哪个通道能被哪个哨兵停掉」是通道自己的属性，由分发方判断。
 *
 * 这里刻意用方法而不是字段：三个实现类各自已经有 scriptName / origin /
 * modFolder / closed 这些字段，直接声明属性接口会和它们的所有权、可写性
 * 打架。方法名带前缀（scriptId / scriptMod）避免和字段重名。
 */
interface IScriptHost
{
	/** 日志和 exclusions 用的稳定标识，一般是脚本文件的完整路径。 */
	public function scriptId():String;

	/** 归属 mod，null 表示不属于任何 mod（mods 根、shared、assets）。 */
	public function scriptMod():String;

	/** 已关闭，分发时直接跳过。 */
	public function isClosed():Bool;

	/** 触发一个回调。脚本里没定义就返回 null，不抛异常。 */
	public function emit(func:String, args:Array<Dynamic>):Dynamic;

	/** 给脚本里的全局变量赋值。 */
	public function setVar(name:String, value:Dynamic):Void;

	/** 读脚本里的全局变量，不存在返回 null。 */
	public function getVar(name:String):Dynamic;

	/** 结束并释放资源，之后 isClosed() 为 true。 */
	public function shutdown():Void;
}
