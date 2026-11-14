import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { marked } from "marked"

// Streams an SSE reply into the transcript from a plain fetch: events are
// JSON objects on `data:` lines ({type: "start"|"delta"|"tool"|"citations"|"error"}),
// `[DONE]` ends the stream. Tool events render as "searched for X" chips
// ahead of the answer text. Sending while a reply streams aborts it —
// "steering": the partial answer is persisted as context, and the new
// message is answered with the interruption in view. On the index page
// the first exchange creates the conversation mid-flight; the response
// names it, later exchanges post to its messages endpoint, and the first
// completed stream visits the conversation's permanent address.
export default class extends Controller {
  static targets = ["form", "transcript", "gate", "greeting", "webMode", "imageMode", "fileInput", "staged", "dropOverlay", "composer"]
  static values = { endpoint: String, fresh: Boolean, keepSimple: Boolean, pending: Boolean, pendingContent: String }

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
  // The foreman's status: one quiet line below the streaming text while the
  // turn runs — the newest phase with a running clock, pinned to the
  // answer's growing edge — expandable into the full timestamped log. It
  // replaces the old live dot as the liveness device, rides events the
  // wire already sends. Completion keeps it — clock frozen to the
  // server's total, log swapped for the persisted one — and the server
  // render is its reload twin; failure and steering still tear it down
  // (nothing persisted to show).
  statusEl = null
  logEl = null
  turnTimer = null
  turnT0 = null
  turnPhase = "thinking"
  turnLaneLabel = ""
  turnLog = []
  sawToken = false
  // Footer suppression: once the accumulated partial grows a line starting
  // "Sources:", the visible preview freezes at the footer's onset and the
  // raw footer text never streams in loud — the completion render rebuilds
  // from `partial`, so nothing is missed, and prose that merely starts
  // "Sources:" self-corrects there (the footer regex won't match it).
  footerSeen = false
  // The answer-mode switch: which mode this ask rides. Per-turn — it
  // reverts to all on send, like the composer clearing; a retry replays
  // the failed turn's mode.
  imageMode = false
  // One-shot handoff from the fresh chat's first send (see connect's
  // marker branch): consume-and-clear, 30s shelf life.
  takeComposerFocusMarker() {
    const stamp = Number(sessionStorage.getItem("comrade:focus-composer"))
    sessionStorage.removeItem("comrade:focus-composer")
    return stamp && Date.now() - stamp < 30000
  }
  // Staged attachments: what the next send carries. Each entry is
  // {data, full, width, height, fullWidth, fullHeight, sourceUrl} —
  // data URLs and dimensions, `full` present only when staging shrank
  // the image. Cleared on send; a failed turn's images ride the retry.
  staged = []

  connect() {
    // The transcript panel is the scroll surface (app shell: the document
    // never scrolls), so liveness tracking binds to it, not the window.
    this.onScroll = () => this.updateAutoScroll()
    this.transcriptTarget.addEventListener("scroll", this.onScroll)
    // The Ask button reads "…" while a stream runs, back to "Ask" the
    // moment there's a draft to send — submitting then steers.
    this.askButton = this.formTarget.querySelector('button[type="submit"]')
    this.formTarget.elements.content.addEventListener("input", () => this.syncAskButton())
    // Drop anywhere on the conversation stages the dragged images. The
    // overlay is purely visual; these element-level listeners own the
    // whole drag lifecycle for everything inside the shell.
    this.onDragOver = (event) => {
      if (![...event.dataTransfer.items].some((item) => item.kind === "file" && item.type.startsWith("image/"))) return
      event.preventDefault()
      this.showDropOverlay()
    }
    this.onDragLeave = (event) => {
      if (!event.relatedTarget || !this.element.contains(event.relatedTarget)) this.hideDropOverlay()
    }
    this.onDrop = (event) => {
      const files = [...event.dataTransfer.files].filter((file) => file.type.startsWith("image/"))
      this.hideDropOverlay()
      if (!files.length) return
      event.preventDefault()
      // A browser image drag carries the source page alongside the bytes.
      const line = event.dataTransfer.getData("text/uri-list").split("\n").find((entry) => entry && !entry.startsWith("#"))
      this.stageFiles(files, line || null)
    }
    this.element.addEventListener("dragover", this.onDragOver)
    this.element.addEventListener("dragleave", this.onDragLeave)
    this.element.addEventListener("drop", this.onDrop)
    // A new conversation starts with the composer focused — land and type.
    // Only the landing grabs focus; opening an old conversation to read it
    // shouldn't steal focus (or pop the keyboard accessory bar). The gate
    // holds the composer hidden, so nothing to focus until it's revealed.
    if (this.freshValue && !this.composerTarget.classList.contains("hidden")) {
      const field = this.formTarget.elements.content
      // Firefox for iOS fails to activate load-time autofocus: the
      // element takes DOM focus (activeElement confirmed, focus events
      // logged) but never becomes really focused — no caret, keys
      // unroute — until the reader taps it. Safari on the same device
      // and URL activates the same load fine, so the fault is Firefox
      // iOS's focus handling, not this code (on-device, 2026-11-14).
      // The blur-then-focus forces a fresh claim — the native autofocus
      // attribute usually wins the race to connect, and re-focusing an
      // already-focused element is a no-op. Desktop pays an invisible
      // blur/refocus round-trip for it.
      if (document.activeElement === field) field.blur()
      field.focus()
      // Escalating fresh claims (rAF, 200ms): each re-claims if the
      // composer still holds focus — cheap on desktop, and the only
      // remaining hope on device is that a later claim lands inside a
      // still-open activation window. Both skip if the reader has
      // already focused something else (2026-11-14, iPad report).
      requestAnimationFrame(() => { if (document.activeElement === field) { field.blur(); field.focus() } })
      setTimeout(() => { if (document.activeElement === field) { field.blur(); field.focus() } }, 200)
    } else if (this.takeComposerFocusMarker()) {
      // Arrived from a fresh chat's first send (the visit stamped a marker
      // before Turbo.visit). The swap replaced the focused composer's DOM,
      // so the focus the send held is gone — hand it back for the
      // follow-up. Ordinary opens of old conversations carry no marker
      // and never get grabbed, and stale markers die in 30s.
      this.formTarget.elements.content.focus()
    }
    // Tab with nothing focused: WebKit can hold DOM focus invisibly (the
    // iPad bug this branch hunts), leaving the reader stranded with
    // nowhere for Tab to go. A Tab seen with body/null owning focus
    // claims the composer instead; when a link or button owns focus,
    // normal traversal proceeds untouched.
    this.onKeydown = (event) => {
      if (event.key !== "Tab") return
      const active = document.activeElement
      const stranded = active === document.body || active === null || active === document.documentElement
      if (stranded && !this.composerTarget.classList.contains("hidden")) {
        event.preventDefault()
        this.composerTarget.focus()
      }
    }
    document.addEventListener("keydown", this.onKeydown)
    this.fitPlaceholder()
    this.element.insertAdjacentHTML("beforeend",
      '<button type="button" data-action="stream-reader#jumpToLatest" class="jump-latest fixed bottom-24 right-[13rem] z-20 hidden cursor-pointer rounded-full border border-hairline bg-panel px-3 py-1.5 font-mono text-[0.594rem] text-kiosk hover:text-newsprint">↓ latest</button>')
    // The server marked this conversation's last user turn unanswered —
    // a search-handoff GET that booted the turn, or a reload mid-stream.
    // Resume it now; the server's retry case makes the resume idempotent.
    if (this.hasPendingValue && this.pendingValue) this.resumeTurn()
  }

