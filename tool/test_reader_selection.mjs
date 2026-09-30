import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const script = readFileSync(new URL('../packages/koofy_reader_bridge/ios/Resources/reader_selection.js', import.meta.url), 'utf8');
const handlers = {};
let now = 1000, selected = '', collapsed = true;
const context = vm.createContext({
  window: { getSelection: () => ({ isCollapsed: collapsed, toString: () => selected }), addEventListener() {} },
  document: { addEventListener: (name, fn) => { handlers[name] = fn; } },
  location: { pathname: '/chapter.xhtml' }, Date: { now: () => now }, JSON,
});
const read = () => JSON.parse(vm.runInContext(script, context));
assert.equal(read().active, false);
selected = 'The leaves were trembling in the wind.'; collapsed = false;
handlers.touchstart(); handlers.selectionchange();
assert.equal(read().busy, true);
now += 2000;
assert.equal(read().busy, true, 'holding a handle must not commit translation');
handlers.touchend();
assert.equal(read().busy, true);
now += 500;
assert.equal(read().busy, false);
assert.equal(read().text, selected);
selected = 'x'.repeat(10000);
assert.equal(read().text.length, 2001, 'native layer can reject oversize without copying whole selection');
collapsed = true;
assert.equal(read().text, '');
assert.equal(read().active, false);
console.log('Selection release, debounce, length limit and clear checks passed.');
