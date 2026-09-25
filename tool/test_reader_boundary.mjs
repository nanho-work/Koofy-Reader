import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';
import assert from 'node:assert/strict';

// Exercise the actual shared Android/iOS anchor script without a browser.
// Native hosts additionally require the final publication spine item.
const script = readFileSync(new URL('../packages/koofy_reader_bridge/ios/Resources/reader_anchor.js', import.meta.url), 'utf8')
  .replaceAll('__KOOFY_RESTORE__', 'false').replaceAll('__KOOFY_ANCHOR__', 'null');
function atEnd(width, height, scrollWidth, scrollHeight, scrollX, scrollY) {
  const root = { scrollWidth, scrollHeight };
  return JSON.parse(runInNewContext(script, {
    window: { innerWidth: width, innerHeight: height, scrollX, scrollY },
    document: { scrollingElement: root, documentElement: root, body: {}, createTreeWalker: () => ({ nextNode: () => null }) },
    NodeFilter: { SHOW_TEXT: 4, FILTER_ACCEPT: 1, FILTER_REJECT: 2 },
  })).resourceEnd;
}
test('single-page and spread endings use viewport end rather than start progression', () => {
  assert.equal(atEnd(400, 600, 1200, 600, 0, 0), false);
  assert.equal(atEnd(400, 600, 1200, 600, 400, 0), false);
  assert.equal(atEnd(400, 600, 1200, 600, 800, 0), true);
  assert.equal(atEnd(800, 600, 1600, 600, 800, 0), true);
  assert.equal(atEnd(400, 600, 1200, 600, -800, 0), true);
});
test('scrolling, one-screen chapters, rounding and invalid viewports', () => {
  assert.equal(atEnd(400, 600, 400, 1800, 0, 600), false);
  assert.equal(atEnd(400, 600, 400, 1800, 0, 1200), true);
  assert.equal(atEnd(400, 600, 400, 600, 0, 0), true);
  assert.equal(atEnd(400, 600, 1200.5, 600, 800, 0), true);
  assert.equal(atEnd(0, 0, 0, 0, 0, 0), false);
});
