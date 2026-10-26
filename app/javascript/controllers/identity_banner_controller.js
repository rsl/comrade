import { Controller } from '@hotwired/stimulus'

// Announces identity changes once. The sidebar section carries the
// current identity (the name, or 'the commune') — on connect this
// compares it with the identity this browser last saw and, if it
// silently changed (someone enlisted as someone else on this device),
// drops a one-line notice over the page. Intentional changes (enlist /
// step-out just submitted) arrive with announce-identity="false" and
// are stored silently.
export default class extends Controller {
  connect() {
    const identity = this.element.dataset.comradeName
    const announce = this.element.dataset.announceIdentity !== 'false'
    const previous = localStorage.getItem('comrade:identity')
    if (previous && previous !== identity && announce) this.announce(previous, identity)
    localStorage.setItem('comrade:identity', identity)
  }

  // Copy is first-pass; the tweaking stage owns the final words.
  announce(previous, current) {
    const banner = document.createElement('div')
    banner.className = [
      'fixed left-0 right-0 top-0 z-50 flex items-center justify-between gap-2',
      'bg-soviet px-4 py-2 text-sm text-neutral-100',
    ].join(' ')
    const text = document.createElement('span')
    text.textContent = `now ${ current } (was ${ previous }) — not you? Step out in the sidebar`
    const dismiss = document.createElement('button')
    dismiss.type = 'button'
    dismiss.textContent = '×'
    dismiss.className = 'cursor-pointer text-lg leading-none hover:text-white'
    dismiss.addEventListener('click', () => banner.remove())
    banner.append(text, dismiss)
    document.body.prepend(banner)
  }
}