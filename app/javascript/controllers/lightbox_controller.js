import { Controller } from "@hotwired/stimulus"

// The transcript's image lightbox: a thumbnail tap opens the proxied
// full-size image over a dark scrim; a tap on the scrim or Escape
// dismisses. Within the strip the tapped image belongs to, the reader
// moves between images with the left/right arrow keys, horizontal
// swipes, or the chevron buttons at the screen edges — each image's
// own data attributes are the navigation source, so the overlay needs
// no registry. The controller lives on <body> (the layout) so both
// renders' thumbnails — the server render's and the stream reader's —
// can reach it as an ancestor. The overlay is built lazily on first
// open and survives Turbo visits with the layout.
export default class extends Controller {
  // Refuse while hidden: Escape and the arrows in the composer
  // shouldn't touch the lightbox just because it once opened.
  keydown(event) {
    if (!this.overlay || this.overlay.classList.contains("hidden")) return
    if (event.key === "Escape") this.close()
    if (event.key === "ArrowRight") this.next(event)
    if (event.key === "ArrowLeft") this.previous(event)
  }

  open(event) {
    const thumb = event.currentTarget
    const strip = thumb.closest(".image-strip")
    this.images = strip
      ? Array.from(strip.querySelectorAll("button[data-full-url]"))
      : [thumb]
    this.index = Math.max(0, this.images.indexOf(thumb))
    this.ensureOverlay()
    this.show()
    this.overlay.classList.remove("hidden")
  }

  close() {
    // A swipe's touchend fires a click on the scrim — the navigation
    // consumed that gesture, so the click must not also dismiss.
    if (this.swiped) {
      this.swiped = false
      return
    }
    // Drop the bytes: an enlarged image can be large, and it has no
    // reason to stay decoded behind the transcript.
    this.image.onerror = null
    this.overlay.classList.add("hidden")
    this.image.src = ""
  }

  next(event) {
    event?.stopPropagation()
    this.move(1)
  }

  previous(event) {
    event?.stopPropagation()
    this.move(-1)
  }

  move(step) {
    const index = this.index + step
    // Clamp, not wrap: the ends are the ends, and a silently looping
    // carousel reads as broken.
    if (index < 0 || index >= this.images.length) return
    this.index = index
    this.show()
  }

  // Horizontal swipes navigate; vertical or stationary touches fall
  // through to the scrim's click (dismiss).
  touchStart(event) {
    this.touchX = event.changedTouches[0].clientX
  }

  touchEnd(event) {
    const delta = event.changedTouches[0].clientX - this.touchX
    if (Math.abs(delta) < 48) return
    this.swiped = true
    if (delta < 0) {
      this.next()
    } else {
      this.previous()
    }
  }

  show() {
    const thumb = this.images[this.index]
    this.image.src = thumb.dataset.fullUrl
    // The full-size source is fetched on demand and can fail where the
    // thumbnail (a CDN re-encode) succeeded — a 403-ing host, an
    // over-cap file. Falling back to the known-good thumb keeps the
    // reader on the picture, worst case at lower resolution.
    this.image.onerror = () => {
      const fallback = thumb.dataset.thumbUrl
      if (fallback && !this.image.src.endsWith(fallback)) this.image.src = fallback
    }
    this.caption.textContent = thumb.dataset.caption || ""
    this.counter.textContent = this.images.length > 1 ? `${this.index + 1} / ${this.images.length}` : ""
    this.prevButton.classList.toggle("hidden", this.index === 0)
    this.nextButton.classList.toggle("hidden", this.index === this.images.length - 1)
  }

  ensureOverlay() {
    if (this.overlay) return
    this.overlay = document.createElement("div")
    this.overlay.className = "fixed inset-0 z-50 flex cursor-pointer flex-col items-center justify-center gap-2 bg-black/85 p-4"
    this.overlay.dataset.action = "click->lightbox#close touchstart->lightbox#touchStart touchend->lightbox#touchEnd"
    this.prevButton = this.navButton("‹", "left", "previous")
    this.nextButton = this.navButton("›", "right", "next")
    this.image = document.createElement("img")
    this.image.className = "max-h-[85vh] max-w-full rounded object-contain"
    this.image.alt = ""
    this.counter = document.createElement("p")
    this.counter.className = "text-xs text-neutral-500"
    this.caption = document.createElement("p")
    this.caption.className = "max-w-full truncate text-xs text-neutral-400"
    this.overlay.append(this.prevButton, this.nextButton, this.image, this.counter, this.caption)
    this.element.append(this.overlay)
  }

  // The edge zones are full-height bands pinned to the screen edges —
  // the whole left/right edge is the affordance, matching the lightbox
  // itself. The classes are written out per side: Tailwind's watcher
  // only generates classes it sees as literals, so interpolating the
  // side into the class string silently ships a button with no
  // offsets (it landed dead-center, 2026-10-31).
  navButton(glyph, side, action) {
    const button = document.createElement("button")
    button.type = "button"
    button.textContent = glyph
    button.ariaLabel = action === "next" ? "Next image" : "Previous image"
    button.className = side === "left"
      ? "absolute inset-y-0 left-0 flex w-24 items-center justify-center cursor-pointer text-5xl leading-none text-neutral-500 hover:text-neutral-100"
      : "absolute inset-y-0 right-0 flex w-24 items-center justify-center cursor-pointer text-5xl leading-none text-neutral-500 hover:text-neutral-100"
    button.dataset.action = `click->lightbox#${action}`
    return button
  }
}