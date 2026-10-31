import { Controller } from "@hotwired/stimulus"

// Desktop (sm+) drag-resize for the sidebar. The divider between the
// content and the aside drags the aside's width between MIN and MAX,
// persisting to localStorage ("comrade:sidebar-width"), which
// app/assets/javascripts/sidebar_width_boot.js restores before first
// paint. Pointer events only — an iPad touch or trackpad drag is the
// same gesture, and the divider's touch-action:none keeps it from
// scrolling the page. The variable (not an inline width) is what moves,
// so the boot script and this controller write the same surface.
// Double-click resets.
//
// Move/up listen on window, not on the captured divider: pointer capture
// proved flaky across real browsers (fine in Chromium, dead on iPadOS) —
// window listeners keep working no matter where the pointer roams.
const MIN = 180
const MAX = 420
const KEY = 'comrade:sidebar-width'

export default class extends Controller {
  static targets = ['aside', 'divider']

  // The sidebar sits at the shell's right edge, so the width is the
  // pointer's distance from the right — the shell is fixed and full-bleed.
  drag(event) {
    if (event.pointerType === 'mouse' && event.button !== 0) return
    event.preventDefault()

    const move = (e) => {
      const width = Math.min(MAX, Math.max(MIN, window.innerWidth - e.clientX))
      document.documentElement.style.setProperty('--sidebar-width', `${ width }px`)
    }
    const up = () => {
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerup', up)
      window.removeEventListener('pointercancel', up)
      document.body.style.userSelect = ''
      document.body.style.cursor = ''
      const width = document.documentElement.style.getPropertyValue('--sidebar-width')
      if (width) localStorage.setItem(KEY, width)
    }

    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', up)
    window.addEventListener('pointercancel', up)
    document.body.style.userSelect = 'none'
    document.body.style.cursor = 'col-resize'
  }

  reset() {
    localStorage.removeItem(KEY)
    document.documentElement.style.removeProperty('--sidebar-width')
  }
}