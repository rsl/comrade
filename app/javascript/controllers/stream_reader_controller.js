import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { marked } from "marked"

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

  // A tool event closes the current text run: the next pass opens a fresh
  // div below the chips. Set in appendExchange, replaced on each tool.
  contentEl = null
  // Auto-scroll follows the stream only while the reader is pinned to the
  // bottom; scrolling up pauses it and raises the "latest" chip.
  autoScroll = true

  connect() {
    this.onScroll = () => this.updateAutoScroll()
    window.addEventListener("scroll", this.onScroll)
    // The Ask button reads "…" while a stream runs, back to "Ask" the
    // moment there's a draft to send — submitting then steers.
    this.askButton = this.formTarget.querySelector('button[type="submit"]')
    this.formTarget.elements.content.addEventListener("input", () => this.syncAskButton())
    this.element.insertAdjacentHTML("beforeend",
      '<button type="button" data-action="stream-reader#jumpToLatest" class="jump-latest fixed bottom-28 right-64 z-20 hidden cursor-pointer rounded-full bg-soviet/40 px-3 py-1.5 text-xs text-neutral-100 hover:bg-soviet/60">↓ latest</button>')
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
    this.element.querySelector(".jump-latest")?.remove()
  }

  updateAutoScroll() {
    const nearBottom = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 80
    this.autoScroll = nearBottom
    this.element.querySelector(".jump-latest")?.classList.toggle("hidden", nearBottom)
  }

  // Chip click (or scrolling home manually) re-pins the reader.
  jumpToLatest() {
    this.autoScroll = true
    window.scrollTo({ top: document.documentElement.scrollHeight })
    this.element.querySelector(".jump-latest")?.classList.add("hidden")
  }

  // Cmd+Enter / Ctrl+Enter sends; plain Enter stays a newline. ArrowUp
  // with the caret at the start recalls sent messages, shell-style;
  // ArrowDown walks back forward, ending on the preserved draft.
  keydown(event) {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      event.target.form.requestSubmit()
    } else if (event.key === "ArrowUp" && !event.shiftKey &&
               event.target.selectionStart === 0 && event.target.selectionEnd === 0) {
      this.recall(-1, event)
    } else if (event.key === "ArrowDown" && !event.shiftKey && this.historyIndex !== null) {
      this.recall(1, event)
    }
  }

  recall(direction, event) {
    const input = event.target
    if (direction === -1) {
      if (!this.sentHistory.length) return
      if (this.historyIndex === null) {
        this.draft = input.value
        this.historyIndex = this.sentHistory.length - 1
      } else if (this.historyIndex > 0) {
        this.historyIndex -= 1
      } else { return }
    } else {
      this.historyIndex += 1
      if (this.historyIndex >= this.sentHistory.length) {
        this.historyIndex = null
        input.value = this.draft ?? ""
        input.setSelectionRange(input.value.length, input.value.length)
        event.preventDefault()
        return
      }
    }
    event.preventDefault()
    input.value = this.sentHistory[this.historyIndex]
    input.setSelectionRange(input.value.length, input.value.length)
  }

  async submit(event) {
    event.preventDefault()
    const input = event.target.elements.content
    const content = input.value.trim()
    if (!content) return

    input.value = ""
    this.syncAskButton()
    this.clearRetries()
    const interrupted = this.partial
    // Steering: finalize the interrupted answer with what arrived — its
    // citation pass runs now, before the new stream resets the shared
    // stream state — then abort the request.
    if (this.currentRequest && this.partial) {
      this.finishStream(this.liveAnswer)
      this.currentRequest.abort()
    } else if (this.currentRequest) {
      this.clearLiveDots()
      this.currentRequest.abort()
    }

    const answer = this.appendExchange(content)
    await this.stream(content, interrupted, answer, { retry: false })
  }

  // The one reply path: POST, stream into the given assistant turn, and
  // on any failure leave a retry link bound to the same content.
  async stream(content, interrupted, answer, { retry }) {
    this.partial = ""
    this.pendingCitations = null
    const request = this.currentRequest = new AbortController()
    this.liveAnswer = answer
    this.showLiveDot(answer)
    this.syncAskButton()

    let response
    try {
      response = await fetch(this.endpointValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "text/event-stream" },
        body: JSON.stringify({ content, interrupted, retry }),
        signal: this.currentRequest.signal,
      })
    } catch (error) {
      if (error.name === "AbortError") return
      this.showRetry(content, interrupted, answer)
      return
    }

    if (!response.ok) {
      this.showRetry(content, interrupted, answer)
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
      if (error.name !== "AbortError") this.showRetry(content, interrupted, answer)
      return
    } finally {
      if (this.currentRequest === request) this.currentRequest = null
      this.syncAskButton()
    }
    // Only the index page visits on completion: the first exchange (or,
    // when steered, the exchange that carries the interruption) ends with
    // a Turbo visit to the conversation's permanent address. On a show
    // page exchanges append in place.
    if (this.freshValue) Turbo.visit(this.conversationUrl)
  }

  // A failed turn offers a one-click resend. The retry is a steer: the
  // user message already exists server-side (it persists eagerly), so
  // the retry request skips user persistence and carries whatever partial
  // answer had streamed as interruption context.
  showRetry(content, interrupted, answer) {
    this.clearLiveDots()
    this.failed = { content, interrupted }

    const line = document.createElement("p")
    line.className = "retry-line mt-2 text-xs text-red-400"
    line.append("reply failed — ")
    const link = document.createElement("a")
    link.href = "#"
    link.textContent = "retry?"
    link.className = "underline"
    link.addEventListener("click", (event) => {
      event.preventDefault()
      this.retry()
    })
    line.append(link)
    answer.append(line)
    this.syncAskButton()
  }

  clearRetries() {
    this.element.querySelectorAll(".retry-line").forEach((el) => el.remove())
  }

  async retry() {
    this.clearRetries()
    const { content, interrupted } = this.failed

    // The retried answer arrives as a fresh assistant turn below the
    // failed one; the user turn is already on the page and in the DB.
    this.transcriptTarget.insertAdjacentHTML("beforeend", this.turnHtml("assistant", ""))
    const turns = this.transcriptTarget.querySelectorAll("article")
    const answer = turns[turns.length - 1]

    await this.stream(content, interrupted, answer, { retry: this.conversationUrl != null })
  }

  appendExchange(content) {
    this.clearLiveDots()
    // First exchange: the centered landing gives way to a top-aligned
    // transcript, deliberately at the moment you act — and the greeting
    // goes with your message, not with the reply.
    this.transcriptTarget.classList.remove("justify-center")
    this.transcriptTarget.querySelector(".greeting")?.remove()
    // You just sent: the reply deserves an audience. Re-pin the reader.
    this.autoScroll = true
    this.element.querySelector(".jump-latest")?.classList.add("hidden")
    this.transcriptTarget.insertAdjacentHTML("beforeend", this.turnHtml("user", content))
    this.transcriptTarget.insertAdjacentHTML("beforeend", this.turnHtml("assistant", ""))
    const turns = this.transcriptTarget.querySelectorAll("article")
    const answer = turns[turns.length - 1]
    // Streamed text renders in final color from the start — no
    // provisional faint pass.
    this.contentEl = answer.querySelector("div")
    this.showLiveDot(answer)
    return answer
  }

  // The liveness device: a pulsing red dot inline in the COMRADE label —
  // no node added or removed in the flow, so nothing shifts. Up at stream
  // start, gone at [DONE], failure, or steering.
  showLiveDot(answer) {
    const label = answer.querySelector("p")
    if (!label.querySelector(".live-dot")) {
      label.insertAdjacentHTML("beforeend",
        '<span class="live-dot ml-2 inline-block h-1.5 w-1.5 animate-pulse rounded-full bg-soviet"></span>')
    }
  }

  clearLiveDots() {
    this.element.querySelectorAll(".live-dot").forEach((el) => { el.remove() })
  }

  // "…" while a stream runs, "Ask" the moment there's a draft typed — a
  // mid-stream submit steers. Fixed width so the swap can't resize the
  // composer unit.
  syncAskButton() {
    const input = this.formTarget.elements.content
    const busy = this.currentRequest && !input.value.trim()
    this.askButton.textContent = busy ? "…" : "Ask"
  }

  // End-of-stream pass for a steered-away answer: same formatting the
  // [DONE] path would run, on whatever text arrived.
  finishStream(answer) {
    this.clearLiveDots()
    this.renderCitations(answer)
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
          this.clearLiveDots()
          this.renderCitations(answer)
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
      // Text is final-color from the first delta; the live dot in the
      // label is the only "still working" signal.
      this.contentEl.textContent += event.text
      this.partial += event.text
    } else if (event.type === "tool") {
      // The finished run stops accumulating — the answer pass formats
      // alone. The dot stays: the stream is still working.
      this.partial = ""
      // Chips collect into one group div (matching the server render):
      // the group carries the outer spacing, chips are tight inside it.
      let group = answer.querySelector(".chip-group")
      if (!group) {
        group = document.createElement("div")
        group.className = "chip-group mt-2 mb-3"
        this.contentEl.after(group)
      }
      const chip = document.createElement("template")
      chip.innerHTML = this.toolChip(event).trim()
      group.append(chip.content.firstChild)
      this.contentEl = document.createElement("div")
      this.contentEl.className = "whitespace-pre-wrap leading-relaxed"
      group.after(this.contentEl)
    } else if (event.type === "citations") {
      this.pendingCitations = event.citations
      return event.citations.length > 0
    }
    return false
  }

  // End-of-stream formatting: paragraphs split on blank lines, each
  // rendered as markdown (the model writes markdown); inline [n] markers
  // plus the model's "Sources:" footer are consumed as the
  // paragraph→source signal and stripped — each paragraph renders with
  // quiet source chips under it, superscripts never appear. During the
  // stream the markers show as literal text (they can split across
  // deltas), so the transformation waits for the whole answer. Text is
  // escaped before parsing so the model's output can never carry live
  // HTML through marked.
  renderCitations(answer) {
    const citations = this.pendingCitations || []
    // The final pass's div — after tool rounds it's the last content div,
    // not the first.
    const content = this.contentEl
    // Finalized: the raw-text pre-wrap goes — the markdown renderer's
    // block tags carry spacing from here.
    content.classList.remove("whitespace-pre-wrap")
    const escape = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")

    const markerUrls = {}
    const body = this.partial.replace(/\n?Sources?:\n((?:\s*\[\d+\][^\n]*\n?)+)\s*$/, (block, lines) => {
      for (const line of lines.split("\n")) {
        const match = line.match(/^\s*\[(\d+)\]\s*(.+)$/)
        const url = match && (match[2].match(/https?:\/\/\S+/) || [])[0]
        if (match && url) markerUrls[parseInt(match[1])] = url
      }
      return "\n"
    })

    content.innerHTML = body.split(/\n\n+/).map((paragraph) => {
      const urls = []
      const plain = this.sansSup(this.sansRangeMarkers(paragraph)).replace(/\[(\d+)\]/g, (marker, n) => {
        const url = markerUrls[parseInt(n)]
        if (!url) return marker
        const citation = citations.find((c) => c.url === url)
        urls.push(citation || { url, title: new URL(url).host })
        return ""
      })
      const chips = this.sourceChips(urls, escape)
      const block = marked.parse(escape(plain), { breaks: true })
      return `<div class="mb-3 last:mb-0">${block}</div>${chips}`
    }).join("")
    if (!citations.length) answer.insertAdjacentHTML("beforeend", this.ownKnowledgeHtml)
    this.pendingCitations = null
  }

  // The model sometimes copies the interface's superscript markup into
  // its own text; it renders as escaped noise, so it goes.
  sansSup(text) {
    return text.replace(/<\/?sup[^>]*>/g, "")
  }

  // Range-shaped citation markers ("[1–5]", "[1]–[3]") resolve to no
  // single source, so they'd survive the [n] pass as literal text — the
  // leak this strips. Misbehaving models can't bracket-bomb the page.
  sansRangeMarkers(text) {
    return text.replace(/\[\d+\]\s*[–—-]\s*(?:\[\d+\]|\d+)|\[\d+\s*[–—-]\s*\d+\]/g, "")
  }

  sourceChips(sources, escape) {
    if (!sources.length) return ""
    const links = sources.map((s) =>
      `<a href="${escape(s.url)}" target="_blank" rel="noopener" class="underline hover:text-neutral-300">${escape(s.title || s.url)}</a>`)
    return `<div class="mt-1 mb-4 text-xs text-neutral-500">sources: ${links.join(" · ")}</div>`
  }

  toolChip(event) {
    const label = event.query ? `searched for ${event.query}` : `fetched ${event.url}`
    // Chip inside the group (see applyEvent): tight, the group div carries
    // the spacing.
    return `<p class="mb-1 text-xs text-neutral-500">— ${label}</p>`
  }

  get ownKnowledgeHtml() {
    return '<div class="mt-3 border-t border-ground-bright pt-2 text-xs text-neutral-500">from model knowledge</div>'
  }

  scrollToBottom() {
    if (this.autoScroll) window.scrollTo({ top: document.documentElement.scrollHeight })
  }
}