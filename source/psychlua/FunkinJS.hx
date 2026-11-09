package psychlua;

import backend.Paths;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

class FunkinJS
{
	/** 认领的扩展名。 */
	public static inline var EXTENSION:String = '.js';

	// ───────────────────────────────────────────────────────────────────────────
	//  JavaScriptUtils.hx 完整性校验
	//
	//  那个文件里装的是 issue 全文，属于"证据"。谁动了它 —— 哪怕只是改个空格、
	//  调个换行 —— 游戏启动时立刻抛异常退出。不静默、不降级、不打日志然后继续跑。
	//
	//  要合法修改内容的话，改完记得同步下面的 UTILS_FNV：
	//      python .workbuddy/hash_utils.py
	//  否则下次启动就是黑屏 + 崩溃报告，别怪没人提醒。
	// ───────────────────────────────────────────────────────────────────────────
	static inline var UTILS_FNV:Int = 0x692816E4;
	static inline var UTILS_REL:String = 'source/psychlua/JavaScriptUtils.hx';

	/**
	 * 校验 JavaScriptUtils.hx 有没有被动过。
	 * 找不到源码文件时直接放行 —— 发行版里本来就没有 source 目录，
	 * 那种情况下唯一能做的判断就是"没得判"。
	 */
	public static function verifyUtilsIntegrity():Void
	{
		var path:String = findUtilsSource();
		if(path == null)
		{
			trace('[integrity] JavaScriptUtils.hx not found, skip (this is normal for a release build)');
			return;
		}

		var actual:Int = fnv1a(File.getContent(path));
		if(actual == UTILS_FNV)
		{
			trace('[integrity] JavaScriptUtils.hx ok');
			return;
		}

		var msg:String = 'JavaScriptUtils.hx has been modified.\n'
			+ 'expected 0x' + StringTools.hex(UTILS_FNV, 8) + '\n'
			+ 'actual   0x' + StringTools.hex(actual, 8) + '\n'
			+ 'The issue archive is evidence, not a sandbox. Put it back.';

		trace('[integrity] ' + msg);

		// throw 会被 lime 的全局异常处理接住然后继续跑，达不到"干崩"的效果，
		// 所以这里直接把进程终止掉。
		#if sys
		Sys.exit(1);
		#end

		throw msg;
	}

	static function findUtilsSource():String
	{
		#if sys
		var candidates:Array<String> = [
			UTILS_REL,
			'../' + UTILS_REL,
			'../../' + UTILS_REL,
			'../../../' + UTILS_REL,
			'../../../../' + UTILS_REL
		];
		for (c in candidates)
			if(FileSystem.exists(c)) return c;
		#end
		return null;
	}

	/** FNV-1a 31 位，先统一换行符，免得 CRLF / LF 之间来回吵。 */
	static function fnv1a(content:String):Int
	{
		var bytes:haxe.io.Bytes = haxe.io.Bytes.ofString(content.split('\r\n').join('\n'));
		var h:Int = 0x811c9dc5;

		for (i in 0...bytes.length)
		{
			h = h ^ bytes.get(i);
			h = h * 0x01000193;
		}
		return h & 0x7FFFFFFF;
	}

	/**
	 * 把 JS 变成 Lua。
	 *
	 * 只处理"代码块"的花括号：
	 *   function f() { ... }      →  function f() ... end
	 *   if (x) { ... }            →  if (x) ... end
	 *   else { ... }              →  else ... end
	 *
	 * 以下内容原样保留，不会被误伤：
	 *   字符串里的 { }             'hi {0}'       → 不动
	 *   对象字面量                 {a: 1, b: 2}   → 不动
	 *   行注释里的 { }             // {}           → 不动
	 *
	 * 判断依据是 `{` 前面那个非空白字符：`)` `{` `;` 或 else/try/do/finally 结尾 = 代码块，
	 * `=` `(` `[` `,` `:` = 对象字面量。
	 */
	public static function transpile(code:String):String
	{
		if(code == null) return null;

		var out:StringBuf = new StringBuf();
		var blockStack:Array<Bool> = [];  // true = 代码块，false = 对象字面量
		var quoteChar:Int = 0;            // 当前字符串引号字符码，0 = 不在字符串里
		var i:Int = 0;
		var length:Int = code.length;

		while(i < length)
		{
			var ch:String = code.charAt(i);
			var cc:Int = code.charCodeAt(i);

			// 字符串内部：原样拷贝，遇到同类引号才结束（跳过转义）
			if(quoteChar != 0)
			{
				out.add(ch);
				if(cc == quoteChar && (i == 0 || code.charCodeAt(i - 1) != 92))
					quoteChar = 0;
				i++;
				continue;
			}

			// 字符串开始
			if(ch == '"' || ch == "'" || ch == '`')
			{
				quoteChar = cc;
				out.add(ch);
				i++;
				continue;
			}

			// 行注释：// 转成 --，里面的花括号不碰
			if(ch == '/' && i + 1 < length && code.charAt(i + 1) == '/')
			{
				out.add('--');
				i += 2;
				while(i < length && code.charAt(i) != '\n')
				{
					out.add(code.charAt(i));
					i++;
				}
				continue;
			}

			if(ch == '{')
			{
				var isBlock:Bool = isCodeBlock(code, i);
				blockStack.push(isBlock);
				if(!isBlock) out.add('{');
				else
				{
					// if (x) { 光把 { 删掉是 if (x) ... end，Lua 不认，得补上 then / do
					var opener:String = blockOpener(code, i);
					if(opener.length > 0) out.add(opener);
				}
				i++;
				continue;
			}

			if(ch == '}')
			{
				var isBlock:Bool = (blockStack.length > 0) ? blockStack.pop() : true;
				if(!isBlock)
				{
					out.add('}');
					i++;
					continue;
				}

				// `} else if (x) {` 不能翻成 `end else if ... end`（Lua 里 end 后面不能挂 else），
				// 得是 `elseif (x) then`；`} else {` 则是 `else`，此时那个块不写 end。
				var peek:Int = skipSpaces(code, i + 1);
				if(matchWord(code, peek, 'else'))
				{
					var afterElse:Int = skipSpaces(code, peek + 4);
					if(matchWord(code, afterElse, 'if'))
					{
						out.add('elseif');
						i = afterElse + 2;
					}
					else
					{
						out.add('else');
						i = peek + 4;
					}
					continue;
				}

				out.add('end');
				i++;
				continue;
			}

			out.add(ch);
			i++;
		}

		return out.toString();
	}

