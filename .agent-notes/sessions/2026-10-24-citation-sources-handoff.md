# Session handoff — 2026-10-24, citation source chain + reply-loop numbering

**State: Sat 2026-10-24 morning. Branch `rsl-citation-sources` holds 8
commits (citation chain + UI shell rework), unpushed — rsl holds the
push until the last UI issues settle. Working tree clean, all gates
green. Verified working on iPad: citation chain (real titled sources,
no fabricated urls), fixed shell layout, keyboard focus (scroll pinned,
shell tracks visualViewport), fresh-conversation swap, working title,
sidebar. STILL OPEN, found in live use after the matrix passed: in the
iPadOS minimized-keyboard state (accessory bar visible, software
keyboard dismissed) the composer slides down under the floating
accessory bar — suspected `visualViewport.height` mismatch or a missed
resize event on that transition, unmeasured. Also a cosmetic stray
caret artifact rendering at stale coordinates across layout shifts.
Next act: reproduce the minimized-keyboard state with the ?vvdebug
readout (see UI session section for the protocol and past numbers),
fix from the measured values, then push + PR. The inherited handoff
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
body). It was removed before committing — resurrect it from git history
(the commit that added the pin, or this file's numbers) when debugging
the minimized-keyboard state. The win came from numbers, not pixels:
each screenshot guess cost a round-trip; one readout capture ended it.

Interpretation trail for the open bug, from the pre-fix screenshot
sequence (unconfirmed — the vvdebug capture supersedes it): the working
theory for the composer-under-accessory overlap is the iPadOS
minimized-keyboard transition — software keyboard dismissed, floating
accessory bar remaining — where either `visualViewport.height` reports
more than the accessory actually covers or the resize event doesn't
fire on that transition. Shot pairs read as: keyboard fully open
(composer high, clear gap), then typing state (composer slid down,
bottom edge under the accessory). Ruled out along the way: window
scroll (pinned at 0 by the boot script), visual-viewport pan
(`offsetTop` stayed 0 in every capture), and shell height mismatch in
the fully-open state (shell tracked `vv.height` exactly). A stray text
caret rendering at stale coordinates across layout shifts appeared in
several captures at varying positions — logged as cosmetic, watch it
after the keyboard-state fix lands.

## Open items → registry

- Minimized-keyboard overlap (above) → next session's first act; then
  push `rsl-citation-sources` + open the PR (rsl holds the push).
- Dead code riders (`marker_index`, `sawCitations`) → still in
  `roadmap.md` (Open questions).
- Stray caret artifact (cosmetic, iOS) → watch it; fix only if it
  survives the keyboard-state fix.
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