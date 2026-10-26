import { Controller } from "@hotwired/stimulus"

// The sidebar is a persistent column on desktop and an overlay drawer on
// narrow viewports: the ☰ toggle slides it in, a tap outside or on a
// conversation slides it out, and a leftward swipe dismisses it. All
// movement is the translate class under max-sm — desktop never moves,
// because none of these classes apply there.
export default class extends Controller {
  static targets = ["toggle", "drawer", "backdrop"]

  connect() {
    // Swipe-to-dismiss binds listeners here instead of data-actions for
    // two reasons: touchmove must be non-passive so a claimed horizontal
    // drag can preventDefault, and the handlers need the drawer element
    // directly. Vertical scroll inside the drawer stays native.
    this.onSwipeStart = this.swipeStart.bind(this)
    this.onSwipeMove = this.swipeMove.bind(this)
    this.onSwipeEnd = this.swipeEnd.bind(this)
    // Scrim tap closes. This rode data-action delegation once; headless
    // verification showed Stimulus's dispatch never firing on the backdrop
    // while raw listeners on the same element always did — so it binds the
    // same way the swipe handlers below do. close() is idempotent, so
    // double binds are harmless.
    this.onScrimClick = this.close.bind(this)
    this.backdropTarget.addEventListener("click", this.onScrimClick)
    this.drawerTarget.addEventListener("touchstart", this.onSwipeStart, { passive: true })
    this.drawerTarget.addEventListener("touchmove", this.onSwipeMove, { passive: false })
    this.drawerTarget.addEventListener("touchend", this.onSwipeEnd)
    this.drawerTarget.addEventListener("touchcancel", this.onSwipeEnd)
  }

  disconnect() {
    this.backdropTarget.removeEventListener("click", this.onScrimClick)
    this.drawerTarget.removeEventListener("touchstart", this.onSwipeStart)
    this.drawerTarget.removeEventListener("touchmove", this.onSwipeMove)
    this.drawerTarget.removeEventListener("touchend", this.onSwipeEnd)
    this.drawerTarget.removeEventListener("touchcancel", this.onSwipeEnd)
  }

  toggle() {
    this.drawerTarget.classList.toggle("max-sm:-translate-x-full")
    this.backdropTarget.classList.toggle("hidden")
    // The ☰ opens the drawer; while it's open it would sit dimmed under
    // the scrim at the drawer's edge, looking like a dead button — hide
    // it. Closing (scrim tap, swipe, conversation tap) brings it back.
    this.toggleTarget.classList.toggle("hidden")
  }

  close() {
    this.drawerTarget.classList.add("max-sm:-translate-x-full")
    this.backdropTarget.classList.add("hidden")
    this.toggleTarget.classList.remove("hidden")
  }

  // Tapping a conversation means navigation — the drawer's job is done.
  navigate() {
    this.close()
  }

  // The drag: a horizontal touch on the open drawer moves it with the
  // finger (inline transform overrides the translate class); lifting
  // past a small threshold dismisses, anything else snaps back to open.
  // Untouched: vertical intent never claims the gesture, so the drawer's
  // own scrolling keeps working; multi-touch and desktop are ignored.
  swipeStart(event) {
    if (event.touches.length !== 1) return
    if (window.matchMedia("(min-width: 640px)").matches) return
    if (this.drawerTarget.classList.contains("max-sm:-translate-x-full")) return
    const touch = event.touches[0]
    this.swipe = { x: touch.clientX, y: touch.clientY, dx: 0, claimed: false }
  }

  swipeMove(event) {
    const swipe = this.swipe
    if (!swipe) return
    const touch = event.touches[0]
    const dx = touch.clientX - swipe.x
    const dy = touch.clientY - swipe.y
    if (!swipe.claimed) {
      if (Math.abs(dx) < 10 && Math.abs(dy) < 10) return
      if (Math.abs(dy) >= Math.abs(dx)) { this.swipe = null; return }
      swipe.claimed = true
      this.drawerTarget.style.transition = "none"
    }
    // The drawer follows the finger, clamped at its open position.
    swipe.dx = Math.min(0, dx)
    this.drawerTarget.style.transform = `translateX(${swipe.dx}px)`
    event.preventDefault()
  }

  swipeEnd(event) {
    const swipe = this.swipe
    this.swipe = null
    if (!swipe?.claimed) return
    this.drawerTarget.style.transition = ""
    this.drawerTarget.style.transform = ""
    // A cancelled gesture (system interrupt) never dismisses.
    if (event.type === "touchcancel") return
    if (swipe.dx < -60) this.close()
  }
}