// FunkinJS 冒烟测试：这个文件会被转译成 lua 再执行（花括号换 end）
// 注意：转译层不处理分号 / let / const / 箭头函数 / switch
// onCreate 比 onCreatePost 早，这样 lua 那边检查时结果已经写好了

function onCreate() {
    setVar('js_probe_var', 'js-ok')

    if (getVar('js_probe_var') == 'nope') {
        setVar('js_branch', 'wrong')
    } else if (getVar('js_probe_var') == 'js-ok') {
        setVar('js_branch', 'elseif')
    } else {
        setVar('js_branch', 'else')
    }

    if (getVar('js_branch') == 'elseif') {
        saveFile('@@ROOT@@/.workbuddy/testout/js_seen.txt', 'js-ok', true)
    }
}

function onUpdatePost(elapsed) {
    if (elapsed > 0) {
        setVar('js_update_ran', true)
    }
}
