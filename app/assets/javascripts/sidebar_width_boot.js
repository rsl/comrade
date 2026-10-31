// Restores the saved sidebar width before first paint — the shell is a
// fixed flex frame, so a late restore would visibly reflow every page
// load. Same pattern as font_scale_boot.js; the value is written by
// app/javascript/controllers/sidebar_resize_controller.js. Narrow
// viewports ignore it: the drawer's max-sm width class outranks the
// variable.
const width = localStorage.getItem('comrade:sidebar-width')
if (width) document.documentElement.style.setProperty('--sidebar-width', width)