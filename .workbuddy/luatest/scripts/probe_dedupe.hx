// 给 compat_isolation.lua 用来验证 addHScript 判重：每建一个实例 onCreate 就跑一次。
// 只做最基本的自增，别用花活 —— 这是测判重，不是测 hscript 语法。
function onCreate()
{
	var n = getVar('probe_hx_creates');
	if (n == null) n = 0;
	n = n + 1;
	setVar('probe_hx_creates', n);
	trace('probe_dedupe onCreate -> ' + n);
}
