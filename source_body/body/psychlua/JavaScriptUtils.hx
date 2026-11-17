package psychlua;

/**
 * FunkinJS transpiler - notes.
 *
 * The engine "supports" JavaScript by deleting every `{` and turning `}` into `end`,
 * then handing the whole file to the Lua interpreter. There is no V8, no QuickJS, no
 * AST and no JavaScript on this path. The idea comes from PE-QuickJs-Engine, which
 * exposed 124 methods named after Lua's and let the Lua runtime do the work.
 *
 * Side effects: object literals, plain blocks, destructuring, arrow functions and
 * template strings all fall apart. That is not a bug here - it matches the original
 * engine's behaviour.
 *
 * This file has no code on purpose. It is the anchor for
 * `FunkinJS.verifyUtilsIntegrity()`: the hash in that class is computed over this
 * file's text, so editing anything here means updating `UTILS_FNV` in the same commit.
 * The long version of these notes, plus the issue archive they came from, lives in
 * `docs/JS_TRANSPILE_HISTORY.md`.
 *
 * Implementation notes:
 *  1. Line comments, semicolons and let/const are left alone - only real JS needs those.
 *  2. Transpiled scripts go through FunkinLua's dostring path but keep the .js path as
 *     scriptName, so logs still show which file is running.
 *  3. Loading a .lua first looks for a same-named .js as a fallback, so mod authors do
 *     not have to change any call site.
 */
class JavaScriptUtils
{
}
