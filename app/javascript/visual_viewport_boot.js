// iOS Safari pans the visual viewport when the keyboard opens — fixed
// elements ride the layout viewport and ghost out from under the browser
// chrome. No viewport unit can express "minus keyboard", so measure it:
// the shell's height tracks visualViewport.height, which shrinks live as
// the keyboard opens and restores when it closes. (2026-10-24)
const setShellHeight = () => {
  const viewport = window.visualViewport
  if (!viewport) return
  document.documentElement.style.setProperty('--shell-height', `${viewport.height}px`)
}

if (window.visualViewport) {
  const onViewportChange = () => {
    setShellHeight()
    pinWindowScroll()
  }
  window.visualViewport.addEventListener('resize', onViewportChange)
  window.visualViewport.addEventListener('scroll', onViewportChange)
  setShellHeight()
}

// iOS Safari "reveals" the focused composer by scrolling the window itself —
// even on a page with no scrollable overflow — and never reverts it, dragging
// the fixed shell out from under the browser chrome. The shell already puts
// the composer above the keyboard, so the scroll serves nothing: pin it back
// to 0. Retries win the fight during the keyboard animation. (2026-10-24)
function pinWindowScroll () {
  if (window.scrollY !== 0) window.scrollTo(0, 0)
}

window.addEventListener('focusin', () => {
  ;[100, 300, 600, 1000].forEach((delay) => setTimeout(pinWindowScroll, delay))
})

// The keyboard-closing resize can land mid-animation and leave the shell
// stuck at the keyboard-open height (2026-11-14, ?vvdebug=1: composer
// stranded ~70px above the bottom with the keyboard gone). Re-measure on
// focusout with the same retry ladder — the last read wins once the
// viewport settles.
window.addEventListener('focusout', () => {
  ;[100, 300, 600, 1000].forEach((delay) => setTimeout(setShellHeight, delay))
})