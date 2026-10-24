# Session handoff — 2026-10-24, citation source chain + reply-loop numbering

**State: Sat 2026-10-24, midday. Branch `rsl-citation-sources` holds the
citation chain + UI shell rework, unpushed — rsl holds the push. Working
tree clean, all gates green. Verified working on iPad: citation chain
(real titled sources, no fabricated urls), fixed shell layout, keyboard
focus (scroll pinned, shell tracks visualViewport), fresh-conversation
swap, working title, sidebar. The keyboard-bug chase is CLOSED and
measured (see the UI session section): the "composer under accessory
bar" overlap was the first frame of iPadOS's floating keyboard
accessory bar appearing — a sub-second transient, self-healing, both
steady states verified correct with the ?vvdebug readout. rsl uses a
Magic Keyboard, so the software keyboard never opens; the 69pt
reservation is the accessory bar alone. Remaining open items: push +
PR (rsl's call), dead-code riders, stray caret artifact (cosmetic),
specs when shapes settle. The inherited handoff
(`2026-10-23-quality-review-erb-rewrite`) is archived.**

## Built (committed on `rsl-citation-sources`)

- **Chip-title fix** (`conversations_helper.rb`, `stream_reader_controller.js`):
  source chips showed bare hosts ("www.tastingtable.com") because
  `parse_footer_lines` discarded the model-written footer titles and the
  fallback was `URI.parse(url).host`. Footer lines now yield
  `{url, title}`; the fallback chain is footer title → canonical citation
  → bare host. Mirror fix in the JS `renderCitations` so streamed answers
  get titled chips. Verified live on conversation 79.
- **Numbered-source menu** (`reply.rb`, `comrade_prompt.md`): the root fix
  for fabricated citation links. `search_results` now presents each result
  to the model as `[n] Title — URL` above its snippet, numbering
  continuing across tool rounds via an `offset` threaded from
  `citations.size`; `fetch_page` results get the same treatment. The
  prompt adds "copy each title and url exactly from the results — never
  construct, complete, or recall a url from memory". Verified end-to-end
  on conversation 80: the footer cited [3] and [4] with exact real URLs
  (all returned HTTP 200), versus conversation 79's fabricated links
  (tastingtable soft-404, snopes hard-404).
- **Refactor in passing**: the yielder became `@yielder` (assigned in
  `enumerator`, nil-initialized in `initialize`) — reek's DataClump fired
  twice on the `(citations|offset, yielder)` pairs threading the loop,
  and the sink is per-reply constant, so threading it as a parameter was
  the smell. `run_tool_round`/`run_numbered_tool_calls` split so the
  round owns its running source number.
- **Skill update earlier this session (merged via PR #7)**: the
  disable-directives section codifies `disable-next` (why agents'
  `disable-next-line` "correction" silently no-ops) and the ERB rule now
  draws the line at the attribute position: Ruby in attributes means a
  tag helper, static attributes stay literal, ERB between tags is fine.

## The open problem — solved

Conversation 80 stored ONE citation (`mashed`, menu item [2]) when the
search returned five. Root cause, found by instrumenting the loop with a
probe (`run_tool_call` logged `found=5`, `run_tool_round` returned 1):
`run_numbered_tool_calls` destructured `run_tool_call`'s return as
`_, found = run_tool_call(...)` — a leftover from when the call returned
a `[result, found]` pair before the refactor. Ruby's multiple
assignment binds `found` to the second *element* of the array, so only
each round's second source survived to `citations`. The menu always
showed N (built from the tool result string) while the canonical list
got 1 — and the symptom looked like a reducer between two joints that
were both correct. Fix: `run_tool_call` returns `found` alone; the
destructure is gone. Probe after the fix: search round 5 + fetch round
1 = 6 raw citations, uniq'd to 5, stored 5 — matches the menu.

Probe lessons for next time: (1) the handoff's repro script was stale —
`Reply.new(...).enumerator` skips the user-message persistence that
`self.call` does, so the model saw an empty transcript; persist the user
message first. (2) A model that answers from memory never calls tools —
pick a question that forces search. (3) `run_tool_call` PERSISTS into
the conversation it is given — probe on a throwaway conversation, and
delete the probe rows after. All probe conversations were deleted.

## UI session, same day: the fixed shell

Separate work stream, same branch: iOS Safari viewport bugs turned into a
layout rework. The measured numbers (iPad Safari 26, ?vvdebug probe),
for whoever debugs viewport state next:

- Landing, keyboard closed: `vv.height == innerHeight == shell == 875`.
- Show page, keyboard open, pre-fix: `scrollY=69` — iOS scrolls the
  window itself on focus even with nothing scrollable, never reverts it,
  and drags `position: fixed` content out from under the chrome.
  `vv.offsetTop=0` — it was never a visual-viewport pan.
- Post-fix, show page, keyboard open: `vv.height=806`, `shell=806px`,
  `scrollY=0` held by the pin, layout correct.
- URL-bar states moved the "full" height too (875 expanded → 932
  collapsed), which is why every `vh`-family unit lied in a different
  state; Safari ships no `interactive-widget` (expected 27.1, Bram.us
  2026-09-11), so the meta tag was inert on iOS all along.

Architecture: `application.html.erb` is a fixed shell sized by
`visualViewport.height` (visual_viewport_boot.js); the document never
scrolls — the transcript panel scrolls internally, the composer is a
shell footer, and the stream reader targets the panel for all scrolling
(`scrollToBottom`, autoScroll pinning, jump-to-latest). The landing→show
Turbo.visit swap stays invisible via the reserved title row + pixel
identical renders; the row now fills with the sent question as the
working title (truncated exactly like `Conversation.start!`).

The vvdebug protocol that cracked the keyboard bug: a readout in
visual_viewport_boot.js gated behind `?vvdebug` printed `vv.height /
offsetTop / pageTop`, `innerHeight`, `scrollY`, and the shell var live
(re-attaching itself on `turbo:load`, since the visit replaces the
body). It never shipped; the exact block is parked in
`tmp/vvdebug-snippet.js` (gitignored) with paste-in instructions and
the reference numbers — resurrect it from there when debugging any
viewport state. The win came from numbers, not pixels: each screenshot
guess cost a round-trip; one readout capture ended it.

The keyboard-bug close-out, measured (rsl on iPad Safari 26 with a
Magic Keyboard attached): the floating pill at the bottom (mic, dismiss
chevron) is the software keyboard's accessory bar — the software
keyboard itself never opens with the Magic Keyboard attached, so every
state is full-height or minus-69pt, nothing in between. Steady states,
both verified correct by the readout:

- Field focused, accessory bar hidden: `vv.height == innerHeight ==
  shell == 875`, `scrollY=0` — shell fills the page, composer at the
  bottom edge.
- Field focused, accessory bar up: `vv.height=806, shell=806px,
  scrollY=0` — shell tracks the reservation exactly, composer sits
  clear above the floating bar.

The reported overlap (composer's bottom edge under the bar, e.g. the
"he is" typing capture) is the bar's APPEAR transition: iPadOS draws
the bar a beat before firing the viewport resize, so the shell lags
one frame and then catches up — a sub-second, self-healing transient.
Nothing page-side can detect the bar directly, so there is no signal
to fix it from; the settled state is correct, which the readout
proved. Ruled out along the way: window scroll (pinned at 0), visual
viewport pan (`offsetTop` stayed 0 in every capture), and a steady
`vv.height` lie (the value always matched the visible state once
settled). A stray text caret rendering at stale coordinates across
layout shifts appeared in several captures at varying positions —
cosmetic, watch only.

## Open items → registry

- Keyboard/accessory-bar bug → CLOSED, measured (see UI session
  section). Remaining action on the branch: push `rsl-citation-sources`
  + open the PR — rsl holds the push.
- Dead code riders (`marker_index`, `sawCitations`) → still in
  `roadmap.md` (Open questions).
- Stray caret artifact (cosmetic, iOS) → watch it in normal use.
- Specs for the citation chain and the shell rework → land when the
  shapes settle, per repo convention.
- The working tree's modified files → committed on
  `rsl-citation-sources`; branch awaits the maintainer's PR/merge.

## rsl's review checklist

- Conversation 79: chips under both paragraphs now carry article titles,
  not bare hosts.
- Conversation 80: both footer links open real articles; the answer's
  inline claims sit next to numbered-menu-derived chips.
- Next fresh search reply: the model's tool row shows the numbered menu;
  chips match the footer's titles.