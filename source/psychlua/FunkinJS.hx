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
	 * 按顺序跑几遍扫描，每一遍只负责一种语法，字符串和注释全程原样跳过：
	 *
	 *   1. 模板字符串   `hi ${name}`        → ("hi " .. tostring(name))
	 *   2. 箭头函数     (a) => a * 2        → function(a) return a * 2 end
	 *   3. C 风格 for   for (i = 0; i < 4; i++) → do local i = 0 while i < 4 do ... end end
	 *   4. 对象字面量   {a: 1, b: 2}        → {a = 1, b = 2}
	 *   5. 运算符       === / !==           → == / ~=
	 *   6. let / const  let x = 1           → local x = 1
	 *   7. 花括号       { ... }             → ... end（代码块）/ 原样（对象）
	 *
	 * 每遍都是"扫描 + 重写"，不做正则替换，所以字符串里的 `=>`、注释里的 `{`
	 * 不会被误伤。class 保持原样（让它在 Lua 侧明确报语法错，好过静默错乱）。
	 */
	public static function transpile(code:String):String
	{
		if(code == null) return null;

		var s:String = code;
		s = passTemplateStrings(s);
		s = passArrows(s);
		s = passForLoops(s);
		s = passCompoundAssign(s);
		s = passObjectLiterals(s);
		s = passOperators(s);
		s = passLetConst(s);
		s = passBraces(s);
		return s;
	}

	// ── 扫描工具 ─────────────────────────────────────────────────────────────

	/** i 指向引号（' " `），返回结束引号之后的位置。 */
	static function skipStringEnd(code:String, i:Int):Int
	{
		var q:Int = code.charCodeAt(i);
		var j:Int = i + 1;
		while(j < code.length)
		{
			var c:Int = code.charCodeAt(j);
			if(c == 92) { j += 2; continue; }
			if(c == q) return j + 1;
			j++;
		}
		return j;
	}

	static function skipLineCommentEnd(code:String, i:Int):Int
	{
		var j:Int = i;
		while(j < code.length && code.charCodeAt(j) != 10) j++;
		return j;
	}

	static function skipBlockCommentEnd(code:String, i:Int):Int
	{
		var j:Int = i + 2;
		while(j + 1 < code.length)
		{
			if(code.charCodeAt(j) == 42 && code.charCodeAt(j + 1) == 47) return j + 2;
			j++;
		}
		return code.length;
	}

	/** i 在字符串/注释起点就返回跳过后的位置，否则原样返回 i。 */
	static function skipLiteral(code:String, i:Int):Int
	{
		if(i >= code.length) return i;
		var c:Int = code.charCodeAt(i);
		if(c == 34 || c == 39) return skipStringEnd(code, i);
		if(c == 47 && i + 1 < code.length)
		{
			var n:Int = code.charCodeAt(i + 1);
			if(n == 47) return skipLineCommentEnd(code, i);
			if(n == 42) return skipBlockCommentEnd(code, i);
		}
		return i;
	}

	/** 把一段普通文本转成 Lua 双引号字符串。 */
	static function quoteLua(s:String):String
	{
		var out:StringBuf = new StringBuf();
		out.add('"');
		for(i in 0...s.length)
		{
			var ch:String = s.charAt(i);
			if(ch == '\\') out.add('\\\\');
			else if(ch == '"') out.add('\\"');
			else if(ch == '\n') out.add('\\n');
			else if(ch == '\r') out.add('\\r');
			else out.add(ch);
		}
		out.add('"');
		return out.toString();
	}

	// ── 1. 模板字符串 ────────────────────────────────────────────────────────

	static function passTemplateStrings(code:String):String
	{
		if(code.indexOf('`') < 0) return code;

		var out:String = '';
		var i:Int = 0;
		while(i < code.length)
		{
			var c:Int = code.charCodeAt(i);
			if(c == 96)
			{
				var r = emitTemplate(code, i);
				out += r.text;
				i = r.next;
				continue;
			}

			var skip:Int = skipLiteral(code, i);
			if(skip > i) { out += code.substring(i, skip); i = skip; continue; }
			out += code.charAt(i);
			i++;
		}
		return out;
	}

	static function emitTemplate(code:String, start:Int):{text:String, next:Int}
	{
		var pieces:Array<String> = [];
		var cur:StringBuf = new StringBuf();
		var i:Int = start + 1;

		while(i < code.length)
		{
			var c:Int = code.charCodeAt(i);
			if(c == 96) { i++; break; }

			if(c == 92 && i + 1 < code.length)
			{
				var n:String = code.charAt(i + 1);
				if(n == 'n') cur.add('\n');
				else if(n == 't') cur.add('\t');
				else if(n == 'r') cur.add('\r');
				else cur.add(n);
				i += 2;
				continue;
			}

			if(c == 36 && i + 1 < code.length && code.charCodeAt(i + 1) == 123)
			{
				var j:Int = i + 2;
				var depth:Int = 1;
				while(j < code.length && depth > 0)
				{
					var d:Int = code.charCodeAt(j);
					if(d == 123) { depth++; j++; continue; }
					if(d == 125) { depth--; j++; continue; }

					var skip:Int = skipLiteral(code, j);
					if(skip > j) { j = skip; continue; }
					j++;
				}
				var expr:String = code.substring(i + 2, j - 1);
				if(cur.length > 0) { pieces.push(quoteLua(cur.toString())); cur = new StringBuf(); }
				pieces.push('tostring(' + expr + ')');
				i = j;
				continue;
			}

			cur.add(code.charAt(i));
			i++;
		}

		if(cur.length > 0) pieces.push(quoteLua(cur.toString()));
		if(pieces.length == 0) pieces.push('""');

		return {text: '(' + pieces.join(' .. ') + ')', next: i};
	}

	// ── 2. 箭头函数 ──────────────────────────────────────────────────────────

	static function passArrows(code:String):String
	{
		if(code.indexOf('=>') < 0) return code;

		var out:String = '';
		var i:Int = 0;
		while(i < code.length)
		{
			var skip:Int = skipLiteral(code, i);
			if(skip > i) { out += code.substring(i, skip); i = skip; continue; }

			var c:Int = code.charCodeAt(i);
			if(c == 61 && i + 1 < code.length && code.charCodeAt(i + 1) == 62)
			{
				// 向前找参数：`)` 结尾就是括号列表，否则是单个标识符。
				// `=>` 前面可能有空格（`(a, b) => ...`），截断 out 时要把这些空格也减掉。
				var tail:Int = i - 1;
				var tailSpaces:Int = 0;
				while(tail >= 0 && isSpaceChar(code.charAt(tail))) { tailSpaces++; tail--; }

				var back:Int = i - 1;
				while(back >= 0 && isSpaceChar(code.charAt(back))) back--;

				var params:String = null;
				var cut:Int = 0;
				if(back >= 0 && code.charAt(back) == ')')
				{
					var depth:Int = 0;
					var j:Int = back;
					while(j >= 0)
					{
						var d:String = code.charAt(j);
						if(d == ')') depth++;
						else if(d == '(')
						{
							depth--;
							if(depth == 0) break;
						}
						j--;
					}
					if(j >= 0) { params = code.substring(j, back + 1); cut = out.length - tailSpaces - (back + 1 - j); }
				}
				else
				{
					var j:Int = back;
					while(j >= 0 && isWordChar(code.charCodeAt(j))) j--;
					if(j < back) { params = '(' + code.substring(j + 1, back + 1) + ')'; cut = out.length - tailSpaces - (back + 1 - (j + 1)); }
				}

				if(params != null && cut >= 0)
				{
					out = out.substring(0, cut);
					var after:Int = skipSpaces(code, i + 2);
					if(after < code.length && code.charAt(after) == '{')
					{
						// 块体：交给花括号那一步把 { } 变成 end（function 不会补 then/do）
						out += 'function' + params;
						i = after;
						continue;
					}

					// 表达式体：找到这一层的结束位置，补 return ... end
					var end:Int = findArrowExprEnd(code, after);
					out += 'function' + params + ' return ' + code.substring(after, end) + ' end';
					i = end;
					continue;
				}
			}

			out += code.charAt(i);
			i++;
		}
		return out;
	}

	/** 表达式体的结束位置：同层的 , ) ; } 或换行。 */
	static function findArrowExprEnd(code:String, from:Int):Int
	{
		var i:Int = from;
		var paren:Int = 0;
		var bracket:Int = 0;
		while(i < code.length)
		{
			var skip:Int = skipLiteral(code, i);
			if(skip > i) { i = skip; continue; }

			var c:Int = code.charCodeAt(i);
			if(c == 10) break;
			if(c == 40) paren++;
			else if(c == 41) { if(paren == 0) break; paren--; }
			else if(c == 91) bracket++;
			else if(c == 93) { if(bracket == 0) break; bracket--; }
			else if((c == 44 || c == 59 || c == 125) && paren == 0 && bracket == 0) break;
			i++;
		}
		return i;
	}

	// ── 3. C 风格 for ────────────────────────────────────────────────────────

	static function passForLoops(code:String):String
	{
		if(code.indexOf('for') < 0) return code;

		var out:String = '';
		var i:Int = 0;
		while(i < code.length)
		{
			var skip:Int = skipLiteral(code, i);
			if(skip > i) { out += code.substring(i, skip); i = skip; continue; }

			if(matchWord(code, i, 'for'))
			{
				var open:Int = skipSpaces(code, i + 3);
				if(open < code.length && code.charAt(open) == '(')
				{
					var close:Int = matchParen(code, open);
					if(close > open)
					{
						var head:String = code.substring(open + 1, close);
						var parts:Array<String> = splitTopLevel(head, ';');
						if(parts.length == 3 && parts[0].length > 0)
						{
							var bodyStart:Int = skipSpaces(code, close + 1);
							if(bodyStart < code.length && code.charAt(bodyStart) == '{')
							{
								var bodyEnd:Int = matchBrace(code, bodyStart);
								if(bodyEnd > bodyStart)
								{
									var body:String = code.substring(bodyStart + 1, bodyEnd);
									var init:String = normalizeForInit(parts[0]);
									var step:String = normalizeForStep(parts[2]);
									out += 'do ' + init + ' while ' + parts[1].trim() + ' do '
										+ body + ' ' + step + ' end end';
									i = bodyEnd + 1;
									continue;
								}
							}
						}
					}
				}
			}

			out += code.charAt(i);
			i++;
		}
		return out;
	}

	static function normalizeForInit(s:String):String
	{
		var t:String = s.trim();
		if(t.startsWith('var ')) t = 'local ' + t.substr(4);
		else if(t.startsWith('let ')) t = 'local ' + t.substr(4);
		else if(t.startsWith('const ')) t = 'local ' + t.substr(6);
		return t;
	}

	static function normalizeForStep(s:String):String
	{
		var t:String = s.trim();
		if(t.endsWith('++')) return t.substr(0, t.length - 2).trim() + ' = ' + t.substr(0, t.length - 2).trim() + ' + 1';
		if(t.endsWith('--')) return t.substr(0, t.length - 2).trim() + ' = ' + t.substr(0, t.length - 2).trim() + ' - 1';
		var plusEq:Int = t.indexOf('+=');
		if(plusEq > 0) return t.substr(0, plusEq).trim() + ' = ' + t.substr(0, plusEq).trim() + ' + ' + t.substr(plusEq + 2);
		var minusEq:Int = t.indexOf('-=');
		if(minusEq > 0) return t.substr(0, minusEq).trim() + ' = ' + t.substr(0, minusEq).trim() + ' - ' + t.substr(minusEq + 2);
		return t;
	}

	/** 从 open（指向 `(`）找到匹配的 `)`。 */
	static function matchParen(code:String, open:Int):Int
	{
		var depth:Int = 0;
		var i:Int = open;
		while(i < code.length)
		{
			var skip:Int = skipLiteral(code, i);
			if(skip > i) { i = skip; continue; }
			var c:Int = code.charCodeAt(i);
			if(c == 40) depth++;
			else if(c == 41) { depth--; if(depth == 0) return i; }
			i++;
		}
		return -1;
	}

	/** 从 open（指向 `{`）找到匹配的 `}`。 */
	static function matchBrace(code:String, open:Int):Int
	{
		var depth:Int = 0;
		var i:Int = open;
		while(i < code.length)
		{
			var skip:Int = skipLiteral(code, i);
			if(skip > i) { i = skip; continue; }
			var c:Int = code.charCodeAt(i);
			if(c == 123) depth++;
			else if(c == 125) { depth--; if(depth == 0) return i; }
			i++;
		}
		return -1;
	}

	/** 按顶层分隔符切分（忽略括号/方括号/字符串里的）。 */
	static function splitTopLevel(s:String, sep:String):Array<String>
	{
		var parts:Array<String> = [];
		var start:Int = 0;
		var depth:Int = 0;
		var i:Int = 0;
		while(i < s.length)
		{
			var skip:Int = skipLiteral(s, i);
			if(skip > i) { i = skip; continue; }
			var c:String = s.charAt(i);
			if(c == '(' || c == '[' || c == '{') depth++;
			else if(c == ')' || c == ']' || c == '}') depth--;
			else if(c == sep && depth == 0)
			{
				parts.push(s.substring(start, i));
				start = i + 1;
			}
			i++;
		}
		parts.push(s.substring(start));
		return parts;
	}

	// ── 4. 对象字面量 ────────────────────────────────────────────────────────

	static function passObjectLiterals(code:String):String
	{
		var out:String = '';
		var i:Int = 0;
		while(i < code.length)
		{
			var skip:Int = skipLiteral(code, i);
			if(skip > i) { out += code.substring(i, skip); i = skip; continue; }

			var c:Int = code.charCodeAt(i);
			if(c == 123 && !isCodeBlock(code, i))
			{
				var close:Int = matchBrace(code, i);
				if(close > i)
				{
					out += '{' + rewriteObjectBody(code.substring(i + 1, close)) + '}';
					i = close + 1;
					continue;
				}
			}

			out += code.charAt(i);
			i++;
		}
		return out;
	}

	/**
	 * 把对象 body 里顶层的 `key:` 换成 `key =`，顺便把简写 `{a, b}` 补成 `{a = a, b = b}`。
	 * 嵌套对象递归处理。
	 */
	static function rewriteObjectBody(body:String):String
	{
		var out:String = '';
		var i:Int = 0;
		var depth:Int = 0;
		while(i < body.length)
		{
			var skip:Int = skipLiteral(body, i);
			if(skip > i) { out += body.substring(i, skip); i = skip; continue; }

			var c:String = body.charAt(i);
			if(c == '{')
			{
				var close:Int = matchBrace(body, i);
				if(close > i)
				{
					out += '{' + rewriteObjectBody(body.substring(i + 1, close)) + '}';
					i = close + 1;
					continue;
				}
			}
			if(c == '(' || c == '[') depth++;
			else if(c == ')' || c == ']') depth--;

			// 顶层（depth 0）的 `标识符:` → `标识符 =`
			if(c == ':' && depth == 0)
			{
				var back:Int = out.length - 1;
				while(back >= 0 && isSpaceChar(out.charAt(back))) back--;
				if(back >= 0 && out.charAt(back) == '>' ) { out += c; i++; continue; } // 不是箭头（保险）

				var j:Int = i - 1;
				while(j >= 0 && isSpaceChar(body.charAt(j))) j--;
				var wordEnd:Int = j;
				while(j >= 0 && isWordChar(body.charCodeAt(j))) j--;
				if(wordEnd >= j + 1)
					out = out.substring(0, back + 1) + ' =';
				else out += c;
				i++;
				continue;
			}

			// 简写属性 `{a, b}`：顶层逗号前是裸标识符，且它已经在 out 里
			if(c == ',')
			{
				if(depth == 0)
				{
					var back:Int = out.length - 1;
					while(back >= 0 && isSpaceChar(out.charAt(back))) back--;
					var wordEnd:Int = back;
					while(back >= 0 && isWordChar(out.charCodeAt(back))) back--;
					if(wordEnd > back && back >= 0 && (out.charAt(back) == '{' || out.charAt(back) == ','))
					{
						var word:String = out.substring(back + 1, wordEnd + 1);
						if(!isLuaKeyword(word)) out += ' = ' + word;
					}
				}
			}

			out += body.charAt(i);
			i++;
		}
		return out;
	}

	static function isLuaKeyword(w:String):Bool
	{
		return switch(w)
		{
			case 'and' | 'break' | 'do' | 'else' | 'elseif' | 'end' | 'false' | 'for' | 'function'
				| 'if' | 'in' | 'local' | 'nil' | 'not' | 'or' | 'repeat' | 'return'
				| 'then' | 'true' | 'until' | 'while': true;
			default: false;
		}
	}

	// ── 5. 复合赋值 x += y ────────────────────────────────────────────────────

	static function passCompoundAssign(code:String):String
	{
		if(code.indexOf('+=') < 0 && code.indexOf('-=') < 0 && code.indexOf('*=') < 0 && code.indexOf('/=') < 0) return code;

		var out:String = '';
		var i:Int = 0;
		while(i < code.length)
		{
			var skip:Int = skipLiteral(code, i);
			if(skip > i) { out += code.substring(i, skip); i = skip; continue; }

			var two:String = code.substr(i, 2);
			if(two == '+=' || two == '-=' || two == '*=' || two == '/=')
			{
				var op:String = two.charAt(0);
				var back:Int = out.length - 1;
				while(back >= 0 && isSpaceChar(out.charAt(back))) back--;

				// 往左吃一个左值：标识符 + 连续的 .name 或 [..]
				var ls:Int = back;
				while(ls >= 0)
				{
					var ch:String = out.charAt(ls);
					if(isWordChar(out.charCodeAt(ls)) || ch == '.') { ls--; continue; }
					if(ch == ']')
					{
						var d:Int = 1;
						ls--;
						while(ls >= 0 && d > 0)
						{
							var q:String = out.charAt(ls);
							if(q == ']') d++;
							else if(q == '[') d--;
							ls--;
						}
						continue;
					}
					break;
				}
				ls++;

				if(ls <= back)
				{
					var lhs:String = out.substring(ls, back + 1).trim();
					if(lhs.length > 0 && !isLuaKeyword(lhs))
					{
						out += '= ' + lhs + ' ' + op + ' ';
						i += 2;
						continue;
					}
				}
			}

			out += code.charAt(i);
			i++;
		}
		return out;
	}

	// ── 6. 运算符 ────────────────────────────────────────────────────────────
	static function passOperators(code:String):String
	{
		if(code.indexOf('===') < 0 && code.indexOf('!==') < 0) return code;

		var out:String = '';
		var i:Int = 0;
		while(i < code.length)
		{
			var skip:Int = skipLiteral(code, i);
			if(skip > i) { out += code.substring(i, skip); i = skip; continue; }

			if(code.substr(i, 3) == '===') { out += '=='; i += 3; continue; }
			if(code.substr(i, 3) == '!==') { out += '~='; i += 3; continue; }
			if(code.substr(i, 2) == '!=') { out += '~='; i += 2; continue; }
			if(code.substr(i, 2) == '&&') { out += 'and'; i += 2; continue; }
			if(code.substr(i, 2) == '||') { out += 'or'; i += 2; continue; }

			out += code.charAt(i);
			i++;
		}
		return out;
	}

	// ── 6. let / const ───────────────────────────────────────────────────────

	static function passLetConst(code:String):String
	{
		if(code.indexOf('let ') < 0 && code.indexOf('const ') < 0 && code.indexOf('var ') < 0) return code;

		var out:String = '';
		var i:Int = 0;
		while(i < code.length)
		{
			var skip:Int = skipLiteral(code, i);
			if(skip > i) { out += code.substring(i, skip); i = skip; continue; }

			if(isWordChar(code.charCodeAt(i)))
			{
				var j:Int = i;
				while(j < code.length && isWordChar(code.charCodeAt(j))) j++;
				var word:String = code.substring(i, j);
				if((word == 'let' || word == 'const' || word == 'var') && j < code.length && isSpaceChar(code.charAt(j)))
				{
					out += 'local';
					i = j;
					continue;
				}
				out += word;
				i = j;
				continue;
			}

			out += code.charAt(i);
			i++;
		}
		return out;
	}

	// ── 7. 花括号 → do / end ─────────────────────────────────────────────────

	static function passBraces(code:String):String
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

		// Gameplay → JS Engine 选了 QuickJS 就走真运行时，不转译、不进 Lua 解释器。
		// 以前这里无条件下面的 transpile，所以任何带 `+` 拼接的 JS 都会变成
		// 「unexpected symbol near '+'」——报错还挂着 "lua script"，很容易看错。
		if(ClientPrefs.data.jsEngine == 'QuickJS')
		{
			jsruntime.JSPlayer.loadFile(jsPath);
			return null;
		}

		for (script in states.PlayState.instance.luaArray)
			if(script.scriptName == jsPath) return null;

		var raw:String = File.getContent(jsPath);
		var luaSource:String = transpile(raw);
		#if desktop
		if(Sys.getEnv('PE_JS_DUMP') == '1') File.saveContent(jsPath + '.transpiled.txt', luaSource);
		#end

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
