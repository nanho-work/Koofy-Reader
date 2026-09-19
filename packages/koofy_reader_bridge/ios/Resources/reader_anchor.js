// Runs in Readium's current resource. No page numbers or layout percentages are
// used as text identity. The quote is understood by both pinned Readium SDKs;
// the DOM point lets us check visibility without rounding to a paragraph start.
(function (anchor) {
  const width = window.innerWidth, height = window.innerHeight;
  const visible = range => Array.from(range.getClientRects()).some(r =>
    r.width > 0 && r.height > 0 && r.right > 1 && r.left < width - 1 &&
    r.bottom > 1 && r.top < height - 1);
  const range = (node, start, end) => {
    const r = document.createRange();
    r.setStart(node, start); r.setEnd(node, end); return r;
  };
  const selector = element => {
    const parts = [];
    while (element && element !== document.documentElement) {
      if (element.id) {
        parts.unshift('#' + CSS.escape(element.id)); break;
      }
      const tag = element.localName;
      let index = 1;
      for (let sibling = element.previousElementSibling; sibling; sibling = sibling.previousElementSibling)
        if (sibling.localName === tag) index++;
      parts.unshift(tag + ':nth-of-type(' + index + ')');
      element = element.parentElement;
    }
    return parts.join(' > ');
  };
  const charEnd = (text, offset) => offset + (text.codePointAt(offset) > 0xffff ? 2 : 1);
  let anchorVisible = null;
  try {
    const point = anchor && anchor.locations && anchor.locations.koofyText;
    if (point) {
      const element = document.querySelector(point.cssSelector);
      const node = element && element.childNodes[point.textNodeIndex];
      if (__KOOFY_RESTORE__ && node && node.nodeType === Node.TEXT_NODE &&
          point.charOffset >= 0 && point.charOffset < node.length) {
        const target = range(node, point.charOffset, charEnd(node.data, point.charOffset));
        if (!visible(target)) {
          // Both pinned SDKs expose scrollToId, which owns scroll mode, RTL and
          // column snapping. Give it the exact range's geometry without splitting
          // text nodes (which would invalidate persisted DOM text-node indices).
          // The hidden proxy never participates in the publication's layout.
          const proxy = document.createElement('span');
          proxy.id = 'koofy-restore-' + Math.random().toString(36).slice(2);
          proxy.hidden = true;
          proxy.getBoundingClientRect = () => target.getBoundingClientRect();
          document.body.appendChild(proxy);
          try { window.readium.scrollToId(proxy.id, false); }
          finally { proxy.remove(); }
        }
      }
      anchorVisible = !!(node && node.nodeType === Node.TEXT_NODE &&
        point.charOffset < node.length && visible(range(node, point.charOffset,
          charEnd(node.data, point.charOffset))));
    } else if (anchor && anchor.locations && anchor.locations.fragments) {
      const id = anchor.locations.fragments[0];
      const element = id && document.getElementById(id);
      if (element) {
        const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
        for (let node; (node = walker.nextNode());) {
          const offset = node.data.search(/\S/);
          if (offset < 0) continue;
          anchorVisible = visible(range(node, offset, charEnd(node.data, offset)));
          break;
        }
      }
    }
  } catch (_) { anchorVisible = false; }

  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      return node.data.trim() && !node.parentElement.closest('script,style,noscript,rt,[hidden]')
        ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
    }
  });
  for (let node; (node = walker.nextNode());) {
    if (!visible(range(node, 0, node.length))) continue;
    // Binary search for the first visible UTF-16 unit in DOM reading order.
    let low = 0, high = node.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (visible(range(node, 0, middle + 1))) high = middle;
      else low = middle + 1;
    }
    let offset = low;
    if (offset > 0 && /[\uDC00-\uDFFF]/.test(node.data[offset])) offset--;
    // Whitespace alone is a poor quote anchor. Stay in the visible text range.
    while (offset < node.length && /\s/.test(node.data[offset])) offset = charEnd(node.data, offset);
    if (offset >= node.length || !visible(range(node, offset, charEnd(node.data, offset)))) continue;
    const css = selector(node.parentElement);
    const end = charEnd(node.data, offset);
    return JSON.stringify({anchorVisible, locations: {
      cssSelector: css,
      koofyText: {cssSelector: css, textNodeIndex: Array.prototype.indexOf.call(node.parentNode.childNodes, node), charOffset: offset}
    }, text: {
      before: node.data.slice(Math.max(0, offset - 48), offset),
      highlight: node.data.slice(offset, end),
      after: node.data.slice(end, end + 48)
    }});
  }
  return JSON.stringify({anchorVisible});
})(__KOOFY_ANCHOR__)
