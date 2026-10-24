import { Controller } from "@hotwired/stimulus"

// iOS-style list management for the recents sidebar: "Edit" flips the
// list into archive mode — each row grows a minus control that patches
// archive and lets the redirect re-render the page. Editing is ephemeral:
// any Turbo visit (including the archive redirect itself) resets it.
export default class extends Controller {
  static targets = ["toggle", "archive"]

  editing = false

  toggle() {
    this.editing = !this.editing
    this.archiveTargets.forEach((el) => el.classList.toggle("hidden", !this.editing))
    this.toggleTarget.textContent = this.editing ? "Done" : "Edit"
  }
}