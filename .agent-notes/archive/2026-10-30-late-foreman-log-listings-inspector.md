# Session handoff — 2026-10-30, late: the foreman remembers, the listings, the inspector

**State: Sat 2026-10-31. Branch `rsl-reasoning-effort`
(PR #15, open) carries twenty-three unpushed commits — everything below
committed. Uncommitted in the tree: the images build (see the second
addendum) and this handoff. Since the
original write of this doc: `08d6764` the listing consolidation landed
(with direct destroy), then `3245a4f` the AGENTS.md tailwind-watcher
rule, `7b8cef2` the wire-request transcript fix (see the addendum at
the bottom), `89bd379` the resizable sidebar (docked right, iPad
touch-robust), `4a50208` the foreman folded into the action line, and
10-31: `aee49ad` the listing title spacer plus `1fd9c56` the
citation-marker whitespace fix (both formerly open items, now
resolved). Gates clean; no specs (shape-first, live-turn verification).
Pushing is rsl's.**

The consumed 10-30 foreman handoff is archived this session
(`.agent-notes/archive/2026-10-30-foreman-status-and-sources.md`); its
open items were verified into `roadmap.md` throughout the day.

## Built

- **Foreman's log persistence** (`62d73f4`): the server accumulates the
  client's timestamped lines (turn accepted, first token, tool rounds)
  into `stats.log`; the status line survives completion — clock frozen
  to the server's total, dot quiet, live log swapped for the persisted
  one at `[DONE]` — and `_message.html.erb` renders the twin on the
  latest answer carrying stats. Byte-identical across the Turbo.visit
  swap, verified live. Failure and steering still tear it down.
  Decision in passing: the completed status line is a pure function of
  the persisted stats ("fast lane · 0:04") so the swap can never
  reflow.

(See the next sections; this doc is written in parts due to length.)

- **Archives rework** (`a20ce95` + uncommitted tail): ordered by
  created_at (when asked), NOT archived_at — rsl flip-flopped on the
  key and settled on ask-order; the date column and the
  Today/Yesterday/week buckets all key on created_at. Rows show the
  conversation's whole first prompt line (`archive_line` — first
  non-blank line of the first user turn), not the 50-char title;
  baseline-aligned (`items-baseline` fixed the whitespace jumble).
  `config.time_zone` hardcoded Eastern, comment names the escape
  hatch.
- **Listing consolidation** (uncommitted, rsl-shaped): index is THE one
  action — `/conversations/all` and `/conversations/archived` are index
  with the mode riding as a ROUTE DEFAULT (static path segments never
  become params — that's why the old `params[:archived]` branch was
  dead code). One `_conversation_list` partial serves both;
  `archived.html.erb` deleted; the dead limit-20 chat-root query is
  gone. Sidebar: "Recent" header, "All" / "Archived" justified links.
  Listing pages: gold title (Comrade-wordmark style), opposite
  listing's link top-right, rows carrying Archive-or-Unarchive plus
  Destroy.
- **Direct destroy** (uncommitted): the two-step doctrine is RETIRED —
  destroy reaches live conversations too, the confirm dialog is the
  guard. rsl: "why force someone to archive in order to destroy if they
  know they want it gone??"
- **Prompt inspector** (`3891043`): a `· prompt` link rides the stats
  segment (both renders, byte-identical twins; the row id rides the
  stats event wire-only — jsonb stays clean) and opens the turn's wire
  request rebuilt from the transcript before the answer row plus the
  CURRENT prompt file and prefs. Reconstruction, not snapshot — the
  page says so. `wire_request` extracted, shared with the live payload;
  `to_transcript` gained `before:`. Two live-caught bugs: the route
  helper is `prompt_conversation_message_path` (member routes name the
  action first), and `link_to` inside string interpolation loses its
  html_safe flag (use `safe_join`).
- **AGENTS.md** (`20702ed`): commits happen only on rsl's explicit
  word, no prodding afterward. Also `b5eca77` (bin/dev reload gotcha)
  and `3dfe2dd` (amend-rule rewording).

## The Turbo twin-id lesson (2026-10-30)

The archive action's `turbo_stream.remove(dom_id)` no-oped on the
listing pages: the sidebar's rows share the same dom_id and Turbo
removes only the first id match (aside renders before main). Listing
rows now carry `listing_#{dom_id}` and the archive action removes both
targets; a remove with no target no-ops silently. Note: a native
`button_to` submit arrives as TURBO_STREAM just like a
`data-turbo-method` link — format wasn't the differentiator, the target
id was.

## rsl's review checklist

- Send a turn: status line below the text survives completion with the
  frozen clock; click opens the log; reload keeps it clickable from the
  server render; footer carries the stats segment and the `· prompt`
  link — live and reload identical.
