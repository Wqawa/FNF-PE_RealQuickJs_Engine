// 新语法冒烟测试：let / const / 箭头函数 / C 风格 for / === / 模板字符串 / 对象字面量 / +=
// 结果写到 .workbuddy/testout/jssyntax.txt
let who = 'probe';
const BASE = 10;
var count = 0;

function onCreate() {
    let tpl = `hi ${who} ${BASE}`;
    setVar('t_tpl', tpl);

    let strict = 'bad';
    if (who === 'probe') {
        strict = 'ok';
    }
    setVar('t_strict', strict);

    let arrow = (a, b) => a + b;
    let sum = arrow(1, 2);
    setVar('t_arrow', sum);

    let arrowBlock = (x) => {
        setVar('t_block', x * 3);
    };
    arrowBlock(4);

    let total = 0;
    for (var i = 0; i < 4; i++) {
        total += i;
    }
    setVar('t_for', total);

    let obj = {a: 1, b: 2};
    let objSum = obj.a + obj.b;
    setVar('t_obj', objSum);

    if (getVar('t_tpl') == 'hi probe 10' && getVar('t_strict') == 'ok' && getVar('t_arrow') == 3
        && getVar('t_block') == 12 && getVar('t_for') == 6 && getVar('t_obj') == 3) {
        saveFile('@@ROOT@@/.workbuddy/testout/jssyntax.txt', 'PASS|js_syntax\n', true)
    } else {
        saveFile('@@ROOT@@/.workbuddy/testout/jssyntax.txt', 'FAIL|js_syntax\n', true)
    }
}
