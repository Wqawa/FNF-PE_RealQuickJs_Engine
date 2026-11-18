-- 隔离回归：脚本查找的四条入口必须命中同一个文件；类解析不能拿到另一棵树。
--
-- 这些断言以前全是坏的，只是没人测：
--   * isRunning 走的是 FunkinLua.findScript -> Paths.getPath，少了 assets/<ver>/ 根兜底，
--     而 notetype 脚本正是从那里加载的，于是"明明在跑"被判成 false；
--   * isRunning 是字符串直比，Windows 下大小写不同就当成两个脚本；
--   * getPropertyFromClass('vanilla.*') 能拿到另一棵树的类，那个类的 Paths 指向 assets/body。

local OUT = '@@ROOT@@/.workbuddy/testout/isolation.txt'
local lines = {}
local failed = 0

local function dump()
	saveFile(OUT, table.concat(lines, '\n') .. '\n', true)
end

local function rec(status, name, detail)
	lines[#lines + 1] = status .. '|' .. name .. (detail ~= nil and ('|' .. tostring(detail)) or '')
	if status == 'FAIL' or status == 'ERR' then failed = failed + 1 end
	dump()
end

local function t(name, fn)
	local ok, res = pcall(fn)
	if not ok then
		rec('ERR', name, res)
	elseif res == false or res == nil then
		rec('FAIL', name)
	else
		rec('PASS', name, (res ~= true) and res or nil)
	end
end

function onCreatePost()
	-- 资源前缀：body 树必须读 assets/body，改错了这里第一个报警
	t('paths_version', function()
		return getPropertyFromClass('Paths', 'VERSION_DIR') == 'body'
	end)

	-- 别棵树的类必须拿不到（以前能拿到，拿到的类内部 Paths 指向 assets/1.0.4）
	t('foreign_class_rejected', function()
		local ok, v = pcall(function()
			return getPropertyFromClass('vanilla.backend.Paths', 'VERSION_DIR')
		end)
		return (not ok) or v == nil
	end)

	-- notetype 脚本从 assets/body/custom_notetypes 加载（没有 shared 这一层）
	t('is_running_root_path', function()
		return isRunning('custom_notetypes/luatestnote.lua') == true
	end)
	-- 同一个文件，大小写不同也必须是"在跑"
	t('is_running_case', function()
		return isRunning('CUSTOM_NOTETYPES/LUATESTNOTE.LUA') == true
	end)
	t('is_running_missing', function()
		return isRunning('nope/does_not_exist.lua') == false
	end)

	-- scripts/ 目录扫出来的 hscript：isRunning 认得到，addHScript 不会再建一份
	t('is_running_scripts_folder', function()
		return isRunning('scripts/probe_dedupe.hx') == true
	end)
	do
		local before = getVar('probe_hx_creates')
		addHScript('scripts/probe_dedupe.hx')
		local after = getVar('probe_hx_creates')
		rec((after == 1) and 'PASS' or 'FAIL', 'add_hscript_dedupe',
			'before=' .. tostring(before) .. ' after=' .. tostring(after))
	end

	-- hscript 的 (%run_v_x) 版本标记
	t('hscript_version_tagged', function()
		return getVar('hx_version_tagged') == '0.7.3'
	end)
	t('hscript_version_plain', function()
		local real = getPropertyFromClass('MainMenuState', 'psychEngineVersion')
		return getVar('hx_version_plain') == real
	end)
	-- 直接读静态字段拿不到伪装值（Interp.get 是模块私有，没钩子），
	-- 所以额外给了个同名全局，带标记的脚本读它就是标记值。
	t('hscript_pe_version_tagged', function()
		return getVar('hx_pe_version_tagged') == '0.7.3'
	end)
	t('hscript_pe_version_plain', function()
		local real = getPropertyFromClass('MainMenuState', 'psychEngineVersion')
		return getVar('hx_pe_version_plain') == real
	end)

	-- 卸载之后实例要从 hscriptArray 里摘掉，isRunning 立刻变 false
	do
		removeHScript('scripts/probe_dedupe.hx')
		rec(isRunning('scripts/probe_dedupe.hx') == false and 'PASS' or 'FAIL', 'remove_hscript')
	end

	rec('SUMMARY', failed == 0 and 'OK' or 'FAILED', failed)
end
