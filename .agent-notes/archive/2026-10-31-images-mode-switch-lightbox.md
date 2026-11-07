# Session handoff — 2026-10-31: the images, the mode switch, the lightbox

**State: Sat 2026-10-31. Branch `rsl-reasoning-effort`
(PR #15, open) carries twenty-six unpushed commits — three new this
session: `3b9bcb3` shared SearXNG pacing, `558f605` the images build
(the whole feature arc in one commit; the shared files made finer
splits fiction), `d03b1e1` the archived 10-30 handoff. Everything
committed; gates clean; no specs (shape-first, live-turn
verification). The 10-30 handoff was consumed and archived by this
session — its images request is what this session built.**

**Archived 2026-11-07.** PR #15 merged (`5f8d21e`), review comments
addressed, CI green. The checklist below was discharged by rsl's PR
review; the commit-count and unpushed state in the header are
superseded. Its images request is what the 10-31 session built, and
what merged today.

## Built

- **Serving** (`Comrade::ImageProxy` + `ImagesController`, route
  `GET /img/:key?p=<url>`): a proxied URL is the source URL plus a
  truncated HMAC-SHA256 signature keyed off `secret_key_base` —
  stateless, no table, nothing forgeable (unsigned requests 400
  before any fetch). On miss: server-side fetch (10s/20s timeouts, 3
  redirects, image content-types only, 10 MB cap), cache under
  `storage/images/<key>.<ext>`, 30-day public cache headers. AVIF
  admitted (origin CDNs serve it while thumbnail CDNs re-encode to
  jpeg); `image/jpg` normalized; SVG excluded deliberately — inline
  SVG from a foreign origin is a script vector. Rejections log
  (`[image_proxy] rejected …`) instead of swallowing. Cleanup rule:
  none yet (rider).
- **The tool** (`Comrade::Tools::ImageSearch`): SearXNG
  `categories=images`, top 6, `resolution` parsed — smallest reported
  dimension under 200 (`MIN_DIMENSION`, tunable) drops; unsized
  results stay. `img_src`/`thumbnail_src` resolved absolute. Shares
  the `Pacing` floor with WebSearch (extracted — one SearXNG, one
  throttle).
- **The reply loop**: the dispatch contract grew a third slot
  (`[result, citations, extra]`) — the extra carries jsonb for the
  tool row; image results persist raw (`title, page, src, thumbnail`)
  and never join citation numbering (plain `1.` `2.` list; `[n]`
  stays the text sources' system). A new `images` SSE event carries
  proxied URLs (`ImageProxy.view`).
- **Display**: a thumbnail strip renders under the turn's chip group,
  ahead of the answer — byte-identical twins (server from the row's
  payload via `image_strip`/`strip_button`, live from the event via
  `imageStripHtml`; verified by comparing the live strip's outerHTML
  against the reloaded render). Thumbnails proxied, `h-24`, lazy,
  horizontal-scroll. Tap opens the lightbox (`lightbox` controller on
  `<body>` so both renders' thumbs reach it): dark scrim, full-size
  proxied image, caption, `n / m` counter; navigation within the
  opened strip — left/right arrow keys (inert while hidden), swipes
  (a swipe suppresses its own scrim click), full-height edge chevron
  bands pinned to the screen sides; ends clamp, not wrap. Full-size
  load failures fall back to the known-good thumbnail
  (`data-thumb-url` rides every strip button, both twins).
- **The mode switch**: a composer-adjacent `all | images` segmented
  pill — a middle segment of the bar (no radius, `self-stretch` to
  the textarea's height; active side `font-medium`, backgrounds
  unified). "all" names the unforced toolbox — knowledge, web, fetch,
  the model's pick — so no turn is mislabeled (rsl rejected "web":
  most turns never search). Per-turn: reverts on send like the
  composer clearing; retry replays its mode (`this.failed` carries
  it). Image mode is HARD: the wire offers only `IMAGE_DEFINITIONS`
  (image tool + page fetch, no web search) and
  `IMAGE_MODE_DIRECTIVE` rides after the transcript via
  `wire_request`'s generalized `system_lines:` slot. The model keeps
  its own unprompted image search (10-30 direction call 3 stands).
- **Provenance contract, hard separation** (rsl's call after the seam
  surfaced: an images-only turn was writing a Sources: footer and the
  footer fallback rendered image pages as text-source chips): image
  results are never `[n]` sources and never enter a Sources footer,
  whether or not text search rode the same turn. The prompt file
  states it; the directive repeats it. Verified: an image-mode turn
  ran two searches, answered briefly, wrote no footer.
- **The prompt inspector stays honest**: image-mode turns record
  `mode: 'images'` in stats (jsonb key), and `rebuilt_request` swaps
  in `IMAGE_DEFINITIONS` plus the directive.
- **Docs ride-alongs**: `docs/architecture.md`'s Ruby-names section
  carries ImageSearch, Pacing, and the proxy; `config/comrade_prompt.md`
  gained the image-tool paragraph (titles not pixels; never a source).

## Lessons (2026-10-31)

- **Tailwind's watcher only generates classes it sees as literals** —
  a class built by interpolating the side (`${side}-3`) shipped a
  button with no offsets at all (it landed dead-center of the flex
  flow). Write per-side class strings out in full.
- **Byte-twin escapes must match on both sides**: the strip helper
  uses `html_escape` (& " ' < >); the JS twin's `escape()` must
  replicate the same set or the Turbo.visit swap reflows.
- **A safe-string lost in a join**: marking one button `html_safe`
  wasn't enough — `Array#join` returns an unsafe String, so the
  wrapper (`image_strip`) carries the `html_safe` and its
  `Rails/OutputSafety` disable.
- **Per-file reek lies; trust `bin/quality`**: whole-repo reek exits 0
  while `reek <file>` reports warnings the gate doesn't see.
- The dev-server reload gotcha bit twice again (service-class changes
  silent until `bin/dev restart`).

## Planned, not built (in `roadmap.md`)

- **"Check provenance"** (rsl calls it a great feature): user-initiated
  check on a searched image — the image twin of the double-check/
  go-deeper canned turns. A link rides the lightbox caption; the
  canned turn drives a `provenance_check` tool with layered findings,
  each labeled by method: C2PA/generator sniff from the proxy's
  cached bytes (positive claims only — absence proves nothing);
  TinEye reverse search for other occurrences and the oldest indexed
  appearance (paid API, `COMRADE_TINEYE_API_KEY`, second key after
  Tavily; oldest crawl ≠ true origin); VLM observational pass (GLM is
  multimodal — confirmed in use; only comrade's lane passing image
  content parts through oMLX needs a one-probe check) — observations,
  never verdicts. Pixel ML classifiers and SynthID ruled out with
  reasons recorded in the roadmap entry.

## rsl's review checklist

- Toggle images mode, send a picture ask: two image chips ("searched
  images for …"), a thumbnail strip, a brief answer, no Sources:
  footer; the switch reverts to all after sending.
- Open thumbnails in the lightbox: full-size image, caption, counter;
  arrow keys, swipes, and the edge chevrons walk the strip; ends
  clamp; Escape/tap closes.
- Any image that errors in the lightbox now falls back to its
  thumbnail instead of showing broken.
- A web-mode turn still searches and cites as before.
- Real-device (iPad) pass still owed from the 10-30 session's list.

## Open items → registries

All in `roadmap.md` (untracked): the pre-existing riders (SearXNG
degradation, reek gate gap, dead-code riders, stray iOS caret, oMLX
stability, copy-tweaking stage, preamble home, real-device
re-verify, attachments' vision-shape probe) plus this session's new
entry — check provenance (see above). "From model knowledge" action-
line copy on images-only turns reads wrong (the words are knowledge,
the pictures are searched) — left for the copy-tweaking stage, rsl's
eye. Meta pending: nothing. The handoff itself stays uncommitted per
protocol.