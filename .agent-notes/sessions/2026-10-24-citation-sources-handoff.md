# Session handoff — 2026-10-24, citation source chain + reply-loop numbering

**State: PR #7 merged to `main` (d29cb29) in the prior session; this
session reproduced, root-caused, and fixed the citations-shrink bug,
committed everything on branch `rsl-citation-sources` (chip-title fix,
numbered-source menu + fix, README model-name correction, this handoff),
and left the branch for the maintainer's PR/merge. All gates clean.
The inherited handoff
(`2026-10-23-quality-review-erb-rewrite`) is superseded — PR #7 merged —
and archived.**

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

## Open items → registry

- Citations-shrink bug → SOLVED this session (see above); struck from
  `roadmap.md`.
- Dead code riders (`marker_index`, `sawCitations`) → still in
  `roadmap.md` (Open questions).
- The working tree's modified files → committed on
  `rsl-citation-sources`; branch awaits the maintainer's PR/merge.

## rsl's review checklist

- Conversation 79: chips under both paragraphs now carry article titles,
  not bare hosts.
- Conversation 80: both footer links open real articles; the answer's
  inline claims sit next to numbered-menu-derived chips.
- Next fresh search reply: the model's tool row shows the numbered menu;
  chips match the footer's titles.