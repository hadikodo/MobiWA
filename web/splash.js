// Removes the loading splash once Flutter has rendered its first frame.
// (In a file, not inline, so the Content-Security-Policy can forbid inline scripts.)
window.addEventListener('flutter-first-frame', function () {
  var s = document.getElementById('splash');
  if (s) s.remove();
});
