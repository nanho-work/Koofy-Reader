(function () {
  // Only installed while translation mode is active. Never modify the publication.
  if (!window.__koofySelectionWatch) {
    var state = window.__koofySelectionWatch = { touching: false, changed: 0 };
    document.addEventListener('touchstart', function () { state.touching = true; }, { passive: true, capture: true });
    function end() { state.touching = false; state.changed = Date.now(); }
    document.addEventListener('touchend', end, { passive: true, capture: true });
    document.addEventListener('touchcancel', end, { passive: true, capture: true });
    document.addEventListener('selectionchange', function () { state.changed = Date.now(); });
    window.addEventListener('blur', function () { state.touching = false; });
  }
  var selection = window.getSelection();
  var text = selection && !selection.isCollapsed ? selection.toString().trim() : '';
  var state = window.__koofySelectionWatch;
  return JSON.stringify({ text: text.slice(0, 2001), active: !!text,
    busy: state.touching || Date.now() - state.changed < 450,
    resource: location.pathname });
})();
