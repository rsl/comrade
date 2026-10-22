// Restores the saved root font size before first paint — every text
// class in the app is rem-based, so this scales the whole UI uniformly.
// The value is written by app/javascript/controllers/font_sizer_controller.js.
document.documentElement.style.fontSize =
  `${ localStorage.getItem('comrade:font-scale') || 100 }%`