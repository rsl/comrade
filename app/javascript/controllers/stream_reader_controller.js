import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Streams an SSE reply into the transcript from a plain fetch: events are
// JSON objects on `data:` lines ({type: "delta"|"tool"|"citations"}),
// `[DONE]` ends the stream. Tool events render as "searched for X" chips
// ahead of the answer text. Sending while a reply streams aborts it —
// "steering": the partial answer is persisted as context, and the new
// message is answered with the interruption in view. On the index page
// the first exchange creates the conversation mid-flight; the response
// names it, later exchanges post to its messages endpoint, and the first
// completed stream visits the conversation's permanent address.
export default class extends Controller {
  static targets = ["form", "transcript"]
  static values = { endpoint: String, fresh: Boolean }

  // The in-flight request, abortable, and the partial answer text it has
  // shown so far — the steer payload when a new message interrupts it.
  currentRequest = null
  partial = ""
  // Set once a response names the conversation; drives the endpoint
  // switch and the visit to the show page on completion.
  conversationUrl = null

  // Cmd+Enter / Ctrl+Enter sends; plain Enter stays a newline.
  keydown(event) {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      event.target.form.requestSubmit()
    }
  }

  async submit(event) {
    event.preventDefault()
    const input = event.target.elements.content
    const content = input.value.trim()
    if (!content) return

    input.value = ""
    const interrupted = this.partial
    if (this.currentRequest) this.currentRequest.abort()

    const answer = this.appendExchange(content)
    this.partial = ""
    this.currentRequest = new AbortController()

    let response
    try {
      response = await fetch(this.endpointValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "text/event-stream" },
        body: JSON.stringify({ content, interrupted }),
        signal: this.currentRequest.signal,
      })
    } catch (error) {
      if (error.name === "AbortError") return
      throw error
    }

    if (!response.ok) {
      this.showFailure(answer, response)
      return
    }

    // The first response names the conversation (Location) and its id
    // (X-Conversation-Id): every later exchange — including steers —
    // belongs to that conversation's messages endpoint.
    if (!this.conversationUrl) {
      this.conversationUrl = response.headers.get("Location")
      this.endpointValue = `${this.conversationUrl}/messages`
    }

    try {
      await this.readStream(response.body, answer)
    } catch (error) {
      // A steered-away stream dies intentionally; its partial answer
      // stays on the page and in the transcript via the next request.
      if (error.name !== "AbortError") throw error
      return
    }
    // Only the index page visits on completion: the first exchange (or,
    // when steered, the exchange that carries the interruption) ends with
    // a Turbo visit to the conversation's permanent address. On a show
    // page exchanges append in place.
    if (this.freshValue) Turbo.visit(this.conversationUrl)
  }

  appendExchange(content) {
    this.transcriptTarget.insertAdjacentHTML("beforeend", this.turnHtml("user", content))
    this.transcriptTarget.insertAdjacentHTML("beforeend", this.turnHtml("assistant", ""))
    const turns = this.transcriptTarget.querySelectorAll("article")
    return turns[turns.length - 1]
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
    let sawCitations = false

    while (true) {
      const { done, value } = await reader.read()
      if (done) break

      buffer += decoder.decode(value, { stream: true })
      const events = buffer.split("\n\n")
      buffer = events.pop()

      for (const event of events) {
        const data = event.replace(/^data: /, "")
        if (data === "[DONE]") {
          if (!sawCitations) answer.insertAdjacentHTML("beforeend", this.ownKnowledgeHtml)
          return
        }
        if (this.applyEvent(answer, JSON.parse(data))) sawCitations = true
        this.scrollToBottom()
      }
    }
  }

  // Returns true when the event carried citations.
  applyEvent(answer, event) {
    if (event.type === "delta") {
      answer.querySelector("div").textContent += event.text
      this.partial += event.text
    } else if (event.type === "tool") {
      answer.insertAdjacentHTML("beforeend", this.toolChip(event))
    } else if (event.type === "citations" && event.citations.length > 0) {
      answer.insertAdjacentHTML("beforeend", this.citationsHtml(event.citations))
      return true
    }
    return false
  }

  toolChip(event) {
    const label = event.query ? `searched for ${event.query}` : `fetched ${event.url}`
    return `<p class="mt-2 text-xs text-neutral-500">— ${label}</p>`
  }

  citationsHtml(citations) {
    const links = citations
      .map((c) => `<a href="${c.url}" target="_blank" rel="noopener" class="underline hover:text-neutral-300">${c.title || c.url}</a>`)
      .join(" · ")
    return `<div class="mt-3 border-t border-neutral-800 pt-2 text-xs text-neutral-500">${citations.length} ${citations.length === 1 ? "source" : "sources"}: ${links}</div>`
  }

  get ownKnowledgeHtml() {
    return '<div class="mt-3 border-t border-neutral-800 pt-2 text-xs text-neutral-500">from own knowledge</div>'
  }

  async showFailure(answer, response) {
    const body = await response.json().catch(() => ({}))
    answer.querySelector("div").textContent = body.errors ? body.errors.join(", ") : "The reply failed. Try again."
  }

  scrollToBottom() {
    window.scrollTo({ top: document.body.scrollHeight })
  }
}