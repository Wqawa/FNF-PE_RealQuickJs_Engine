-- 自定义音符类型脚本（custom notetype）：故意放到 assets/ 根下，
-- 走的是 0.6.x 那套 getPreloadPath('assets/<file>') 的路径。
-- 只有新的 assets/ 兜底生效时，这个文件才会被加载。
local OUT = '@@ROOT@@/.workbuddy/testout/kind_notetype.txt'

function onCreate()
	saveFile(OUT, 'notetype|ok|assets-root\n', true)
end
