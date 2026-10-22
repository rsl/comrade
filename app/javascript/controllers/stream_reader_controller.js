import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Streams an SSE reply into the transcript from a plain fetch: deltas are
// JSON-string `data:` lines, `[DONE]` ends the stream. On a fresh
// conversation the first exchange streams in place, then Turbo visits the
// conversation's permanent address (the Location header).
export default class extends Controller {
  static targets = ["form", "transcript"]
  static values = { endpoint: String, fresh: Boolean }

  async submit(event) {
    event.preventDefault()
    const input = event.target.elements.content
    const content = input.value.trim()
    if (!content) return

    input.value = ""
    const answer = this.appendExchange(content)

    const response = await fetch(this.endpointValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "text/event-stream" },
      body: JSON.stringify({ content }),
    })

    if (!response.ok) {
      this.showFailure(answer, response)
      return
    }

    await this.readStream(response.body, answer)
    if (this.freshValue) Turbo.visit(response.headers.get("Location"))
  }

  appendExchange(content) {
    this.transcriptTarget.insertAdjacentHTML("beforeend", this.turnHtml("user", content))
    this.transcriptTarget.insertAdjacentHTML("beforeend", this.turnHtml("assistant", ""))
    const turns = this.transcriptTarget.querySelectorAll("article")
    return turns[turns.length - 1].querySelector("div")
  }

  turnHtml(role, content) {
    const label = role === "user" ? "You" : "Comrade"
    return `<article class="${role === "user" ? "text-neutral-100" : "text-neutral-300"}">
      <p class="mb-1 text-xs font-medium uppercase tracking-wide text-neutral-500">${label}</p>
      <div class="whitespace-pre-wrap leading-relaxed">${content}</div>
    </article>`
  }

  async readStream(body, answer) {
    const reader = body.getReader()
    const decoder = new TextDecoder()
    let buffer = ""

    while (true) {
      const { done, value } = await reader.read()
      if (done) break

      buffer += decoder.decode(value, { stream: true })
      const events = buffer.split("\n\n")
      buffer = events.pop()

      for (const event of events) {
        const data = event.replace(/^data: /, "")
        if (data === "[DONE]") return
        answer.textContent += JSON.parse(data)
        this.scrollToBottom()
      }
    }
  }

  async showFailure(answer, response) {
    const body = await response.json().catch(() => ({}))
    answer.textContent = body.errors ? body.errors.join(", ") : "The reply failed. Try again."
  }

  scrollToBottom() {
    window.scrollTo({ top: document.body.scrollHeight })
  }
}