  // The full greeting doesn't fit one line beside the mode switch at
  // phone widths — a wrapped placeholder clips inside the one-row
  // textarea. Measured, not a breakpoint: the A− text-scale steps and
  // odd viewports all change the budget. Swaps to the short form (the
  // view carries it as data-short-placeholder, only where a swap makes
  // sense) when the current placeholder would wrap. One-way: rotating
  // wide again keeps the short form.
  fitPlaceholder() {
    const field = this.formTarget.elements.content
    const short = field.dataset.shortPlaceholder
    if (!short || field.placeholder === short) return
    // A gated page connects with the form still hidden: clientWidth is 0
    // and everything "overflows". Only judge once the form is rendered —
    // the gate's reveal calls back in.
    if (field.clientWidth === 0) return
    const probe = document.createElement("span")
    probe.style.cssText = "position:absolute;visibility:hidden;white-space:pre;font:" + getComputedStyle(field).font
    probe.textContent = field.placeholder
    document.body.appendChild(probe)
    const style = getComputedStyle(field)
    // clientWidth includes the field's padding; the text budget doesn't.
    const budget = field.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight)
    const overflows = probe.getBoundingClientRect().width > budget
    probe.remove()
    if (overflows) field.placeholder = short
  }

  disconnect() {
    this.transcriptTarget.removeEventListener("scroll", this.onScroll)
    document.removeEventListener("keydown", this.onKeydown)
    this.element.removeEventListener("dragover", this.onDragOver)
    this.element.removeEventListener("dragleave", this.onDragLeave)
    this.element.removeEventListener("drop", this.onDrop)
    this.element.querySelector(".jump-latest")?.remove()
    this.stopTurnStatus()
  }

  showDropOverlay() {
    this.dropOverlayTarget.classList.replace("hidden", "flex")
  }

  hideDropOverlay() {
    this.dropOverlayTarget.classList.replace("flex", "hidden")
  }

  // The attach segment: the hidden input's picker — on iOS that IS the
  // Photos picker, the only mobile flow.
  pickAttachments() {
    this.fileInputTarget.click()
  }

  pickFiles(event) {
    this.stageFiles(event.target.files, null)
    event.target.value = ""
  }

  // ⌘V of a screenshot: the clipboard's image files stage like dropped
  // ones. Only intercepted when images ride the paste — text pastes
  // stay untouched.
  paste(event) {
    const files = [...event.clipboardData.files].filter((file) => file.type.startsWith("image/"))
    if (!files.length) return
    event.preventDefault()
    this.stageFiles(files, null)
  }

  // Staging is keep-or-shrink, format-preserving: at or under ~1280px
  // the original bytes ride (a PNG screenshot keeps its text crisp);
  // over the cap, a canvas downsample to ~1280px, JPEG 0.8 — and the
  // original rides along as `full` for the model's read_image escape
  // hatch. What this browser can't decode (HEIC outside Safari), it
  // says so.
  async stageFiles(files, sourceUrl) {
    for (const file of files) {
      if (file.size > 10 * 1024 * 1024) {
        this.showStageNote(`${file.name || "image"} is over the 10 MB cap`)
        continue
      }
      try {
        this.staged.push(await this.stageFile(file, sourceUrl))
        this.renderStaged()
      } catch {
        this.showStageNote(`${file.name || "image"}: this browser can't decode it`)
      }
    }
  }

  async stageFile(file, sourceUrl) {
    const bitmap = await createImageBitmap(file)
    const { width, height } = bitmap
    if (Math.max(width, height) <= 1280) {
      bitmap.close()
      return { data: await this.readAsDataURL(file), width, height, full: null, fullWidth: null, fullHeight: null, sourceUrl }
    }
    const scale = 1280 / Math.max(width, height)
    const canvas = Object.assign(document.createElement("canvas"), { width: Math.round(width * scale), height: Math.round(height * scale) })
    const context = canvas.getContext("2d")
    // JPEG has no alpha: fill first, or transparent areas render black.
    context.fillStyle = "#fff"
    context.fillRect(0, 0, canvas.width, canvas.height)
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
    bitmap.close()
    return {
      data: canvas.toDataURL("image/jpeg", 0.8),
      width: canvas.width,
      height: canvas.height,
      full: await this.readAsDataURL(file),
      fullWidth: width,
      fullHeight: height,
      sourceUrl,
    }
  }

  readAsDataURL(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader()
      reader.onload = () => resolve(reader.result)
      reader.onerror = () => reject(reader.error)
      reader.readAsDataURL(file)
    })
  }

  showStageNote(text) {
    this.stageNote?.remove()
    this.stageNote = document.createElement("p")
    this.stageNote.className = "grow basis-full font-mono text-[0.594rem] text-red-text"
    this.stageNote.textContent = text
    this.stagedTarget.append(this.stageNote)
    this.stagedTarget.classList.remove("hidden")
  }

  renderStaged() {
    this.stageNote = null
    const box = this.stagedTarget
    box.replaceChildren()
    this.staged.forEach((image, index) => {
      const chip = document.createElement("div")
      chip.className = "c-staged-chip"
      const thumb = document.createElement("img")
      thumb.src = image.data
      thumb.alt = ""
      thumb.className = "h-10 w-auto"
      const label = document.createElement("span")
      label.textContent = image.full
        ? `${image.width}×${image.height} (from ${image.fullWidth}×${image.fullHeight})`
        : `${image.width}×${image.height}`
      const remove = document.createElement("button")
      remove.type = "button"
      remove.textContent = "×"
      remove.setAttribute("aria-label", "Remove attachment")
      remove.className = "cursor-pointer px-1 text-kiosk hover:text-newsprint"
      remove.addEventListener("click", () => {
        this.staged.splice(index, 1)
        this.renderStaged()
      })
      chip.append(thumb, label, remove)
      box.append(chip)
    })
    box.classList.toggle("hidden", !this.staged.length)
  }

  updateAutoScroll() {
    const panel = this.transcriptTarget
    const nearBottom = panel.scrollTop + panel.clientHeight >= panel.scrollHeight - 80
    this.autoScroll = nearBottom
    this.element.querySelector(".jump-latest")?.classList.toggle("hidden", nearBottom)
  }

  // Chip click (or scrolling home manually) re-pins the reader.
  jumpToLatest() {
    this.autoScroll = true
    this.transcriptTarget.scrollTop = this.transcriptTarget.scrollHeight
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

  // The answer-mode switch: all is the default; images swaps web search
  // off the wire for the turn. The active segment reads as part of the
  // composer (raised), the inactive one recedes.
  pickWebMode() {
    this.imageMode = false
    this.renderModeSwitch()
  }

  pickImageMode() {
    this.imageMode = true
    this.renderModeSwitch()
  }

  // The active mode reads newsprint on the red wash with the inset red
  // underline; the inactive one recedes to kiosk. Class twins of
  // _chat.html.erb's switch.
  renderModeSwitch() {
    if (!this.hasWebModeTarget) return
    this.webModeTarget.className = this.imageMode ? "c-modebtn" : "c-modebtn on"
    this.imageModeTarget.className = this.imageMode ? "c-modebtn on" : "c-modebtn"
  }

  async submit(event) {
    event.preventDefault()
    const input = event.target.elements.content
    const content = input.value.trim()
    // An image-only send is legal: empty text with attachments passes.
    if (!content && !this.staged.length) return

    // The images ride this send; the staged chips clear either way —
    // the user turn below carries their thumbnails, and a failed turn's
    // images travel with its retry link.
    const images = this.staged.map((image) => ({
      data: image.data,
      full: image.full,
      width: image.width,
      height: image.height,
      full_width: image.fullWidth,
      full_height: image.fullHeight,
      source_url: image.sourceUrl,
    }))
    this.staged = []
    this.renderStaged()

    input.value = ""
    this.syncAskButton()
    this.clearRetries()
    // The mode rides the ask and reverts — per-turn, like the composer
    // clearing.
    const mode = this.imageMode ? "images" : ""
    this.pickWebMode()
    // Only an in-flight stream can be interrupted. A completed stream also
    // leaves `partial` holding its full text — sending that as `interrupted`
    // makes the server persist the previous answer again as a lead-in row
    // (the duplicate-transcript bug of 2026-10-24).
    const interrupted = this.currentRequest ? this.partial : ""
    // Steering: finalize the interrupted answer with what arrived — its
    // citation pass runs now, before the new stream resets the shared
    // stream state — then abort the request.
    if (this.currentRequest && this.partial) {
      this.finishStream(this.liveAnswer)
      this.currentRequest.abort()
    } else if (this.currentRequest) {
      this.currentRequest.abort()
    }

    const answer = this.appendExchange(content, images)
    await this.stream(content, interrupted, answer, { retry: false, mode, images })
  }

  // The one reply path: POST, stream into the given assistant turn, and
  // on any failure leave a retry link bound to the same content — same
  // mode, same images: a failed image turn retries as an image turn.
  async stream(content, interrupted, answer, { retry, mode, images }) {
    this.partial = ""
    this.pendingCitations = null
    this.pendingStats = null
    this.footerSeen = false
    this.clearOffers()
    const request = this.currentRequest = new AbortController()
    this.liveAnswer = answer
    this.syncAskButton()
    let completed

    let response
    try {
      response = await fetch(this.endpointValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "text/event-stream" },
        body: JSON.stringify({ content, interrupted, retry, mode, images }),
        signal: this.currentRequest.signal,
      })
    } catch (error) {
      if (error.name === "AbortError") return
      this.showRetry(content, interrupted, answer, null, mode, images)
      return
    }

    if (!response.ok) {
      this.showRetry(content, interrupted, answer, null, mode, images)
      return
    }

    // The first response names the conversation (Location) and its id
    // (X-Conversation-Id): every later exchange — including steers —
    // belongs to that conversation's messages endpoint.
    if (!this.conversationUrl) {
      this.conversationUrl = response.headers.get("Location")
      this.endpointValue = `${this.conversationUrl}/messages`
    }

    this.startTurnStatus(answer)
    try {
      completed = await this.readStream(response.body, answer, content, interrupted, mode, images)
    } catch (error) {
      // A steered-away stream dies intentionally; its partial answer
      // stays on the page and in the transcript via the next request.
      if (error.name !== "AbortError") this.showRetry(content, interrupted, answer, null, mode, images)
      return
    } finally {
      if (this.currentRequest === request) this.currentRequest = null
      this.syncAskButton()
      // Completion keeps the status line (the reload twin renders it);
      // failure and steering tear it down.
      if (!completed) this.stopTurnStatus()
    }
    // Only the index page visits on completion: the first exchange (or,
    // when steered, the exchange that carries the interruption) ends with
    // a Turbo visit to the conversation's permanent address. On a show
    // page exchanges append in place. An upstream error ends the stream
    // without completion, so it never visits. The marker tells the show
    // page's connect() to hand focus back — this swap replaces the
    // composer's DOM, so the focus this send held dies here otherwise.
    if (completed && this.freshValue) {
      sessionStorage.setItem("comrade:focus-composer", String(Date.now()))
      Turbo.visit(this.conversationUrl)
    }
  }

  // A failed turn offers a one-click resend. The retry is a steer: the
  // user message already exists server-side (it persists eagerly), so
  // the retry request skips user persistence and carries whatever partial
  // answer had streamed as interruption context. The reason, when the
  // server sent one, names the upstream failure.
  showRetry(content, interrupted, answer, reason, mode, images = []) {
    this.failed = { content, interrupted, mode, images }

    const line = document.createElement("p")
    line.className = "retry-line mt-2 font-mono text-[0.594rem] text-red-text"
    line.append(reason ? `reply failed — ${reason} — ` : "reply failed — ")
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
    const { content, interrupted, mode, images } = this.failed

    // The retried answer arrives as a fresh assistant turn inside the
    // failed exchange's answer stack; the user turn is already on the
    // page and in the DB.
    const wrap = this.answerWrap()
    wrap.insertAdjacentHTML("beforeend", this.turnHtml("assistant", ""))
    const articles = wrap.querySelectorAll("article")
    const answer = articles[articles.length - 1]
    this.contentEl = answer.querySelector("div")

    await this.stream(content, interrupted, answer, { retry: this.conversationUrl != null, mode, images })
  }

  // The answer stack of the transcript's last exchange — where a retried
  // or resumed answer lands. A missing stack (a transcript the server
  // rendered without one) gets created.
  answerWrap() {
    const turns = this.transcriptTarget.querySelectorAll(".c-turn")
    const shell = turns[turns.length - 1]
    if (shell) {
      let wrap = shell.querySelector(".c-a-wrap")
      if (!wrap) {
        wrap = document.createElement("div")
        wrap.className = "c-a-wrap"
        shell.append(wrap)
      }
      return wrap
    }
    const cols = this.ensureHeads()
    const fresh = document.createElement("div")
    fresh.className = "c-turn"
    fresh.innerHTML = '<div class="c-a-wrap"></div>'
    cols.append(fresh)
    return fresh.querySelector(".c-a-wrap")
  }

  // The pending-turn resume: the user turn is server-rendered and
  // persisted (a dead stream's, or one booted by the /search GET), so the
  // resume always rides the retry path — the server matches the turn to
  // its row on the exact content and never double-persists. The answer
  // arrives as a fresh assistant turn in that exchange's answer stack.
  async resumeTurn() {
    const content = this.pendingContentValue
    // The page knows its own address: claiming it up front keeps the
    // retry flag true even when the resume's fetch dies before a
    // response — a manual resend after that must still ride the retry
    // path, or the server would double-persist the user turn.
    this.conversationUrl ||= window.location.pathname
    const wrap = this.answerWrap()
    wrap.insertAdjacentHTML("beforeend", this.turnHtml("assistant", ""))
    const articles = wrap.querySelectorAll("article")
    const answer = articles[articles.length - 1]
    this.contentEl = answer.querySelector("div")

    await this.stream(content, null, answer, { retry: true, mode: null, images: [] })
  }

  appendExchange(content, images = []) {
    // First exchange: the greeting goes with your message, not with the
    // reply — the transcript top-aligns from here (empty-state centering
    // is my-auto on the card, which is gone or hidden by now).
    this.transcriptTarget.querySelector(".greeting")?.remove()
    // You just sent: the reply deserves an audience. Re-pin the reader.
    this.autoScroll = true
    this.element.querySelector(".jump-latest")?.classList.add("hidden")
    // One exchange shell: question cell, answer stack — the note card
    // arrives at completion. The new turn's node is red; every older one
    // demotes to gold. The server render marks only the last user turn
    // live, so the reload twin agrees.
    this.transcriptTarget.querySelectorAll(".c-node-live").forEach((node) => node.classList.remove("c-node-live"))
    const cols = this.ensureHeads()
    const shell = document.createElement("div")
    shell.className = "c-turn"
    shell.innerHTML =
      `<div class="c-q"><span class="c-node c-node-live"></span>${this.turnHtml("user", content, images)}</div>` +
      `<div class="c-a-wrap">${this.turnHtml("assistant", "")}</div>`
    cols.append(shell)
    // The reserved title row's heir: the masthead's edition band reads
    // the working title — truncated exactly like Conversation.start! (an
    // image-only send names itself the same way the server's fallback
    // does) — so the band reads the same before and after the
    // Turbo.visit swap. Fresh pages only: a show page's band already
    // carries the conversation's title.
    if (this.freshValue) {
      const band = document.getElementById("edition-band")
      if (band) {
        band.textContent =
          content.replace(/\s+/g, " ").slice(0, 50) || (images.length === 1 ? "Image" : `${images.length} images`)
      }
    }
    const answer = shell.querySelector(".c-a-wrap article")
    // Streamed text renders in final color from the start — no
    // provisional faint pass.
    this.contentEl = answer.querySelector("div")
    return answer
  }

  // The column heads above the transcript — created lazily on the first
  // send of a fresh chat, matching the server render's heads row.
  ensureHeads() {
    let cols = this.transcriptTarget.querySelector(".c-cols")
    if (!cols) {
      cols = document.createElement("div")
      cols.className = "c-cols"
      // Byte-identical with _chat.html.erb's head row.
      cols.innerHTML = '<div class="c-col-head c-head-q">Current</div><div class="c-col-head c-head-sources">Sources</div>'
      this.transcriptTarget.append(cols)
    }
    return cols
  }

  // The foreman's status: a pulsing dot, the newest phase, and a running
  // clock on one quiet line BELOW the streaming text — pinned to the
  // answer's growing edge, where the reader is looking. A click expands
  // the full timestamped log. Up when the stream opens; completion keeps
  // it (completeTurnStatus), failure and steering tear it down (the
  // stream call's finally).
  startTurnStatus(answer) {
    this.turnT0 = Date.now()
    this.turnPhase = "thinking"
    this.turnLaneLabel = ""
    this.turnLog = []
    this.sawToken = false
    // A completed prior turn leaves its log element behind (its status
    // line survives); the new turn's log starts fresh below its own line.
    this.logEl = null
    this.statusEl = document.createElement("p")
    this.statusEl = document.createElement("p")
    this.statusEl.className = "turn-status flex cursor-pointer items-center gap-2 font-mono text-xs text-kiosk"
    // The event is named explicitly: Stimulus's shorthand (identifier#method)
    // resolves the event from the element's default (a → click, form →
    // submit, …) and a <p> has none — the action throws "missing event
    // name" inside the observer and silently never binds.
    this.statusEl.dataset.action = "click->stream-reader#toggleTurnLog"
    this.statusEl.innerHTML =
      '<span class="live-dot inline-block h-1.5 w-1.5 animate-pulse rounded-full bg-soviet"></span>' +
      '<span class="turn-status-text grow"></span>'
    this.statusClock = this.statusEl.querySelector(".turn-status-text")
    // Anchored below the content div: text grows above it, tool rounds
    // already create each new content div before it, so the status stays
    // at the answer's growing edge without re-insertion.
    this.contentEl.after(this.statusEl)
    this.renderTurnStatus()
    this.turnTimer = setInterval(() => this.renderTurnStatus(), 1000)
  }

  renderTurnStatus() {
    this.statusClock.textContent =
      [this.turnLaneLabel, this.turnPhase, this.turnClock(Date.now() - this.turnT0)].filter(Boolean).join(" · ")
  }

  // The m:ss clock both the status line and the log's stamps read —
  // client-side against turnT0 while the turn runs, server-side from
  // total_ms once it's done (byte-identical twins).
  turnClock(milliseconds) {
    const seconds = Math.floor(milliseconds / 1000)
    return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`
  }

  // Log entries are stamped against the turn's clock and kept as plain
  // text — model names, queries and URLs never touch innerHTML.
  turnStamp(text) {
    return `${this.turnClock(Date.now() - this.turnT0)} ${text}`
  }

  appendTurnLog(text) {
    this.turnLog.push(text)
    if (!this.logEl) {
      this.logEl = document.createElement("pre")
      this.logEl.className = "c-turn-log hidden"
      this.statusEl.after(this.logEl)
    }
    this.logEl.textContent = this.turnLog.join("\n")
  }

  toggleTurnLog(event) {
    // The log is found from the clicked line, not an instance field: the
    // server render's status lines (older turns after a reload) carry the
    // same action with no controller state behind them.
    event.currentTarget.closest("article")?.querySelector(".c-turn-log")?.classList.toggle("hidden")
  }

  // Completion retires the ticking status: renderCitations swaps the whole
  // block for the merged action line — dot, clickable total, persisted
  // log. Stopping the timer is all that's left here; failure and steering
  // tear the line down through stopTurnStatus.
  completeTurnStatus() {
    if (this.turnTimer) clearInterval(this.turnTimer)
    this.turnTimer = null
  }

  stopTurnStatus() {
    if (this.turnTimer) clearInterval(this.turnTimer)
    this.turnTimer = null
    this.statusEl?.remove()
    this.statusEl = null
    this.logEl = null
  }

  // "…" while a stream runs, "Ask" the moment there's a draft typed — a
  // mid-stream submit steers. Fixed width so the swap can't resize the
  // composer unit.
  syncAskButton() {
    const input = this.formTarget.elements.content
    const busy = this.currentRequest && !input.value.trim()
    this.askButton.textContent = busy ? "…" : "Ask"
  }

  // A tap on Ask while the composer is focused blurs the textarea first —
  // and iOS Safari cancels the tap's click across the focus change and the
  // viewport recalc it triggers (accessory bar hides, shell re-sizes), so
  // the first tap never submits. Preventing mousedown's default keeps
  // focus in the composer: no blur, no recalc, the tap completes — and
  // focus survives sending, so the next message needs no re-tap.
  holdFocus(event) {
    event.preventDefault()
  }

  // End-of-stream pass for a steered-away answer: same formatting the
  // [DONE] path would run, on whatever text arrived.
  finishStream(answer) {
    this.renderCitations(answer)
  }

  turnHtml(role, content, images = []) {
    // Attachments render above the turn's text, same slot the tool chips
    // and image strips take in answers. Byte-identical with
    // _message.html.erb's branches (styling in the c- classes).
    const strip = images.length ? this.attachmentStripHtml(images) : ""
    if (role === "user") {
      return `<article>
      <p class="c-turn-label"><span class="c-who-mark">▸</span>You</p>
      ${strip}
      <div class="c-question">${content}</div>
    </article>`
    }
    return `<article>
      <p class="c-turn-label"><span class="c-who-mark">▸</span>Comrade</p>
      <div class="c-answer whitespace-pre-wrap">${content}</div>
    </article>`
  }

  // The staged copies as the turn's thumbnail strip: data URLs — the
  // bytes aren't stored yet. The reload twin reads the same refs back
  // as /uploads/ URLs (attachment_strip in conversations_helper.rb);
  // identical markup, identical pixels, different address only.
  attachmentStripHtml(images) {
    const escape = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;")
    const buttons = images.map((image) => {
      const full = image.full || image.data
      const caption = image.sourceUrl || "attached image"
      return `<button type="button" class="shrink-0 cursor-pointer" data-action="click->lightbox#open" data-full-url="${escape(full)}" data-thumb-url="${escape(image.data)}" data-caption="${escape(caption)}"><img src="${escape(image.data)}" alt="attached image" loading="lazy" class="h-24 w-auto rounded"></button>`
    }).join("")
    return `<div class="image-strip c-attachment-strip">${buttons}</div>`
  }

  async readStream(body, answer, content, interrupted, mode, images) {
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
          // Completion swaps the foreman's status to its persisted form
          // before the citation render consumes the stats event.
          this.completeTurnStatus()
          this.renderCitations(answer)
          return true
        }
        const parsed = JSON.parse(data)
        // Upstream failure (endpoint unreachable, misconfigured): the
        // reason lands in the retry line; the [DONE] success path never
        // runs, so no citation render and no Turbo visit.
        if (parsed.type === "error") {
          this.showRetry(content, interrupted, answer, parsed.message, mode, images)
          return false
        }
        // The server recognized this retry as an already-answered turn:
        // the original stream died after persisting its full answer. The
        // empty retry turn goes, and the stream counts as complete — a
        // fresh page then visits the true transcript, a show page is
        // already on it.
        if (parsed.type === "duplicate") {
          answer.remove()
          return true
        }
        if (this.applyEvent(answer, parsed)) sawCitations = true
        this.scrollToBottom()
      }
    }
  }

  // Returns true when the event carried citations.
  applyEvent(answer, event) {
    if (event.type === "start") {
      // The foreman's opening entry: which lane the turn rides, the model
      // on it, the pinned effort when there is one. A lane-less setup has
      // no lane to name — the model speaks for itself.
      this.turnLaneLabel = event.lane === "legacy" ? "" : `${event.lane} lane`
      const parts = [this.turnLaneLabel, event.model, event.effort && `effort ${event.effort}`].filter(Boolean)
      this.appendTurnLog(this.turnStamp(`turn accepted — ${parts.join(", ")}`))
      this.renderTurnStatus()
    } else if (event.type === "delta") {
      // Text is final-color from the first delta; the status line's clock
      // is the "still working" signal.
      this.partial += event.text
      this.showPartialTail()
      if (!this.sawToken) {
        this.sawToken = true
        this.appendTurnLog(this.turnStamp("first token"))
      }
      this.turnPhase = "writing"
      this.renderTurnStatus()
    } else if (event.type === "tool") {
      // The finished run stops accumulating — the answer pass formats
      // alone. The status line keeps ticking: the stream is still working.
      this.partial = ""
      this.footerSeen = false
      this.turnPhase =
        event.name === "fetch_page" ? "fetching"
        : event.name === "read_image" ? "reading"
        : "searching"
      this.appendTurnLog(this.turnStamp(this.toolLogLine(event)))
      this.renderTurnStatus()
      // Chips collect into one group div (matching the server render):
      // the group carries the outer spacing, chips are tight inside it.
      let group = answer.querySelector(".c-chip-group")
      if (!group) {
        group = document.createElement("div")
        group.className = "c-chip-group"
        this.contentEl.after(group)
      }
      const chip = document.createElement("template")
      chip.innerHTML = this.toolChip(event).trim()
      group.append(chip.content.firstChild)
      this.contentEl = document.createElement("div")
      this.contentEl.className = "c-answer whitespace-pre-wrap"
      group.after(this.contentEl)
    } else if (event.type === "images") {
      // An image_search round's found pictures: a thumbnail strip after
      // the chip group, ahead of the answer text (the reload twin reads
      // the row's payload).
      this.renderImageStrip(answer, event.images)
    } else if (event.type === "citations") {
      this.pendingCitations = event.citations
      return event.citations.length > 0
    } else if (event.type === "stats") {
      // The same numbers the server persists on the row — the footer
      // segment renders from these so the live render and the reload
      // match byte for byte. The row id rides the event (wire-only, the
      // jsonb stays clean) so the footer's prompt link can target the row.
      this.pendingStats = event.stats
    }
    return false
  }

  // Renders the streaming preview of the accumulated `partial`: what the
  // completion render will keep, not what it will strip. Inline [n]
  // markers vanish here the way they resolve into source chips there, and
  // a trailing "[" or "[1" hides too — markers split across deltas. A
  // bracket that turns out to be prose pops back at completion. Once the
  // footer begins (a line starting "Sources:"), the preview freezes at
  // the footer's onset; later deltas accumulate silently, and the
  // completion render rebuilds from `partial` so nothing is missed.
  showPartialTail() {
    if (this.footerSeen) return
    const onset = this.partial.search(/(^|\n)Sources:/)
    if (onset !== -1) {
      this.footerSeen = true
      this.contentEl.textContent = this.visibleText(this.partial.slice(0, onset))
      return
    }
    this.contentEl.textContent = this.visibleText(this.partial)
  }

  visibleText(text) {
    // Horizontal whitespace only before a marker: this runs on the whole
    // raw stream, and \s* would eat the \n\n between paragraphs, visually
    // merging them in the preview. The completion twins run per-paragraph,
    // where plain \s* is safe.
    return text.replace(/[^\S\n]*\[\d+\]/g, "").replace(/[^\S\n]*\[\d*\]$/, "")
  }

  // End-of-stream formatting: paragraphs split on blank lines, each
  // rendered as markdown (the model writes markdown); inline [n] markers
  // plus the model's "Sources:" footer are consumed as the
  // paragraph→source signal and stripped — their sources print in the
  // turn's margin note card, superscripts never appear (slice 2). During
  // the stream the markers show as literal text (they can split across
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
    const escape = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;")

    const markerSources = {}
    const body = this.partial.replace(/\n?Sources?:\n((?:\s*\[\d+\][^\n]*\n?)+)\s*$/, (block, lines) => {
      // The model writes titles into the footer — they beat bare hosts
      // when the cited url isn't in the canonical citations list.
      for (const line of lines.split("\n")) {
        const match = line.match(/^\s*\[(\d+)\]\s*(.+)$/)
        if (!match) continue
        const urlMatch = match[2].match(/https?:\/\/\S+/)
        if (!urlMatch) continue
        const url = urlMatch[0]
        const title = match[2].replace(url, "").replace(/\s*[–—-]\s*$/, "").trim() || null
        markerSources[parseInt(match[1])] = { url, title }
      }
      return "\n"
    })

    // Footerless answers (the fast lane skips the footer on ~1 in 4)
    // resolve markers positionally against the citations event — the
    // server persists citations in wire order, so [n] is citations[n-1].
    // A declared footer wins: its map is the model's own numbering.
    // Twin of the footer/positional fork in sources_helper.rb.
    const footerDeclared = Object.keys(markerSources).length > 0
    if (!footerDeclared && citations.length) {
      citations.forEach((citation, index) => { markerSources[index + 1] = citation })
    }

    // The note card's lines: the union of the paragraphs' marker
    // resolutions, first-appearance order, deduped by url — each
    // carrying the marker number that cited it. A declared footer with
    // no inline markers (deep-lane drift) falls back to the footer's own
    // list. Twin of turn_sources in sources_helper.rb.
    const noteSources = []
    const remember = (n, cited) => {
      const citation = citations.find((c) => c.url === cited.url)
      const source = citation || { url: cited.url, title: cited.title || new URL(cited.url).host }
      if (!noteSources.some((s) => s.url === source.url)) noteSources.push({ n, url: source.url, title: source.title })
    }
    let resolved = false
    const html = body.split(/\n\n+/).map((paragraph) => {
      const plain = this.sansSup(this.sansRangeMarkers(paragraph)).replace(/\s*\[(\d+)\]/g, (marker, n) => {
        const cited = markerSources[parseInt(n)]
        if (!cited) return marker
        resolved = true
        remember(parseInt(n), cited)
        return ""
      })
      return marked.parse(escape(plain), { breaks: true })
    }).join("")
    if (footerDeclared && !resolved) {
      Object.keys(markerSources).sort((a, b) => a - b).forEach((n) => remember(parseInt(n), markerSources[n]))
    }
    content.innerHTML = html
    this.fillNote(answer, noteSources, escape)
    // Completion merges the foreman into the action line: the status
    // line and its live log retire, the merged line carries the dot and
    // the clickable total, and the persisted log sits under it — what a
    // reload renders. Byte-identical with _message.html.erb.
    this.statusEl?.remove()
    this.logEl?.remove()
    this.statusEl = null
    this.logEl = null
    if (!citations.length) {
      answer.insertAdjacentHTML("beforeend", this.ownKnowledgeHtml)
    } else {
      answer.insertAdjacentHTML("beforeend", this.breakDownHtml)
    }
    this.appendTurnLogPre(answer)
    this.pendingCitations = null
    this.pendingStats = null
  }

  // The margin-note card: the exchange's note number, then one line per
  // source — marker, title link, go-deeper — or the "none" line when the
  // answer drew on model knowledge alone. The number counts the notes
  // already in the transcript, matching the server render's exchange
  // count. Byte-shape twin of note_card in sources_helper.rb.
  fillNote(answer, sources, escape) {
    const shell = answer.closest(".c-turn")
    if (!shell) return
    const number = String(this.transcriptTarget.querySelectorAll(".c-note").length).padStart(2, "0")
    let note = shell.querySelector(".c-note")
    if (!note) {
      note = document.createElement("div")
      note.className = "c-note"
      shell.append(note)
    }
    const lines = sources.map((source) =>
      `<span class="c-note-line"><em>${source.n}</em> · <a href="${escape(source.url)}" target="_blank" rel="noopener">${escape(source.title || source.url)}</a> <a href="#" data-title="${escape(source.title || "")}" data-url="${escape(source.url)}" data-action="stream-reader#goDeeper" class="go-deeper">go deeper</a></span>`)
    if (!lines.length) lines.push('<span class="c-note-line">none — from model knowledge</span>')
    note.innerHTML = `<b class="c-note-num">${number}</b>${lines.join("")}`
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
    return text.replace(/\s*\[\d+\]\s*[–—-]\s*(?:\[\d+\]|\d+)|\s*\[\d+\s*[–—-]\s*\d+\]/g, "")
  }

  // The foreman's log line for a tool event — the same words the server
  // writes into the persisted log (tool_log_line in reply.rb).
  toolLogLine(event) {
    if (event.name === "web_search") return `searched: ${event.query}`
    if (event.name === "image_search") return `searched images: ${event.query}`
    if (event.name === "read_image") return `read image: ${event.key}`
    return `fetched: ${event.url}`
  }

  toolChip(event) {
    const escape = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;")
    const label =
      event.name === "image_search" ? "searched images for:"
      : event.name === "read_image" ? "read image:"
      : event.query ? "searched for:"
      : "fetched:"
    const value = event.query || event.url || event.key
    // Chip inside the group (see applyEvent): tight, the group div carries
    // the spacing. Byte-shape twin of tool_note in conversations_helper.rb.
    return `<p class="c-tool-chip">— ${label} <em>${escape(value)}</em></p>`
  }

  // The thumbnail strip an image_search round found: proxied thumbs
  // (comrade serves the bytes — devices never hit image hosts), tap
  // opens the full image in the lightbox. Sits after the chip group,
  // ahead of the answer text; further strips keep row order under it.
  // Byte-identical with image_strip in conversations_helper.rb.
  renderImageStrip(answer, images) {
    const group = answer.querySelector(".c-chip-group")
    if (!group || !images?.length) return
    const strips = answer.querySelectorAll(".image-strip")
    const anchor = strips.length ? strips[strips.length - 1] : group
    const strip = document.createElement("template")
    strip.innerHTML = this.imageStripHtml(images).trim()
    anchor.after(strip.content.firstChild)
    this.scrollToBottom()
  }

  imageStripHtml(images) {
    const escape = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;")
    const buttons = images.map((image) => {
      const title = escape(image.title)
      return `<button type="button" class="shrink-0 cursor-pointer" data-action="click->lightbox#open" data-full-url="${escape(image.full)}" data-thumb-url="${escape(image.thumb)}" data-caption="${title}"><img src="${escape(image.thumb)}" alt="${title}" loading="lazy" class="h-24 w-auto rounded"></button>`
    }).join("")
    return `<div class="image-strip mt-1 mb-3 flex gap-2 overflow-x-auto">${buttons}</div>`
  }

  // The provenance segment of the answer's footer line, from the server's
  // stats event — the same numbers the row persists, so the live render
  // and the reload match byte for byte. On a fresh completion the total
  // is the click target that toggles the foreman's log. Byte-identical
  // with stats_segment in conversations_helper.rb.
  statsSegment() {
    const stats = this.pendingStats
    if (!stats || !stats.total_ms) return ""
    return ` · <span class="cursor-pointer hover:text-newsprint" data-action="click->stream-reader#toggleTurnLog">total ${this.statSeconds(stats.total_ms)}</span>`
  }

  statSeconds(ms) {
    return `${(ms / 1000).toFixed(1)}s`
  }

  // The action line's dot: gold marks a completed turn — every completed
  // turn's line carries one; red pulsing is the working mark, streaming
  // only. Byte-twin of standing_dot in conversations_helper.rb.
  get standingDot() {
    return '<span class="live-dot mr-2 inline-block h-1.5 w-1.5 rounded-full bg-gold"></span>'
  }

  // The foreman's timestamped log, collapsed under the merged action line
  // and opened from the total time. The persisted log is the truth; text
  // only — model names, queries and URLs never touch innerHTML. Byte-twin
  // of turn_log_pre in conversations_helper.rb.
  appendTurnLogPre(answer) {
    const stats = this.pendingStats
    if (!stats?.log) return
    const pre = document.createElement("pre")
    pre.className = "c-turn-log hidden"
    pre.textContent = stats.log.join("\n")
    answer.insertAdjacentElement("beforeend", pre)
  }

  get ownKnowledgeHtml() {
    // Must stay byte-identical with _message.html.erb's memory footer:
    // the post-first-reply Turbo.visit swaps one for the other.
    let html = '<div class="c-stats-line">' + this.standingDot + 'from model knowledge' + this.statsSegment() + '<span class="break-down-offer"> · <a href="#" data-action="stream-reader#breakDown" class="break-down">break it down</a></span>'
    if (this.keepSimpleValue) html += this.keepSimpleHtml
    return html + '</div>'
  }

  // The action line on a search answer — the note card carries the
  // sources, the line names them (from sources) and carries the actions.
  // Byte-identical with _message.html.erb's sources branch.
  get breakDownHtml() {
    let html = '<div class="c-stats-line">' + this.standingDot + 'from sources' + this.statsSegment() + '<span class="double-check-offer"> · <a href="#" data-action="stream-reader#doubleCheck" class="double-check">check sources</a></span><span class="break-down-offer"> · <a href="#" data-action="stream-reader#breakDown" class="break-down">break it down</a></span>'
    if (this.keepSimpleValue) html += this.keepSimpleHtml
    return html + '</div>'
  }

  // The calibration offer, when standing: rides the latest answer's
  // action line in both renders. Yes/no post and delete through Turbo's
  // method delegation, so injected anchors behave like server-rendered
  // ones. Byte-identical with _message.html.erb's keep-simple span.
  get keepSimpleHtml() {
    return '<span class="keep-simple-offer"> · Simpler by default? <a href="/calibration" data-turbo-method="post">Yes</a> <a href="/calibration" data-turbo-method="delete">No thanks</a></span>'
  }

  // "Stay in the commune": the gate's punt is a client-side reveal — the
  // composer and the rail were always here, just held back until the
  // reader chose. No cookie, no memory: a fresh load asks again. A
  // handle is the only permanent way out of the gate.
  stayInCommune(event) {
    event.preventDefault()
    this.gateTarget.hidden = true
    this.greetingTarget.hidden = false
    this.composerTarget.classList.remove("hidden")
    this.fitPlaceholder()
    document.querySelectorAll("[data-gate-sidebar]").forEach((el) => el.classList.remove("hidden"))
    // The ☰ carries the same gated-hidden as its rail and rides along.
    document.querySelector("[data-sidebar-drawer-target='toggle']")?.classList.remove("hidden")
    this.formTarget.elements.content.focus()
  }

  // The offer on a memory answer: submit a canned verification turn through
  // the composer path, so it behaves exactly like typed text. Refuses while
  // a stream is live (it would steer) and when a draft sits in the composer
  // (never clobber one).
  doubleCheck(event) {
    event.preventDefault()
    const input = this.formTarget.elements.content
    if (this.currentRequest || input.value.trim()) return
    input.value = "double check that against sources — anything wrong, anything missing?"
    this.formTarget.requestSubmit()
  }

  // The line under the answer, action side: a canned simplification turn,
  // same composer path. The server counts these — after enough of them
  // the sidebar quietly offers to make it the default.
  breakDown(event) {
    event.preventDefault()
    const input = this.formTarget.elements.content
    if (this.currentRequest || input.value.trim()) return
    input.value = "break that down — plainer, smaller pieces, same ground."
    this.formTarget.requestSubmit()
  }

  // The links target the latest answer by design; a new turn demotes every
  // older link, so they leave the DOM at stream start. The server render
  // shows them on the latest answer only.
  clearOffers() {
    this.element.querySelectorAll(".double-check-offer, .break-down-offer, .keep-simple-offer").forEach((el) => { el.remove() })
  }

  // The per-source chip offer: submit a canned depth turn naming that one
  // source through the composer path, so it behaves exactly like typed
  // text ("go deeper on…" also trips the server's depth mode). Same
  // refusals as doubleCheck — streaming would steer, a draft must not be
  // clobbered.
  goDeeper(event) {
    event.preventDefault()
    const chip = event.target.closest("a.go-deeper")
    const input = this.formTarget.elements.content
    if (!chip || this.currentRequest || input.value.trim()) return
    const title = chip.dataset.title && chip.dataset.title.trim()
    const source = title ? `${title} (${chip.dataset.url})` : chip.dataset.url
    input.value = `go deeper on this source — ${source} — what does it actually support, and what did the answer leave out?`
    this.formTarget.requestSubmit()
  }

  scrollToBottom() {
    if (this.autoScroll) this.transcriptTarget.scrollTop = this.transcriptTarget.scrollHeight
  }
}