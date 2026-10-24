import { Controller } from "@hotwired/stimulus"

// Root font-size stepper: every text class in the app is rem-based, so
// scaling <html> resizes everything uniformly. The choice persists in
// localStorage and is restored before first paint by an inline head script.
const STEPS = [87.5, 100, 112.5, 125]

export default class extends Controller {
  connect() {
    this.index = STEPS.indexOf(this.current())
    if (this.index === -1) this.index = 1
  }

  smaller() {
    this.step(-1)
  }

  larger() {
    this.step(1)
  }

  step(direction) {
    this.index = Math.min(STEPS.length - 1, Math.max(0, this.index + direction))
    const scale = STEPS[this.index]
    document.documentElement.style.fontSize = `${ scale }%`
    localStorage.setItem('comrade:font-scale', scale)
  }

  current() {
    // The inline head script writes a percentage string ("112.5%"); parseFloat
    // reads the number directly.
    return parseFloat(document.documentElement.style.fontSize) || 100
  }
}