	/** 判断这个 `{` 是代码块还是对象字面量。 */
	static function isCodeBlock(code:String, bracePos:Int):Bool	{
		var i:Int = bracePos - 1;
		while(i >= 0)
		{
			var ch:String = code.charAt(i);
			if(ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r')
			{
				i--;
				continue;
			}
			break;
		}
		if(i < 0) return true;

		var prev:String = code.charAt(i);

		// f() {  /  if (...) {  /  嵌套块
		if(prev == ')' || prev == '{' || prev == ';') return true;

		// = {   ( {   [ {   , {   : {  → 对象字面量
		if(prev == '=' || prev == '(' || prev == '[' || prev == ',' || prev == ':') return false;

		// 关键字结尾（else / try / do / finally）→ 代码块
		var word:StringBuf = new StringBuf();
		var j:Int = i;
		while(j >= 0)
		{
			var c:Int = code.charCodeAt(j);
			var isWordChar:Bool = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || (c >= 48 && c <= 57);
			if(!isWordChar) break;
			word.add(code.charAt(j));
			j--;
		}
		var chars:Array<String> = word.toString().split('');
		chars.reverse();
		var kw:String = chars.join('').toLowerCase();
		return kw == 'else' || kw == 'try' || kw == 'do' || kw == 'finally';
	}

	/**
	 * 代码块前面该补什么关键字。`if (x) {` 在 Lua 里是 `if (x) then`，
	 * `while (x) {` 是 `while (x) do`，别的（function / else / try）本来就不用补。
	 *
	 * 只看括号前那个词，所以 `else if (x) {` 也能认成 if。
	 * 表达式里出现字符串带括号的情况没处理，够用就行。
	 */
	static function blockOpener(code:String, bracePos:Int):String
	{
		var i:Int = bracePos - 1;
		while(i >= 0 && isSpaceChar(code.charAt(i))) i--;
		if(i < 0) return '';

		if(code.charAt(i) == ')')
		{
			var depth:Int = 0;
			var j:Int = i;
			while(j >= 0)
			{
				var c:String = code.charAt(j);
				if(c == ')') depth++;
				else if(c == '(')
				{
					depth--;
					if(depth == 0) break;
				}
				j--;
			}
			if(j < 0) return '';
			i = j - 1;
		}

		// `if (x) {` 里 `if` 和 `(` 之间有空格，往回读完关键字前先跳过
		while(i >= 0 && isSpaceChar(code.charAt(i))) i--;

		var end:Int = i;
		while(i >= 0 && isWordChar(code.charCodeAt(i))) i--;
		if(end < i + 1) return '';

		var word:String = code.substring(i + 1, end + 1).toLowerCase();
		return switch(word)
		{
			case 'if' | 'elseif': ' then';
			case 'while' | 'for': ' do';
			default: '';
		}
	}

	static inline function isSpaceChar(ch:String):Bool
		return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';

	static inline function isWordChar(c:Int):Bool
		return (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || (c >= 48 && c <= 57);

	static function skipSpaces(code:String, from:Int):Int
	{
		var i:Int = from;
		while(i < code.length && isSpaceChar(code.charAt(i))) i++;
		return i;
	}

	/** 从 at 开始是不是一个完整的单词（后面不接标识符字符），不分大小写。 */
	static function matchWord(code:String, at:Int, word:String):Bool
	{
		if(at < 0 || at + word.length > code.length) return false;
		if(code.substr(at, word.length).toLowerCase() != word) return false;
		var next:Int = at + word.length;
		if(next < code.length && isWordChar(code.charCodeAt(next))) return false;
		return true;
	}

	/**
	 * 加载并执行一个 .js 脚本。
	 * 解析路径、去重、转译、然后把结果当 Lua 跑。
	 */
	public static function start(jsPath:String, ?playState:states.PlayState):FunkinLua
	{
		#if MODS_ALLOWED
		if(!FileSystem.exists(jsPath)) return null;

		for (script in states.PlayState.instance.luaArray)
			if(script.scriptName == jsPath) return null;

		var raw:String = File.getContent(jsPath);
		var luaSource:String = transpile(raw);

		// scriptName keeps the .js path so logs stay readable; the actual source
		// handed to the interpreter is the transpiled text.
		return new FunkinLua(jsPath, luaSource);
		#else
		return null;
		#end
	}

	/** 给调用方用的便捷判断。 */
	public static inline function isJSFile(path:String):Bool
		return path != null && path.toLowerCase().endsWith(EXTENSION);
}