- Open the prompt page from an answer's footer link: full wire request,
  scroll reaches the end.
- Sidebar "Recent" with "All" / "Archived"; both listing pages: gold
  title, opposite link top-right, full prompt lines, baseline-aligned
  rows, Archive/Unarchive + Destroy working in place.

## Open items → registries

All in `roadmap.md` (untracked): SearXNG degradation, reek gate gap,
dead-code riders, stray iOS caret, oMLX stability, copy-tweaking stage,
preamble permanent home, real-device re-verify. Resolved 10-31
(`aee49ad`, `1fd9c56`): the listing title spacer is reserved, and the
`[n]`-strip no longer leaves a space before punctuation ("redocks it
." → "redocks it.") — the gsub twins consume the whitespace before the
marker; visibleText uses horizontal-whitespace-only so the streaming
preview can't eat paragraph breaks. Meta pending: nothing.

Uncommitted (this session's tail): `conversations_controller.rb`,
`conversations_helper.rb`, `index.html.erb`,
`_conversation_list.html.erb` (new), `application.html.erb`,
`config/routes.rb`, `archived.html.erb` (deleted), plus the archived
handoff's git mv. All verified live; gates clean. Per protocol the
handoff itself stays uncommitted. — Committed since: `08d6764`.

## Addendum — continuation past midnight

- **The searches went insane, and it was comrade's, not the model
  server's.** The prompt inspector's `wire_request` extraction had
  dropped `messages.concat(@conversation.to_transcript)` — every live
  turn rode the system prompt and prefs only. The model answered
  questions nobody asked (Ottoman wars, Mercedes M117, GSC indexing) or
  said "I don't have a question yet". oMLX's log was the tell: every
  pass of every broken turn was `prompt: 944`. Fixed in `7b8cef2`;
  verified live (`prompt: 954`, the answer matched the question).
- **Sidebar resizable, docked right** (`89bd379`): drag divider, 180–420px
  clamp, localStorage + pre-paint boot restore, window-level drag
  listeners (pointer capture died on iPadOS), 8px hairline with an 8px
  transparent reach each side for a 24px touch target. Commit message
  has the details.
- **The foreman merged into the action line** (`4a50208`): no separate
  stood status line — the dot opens the action line, the total time
  toggles the log, the prompt link is gone from the renders (page and
  route stay reachable by URL).
- **~~Open: the `resize-test` enlistee~~ — resolved 10-31: gone from
  the dev DB (destroyed).

## Next session — rsl's request

- **Serving/showing/searching images.** rsl wants comrade to handle
  images: serve them, show them in the transcript, and search them.
  The scope conversation happened 10-31 — three direction calls
  settled, none built yet:
  1. **Serving: comrade fetches and serves images itself.** A new
     fetch-and-serve route; devices never talk to image hosts
     directly (fits comrade's traffic posture, avoids hotlink
     blocks). Browser-loads-directly was rejected: leaks viewer IPs
     to image hosts, broken pictures routinely.
  2. **Display: small inline thumbnails, tap to enlarge.** Search
     results are mostly thumbnails; answers stay text-led. Full-
     width-in-flow rejected: dominates the screen. The twins
     discipline applies — the live render and the saved render must
     stay byte-identical.
  3. **Search: a separate image-search tool.** The model calls it
     when pictures would help, the way it calls text search; its own
     tool-note chip. Folding images into every text search was
     rejected: silent overhead, images nobody sees, noisier prompt.
  Build-time riders parked: where fetched copies live and their
  cleanup rule, the tap-to-enlarge interaction, thumbnail sizing and
  lazy loading, the SearXNG images wiring inside the new tool.

## Addendum — 10-31, later: the images build

The section above is built — all three direction calls landed, plus
every parked rider settled along the way. Uncommitted; verified live
(two turns with two image searches each), gates clean.

- **Serving** (`Comrade::ImageProxy` + `ImagesController`, route
  `GET /img/:key?p=<url>`): a proxied URL is the source URL plus a
  truncated HMAC-SHA256 signature keyed off `secret_key_base` —
  stateless, no table, no Active Storage, nothing forgeable
  (unsigned requests are 400'd before any fetch). On miss the
  controller fetches server-side (10s/20s timeouts, 3 redirects,
  image content-types only, 10 MB cap) and caches the copy under
  `storage/images/<key>.<ext>`. Copies serve with 30-day public
  cache headers — same bytes forever for a given signed URL. Rider
  settled: no cleanup rule yet (disk is cheap here).
- **The tool** (`Comrade::Tools::ImageSearch`): SearXNG
  `categories=images`, top 6, `img_src`/`thumbnail_src` resolved
  absolute (some engines return protocol-relative paths), thumbnail
  falls back to the full image. Pacing extracted from WebSearch into
  `Comrade::Tools::Pacing` — one shared floor, one SearXNG. The
  dispatch contract grew a third slot (`[result, citations, extra]`):
  the image list persists raw on the tool row's payload
  (`images: [title, page, src, thumbnail]`), the wire event carries
  proxied URLs. Image results never join citation numbering — the
  result list is numbered `1.` `2.`, not `[n]`, and the prompt file
  now tells the model it gets titles, not pixels, and never to cite
  images as sources.
- **Display**: a new `images` SSE event; the strip renders under the
  turn's chip group, ahead of the answer — server side from
  `tool_payload` via the helper, live side from the event, byte-for-
  byte twins (verified by comparing the live strip's outerHTML
  against the reloaded render). Thumbnails are proxied `thumbnail`
  URLs, `h-24`, lazy, horizontal-scroll row. Tap opens the
  lightbox: a new `lightbox` Stimulus controller lives on `<body>`
  (so both renders' thumbs reach it), overlay built lazily on first
  open, dark scrim, full-size proxied image, caption beneath, tap
  or Escape dismisses. Later the same day, rsl's ask: navigation
  within the opened strip — left/right arrow keys, horizontal
  swipes (a swipe suppresses its own scrim click), and edge
  chevrons with an `n / m` counter — the chevrons are full-height edge
  bands pinned to the screen sides, matching the lightbox's own
  footprint; ends clamp rather than wrap; arrows are inert while the
  overlay is hidden. Verified with an injected-strip fixture (no model
  turn needed): keys, chevrons, clamp, swipe navigation, and the
  swipe-then-close sequence pass. Geometry lesson on the way:
  Tailwind's watcher only generates classes it sees as literals — a
  class built by interpolating the side (`${side}-3`) shipped a
  button with no offsets at all; write per-side class strings out in
  full. Same day, rsl's bug report — some images error in the
  lightbox while their thumbnails load: the two ride different
  sources (thumb = a re-encoding CDN that always serves jpeg; full =
  the origin host, which 403s hotlinks, serves avif, or exceeds the
  cap). Fixes: avif admitted to the proxy's allowlist (image/jpg
  normalized), rejections logged instead of swallowed, and the
  lightbox falls back to the known-good thumbnail (`data-thumb-url`
  rides the strip buttons, both twins) when the full-size fails —
  the reader always sees the picture, worst case at lower resolution.
  Minimum size for results: SearXNG's image engines report each
  picture's resolution, so ImageSearch drops anything whose smallest
  reported dimension is under 200 (`MIN_DIMENSION`, tunable) — tiny
  icons and spacer gifs never reach the strip; results reporting no
  resolution stay in.
- **Probe lessons**: the reek gate gap in the registry — the
  per-file reek runs during this build showed warnings the
  whole-repo gate doesn't; trust `bin/quality`. And the dev-server
  reload gotcha bit twice in one hour (service-class changes
  silent until `bin/dev restart`).

## Addendum — 10-31, latest: the search-mode switch, the provenance rule

rsl reviewed the images build and took it a step back: "there's no UI
element to switch/pick what searches" — the 10-31 direction call 3 had
settled agent-side invocation only, and he read it Google-style (a
reader-facing mode). Four direction calls settled and built the same
day:

- **A web/images switch rides the composer** (between the textarea and
  Ask) on the chat surfaces — the mode is part of the question.
- **Per-turn**: it reverts to web on send, like the composer clearing;
  a retried turn replays its mode (`this.failed` carries it).
- **Hard binding**: in image mode the wire request offers only
  `IMAGE_DEFINITIONS` (image tool + page fetch; web search is off the
  table) and an `IMAGE_MODE_DIRECTIVE` system line rides after the
  transcript — search images, let the pictures carry the answer, no
  [n], no Sources: footer. Verified live: an image-mode turn ran two
  image searches, answered briefly, wrote no footer.
- **The model keeps its unprompted image_search tool** — the switch is
  additive; direction call 3 stands.
- **Provenance contract, hard separation** (rsl picked it after the
  seam surfaced): image results never enter the Sources: system.
  The prompt file states it (image pages never take [n] nor a footer
  slot, whether or not text search rode the same turn), the directive
  repeats it, and the result list is numbered `1.` `2.` — [n] stays
  the text sources' system.
- **The prompt inspector stays honest**: image-mode turns record
  `mode: 'images'` in stats (jsonb key, wire-invisible otherwise),
  and the rebuild swaps in `IMAGE_DEFINITIONS` plus the directive.
  `wire_request` generalized its appended-system-lines slot to
  `system_lines:` (mode directive, then the cap-pass directive).

Rider surfaced, not resolved: the action line on an images-only turn
reads "From model knowledge" — true of the words, false of the
pictures. Copy is the copy-tweaking stage's; left for rsl's eye.