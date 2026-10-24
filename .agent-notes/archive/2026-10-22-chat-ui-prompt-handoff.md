# Session handoff — 2026-10-22, 3a UI + prompt rework + 2b tools + SearXNG + steering + citations + lifecycle

**State: `rsl-schema-models` carries thirty-five unpushed commits on top
of `main` (`43678d3`) — phases 1, 2a, 3a, 2b, 4 are built and
live-verified; this session added tool calling, SearXNG, steering,
per-paragraph citation chips, conversation archive lifecycle, retry,
thinking states, Cmd+Enter, and the New button. All gates green
throughout (rubocop, reek, herb, lefthook). Not merged: push + PR
remain rsl's call — he has explicitly held pushing. The session's own
handoff is this file — uncommitted, the working tree's boundary.**

## Built

- **GoodJob worker proc (a2fe4b0, closes the roadmap open item):** dev
  `execution_mode :external`; bin/jobs is a GoodJob CLI (constant is
  `GoodJob::CLI`, uppercase); puma.rb solid_queue leftover deleted.
  bin/dev's daemon manages web + worker as a pair (separate pidfiles,
  shared log). Bonus fix: the daemon now passes PORT into the spawned web
  process — previously `bin/dev start` from a shell without the exports
  booted Puma on 3000 while the port file said 1917.
- **Tailwind (1bb5d1a):** tailwindcss-rails, no Node. Gotchas paid for:
  the global `BUNDLE_FORCE_RUBY_PLATFORM` export hides the binary
  platform gem (override per-invocation); the gem's installer clobbers
  bin/dev with a foreman template (reverted) and its watch task dies
  without stdin (bin/dev feeds it `tail -f /dev/null |`, langafile's
  pattern). The watcher is the daemon's third process.
- **Chat UI (2550fd9 + fixes):** index (recent list) + show (transcript),
  a Stimulus `stream_reader` controller doing plain fetch + SSE parse
  (`data:` JSON-string lines, `[DONE]` ends). Fresh conversations stream
  their first exchange in place, then Turbo.visit the Location header;
  follow-ups append in place. Fixes folded in: `Conversation.start!` no
  longer double-writes the user message (Reply owns user persistence —
  its eager append IS the 422 gate); the show action exists (2a shipped
  the route without it); the chat form is `data-turbo="false"` (Turbo
  Drive was submitting it twice).
- **COMRADE_LLM_ env prefix (9f70b29):** model endpoint vars renamed
  from `LLM_*` — fleet-collision-safe and self-documenting; rsl
  initially defended the `LLM_*` contract, then agreed the app is young
  enough that a rename is cheap ("documents are not laws"). exports.zsh
  aliases them to the OMLX values. Note: `config/**/*` is RuboCop-
  excluded, so config lint status is invisible to explicit-file runs.
- **LAN access (b05b6b0):** dev binds 0.0.0.0; `comrade.local` is
  advertised over Bonjour via launchd (`com.rsl.comrade-mdns`,
  KeepAlive). Key discovery: `dns-sd -R` registers a service but NOT a
  hostname A record — iOS needs `-P` (proxy form with explicit host +
  IP). The plist hardcodes 192.168.50.151; if DHCP changes the address,
  edit the plist + `launchctl kickstart -k gui/$(id -u)/com.rsl.comrade-mdns`.
  Why Bonjour and not router DNS: `studio.local` works on the iPad via
  the Mac's automatic mDNS hostname announcement, not any DNS config —
  rsl confirmed he never configured router DNS.
- **Tool calling (662cb8c, phase 2b):** the model can call `web_search`
  (SearXNG JSON, top 5) and `fetch_page` (Tavily extract, content
  truncated to 8k) mid-stream. Reply parses tool_call fragments out of
  the stream, executes up to MAX_TOOL_ROUNDS (3), and resumes with
  results in context. Persistence: the assistant's tool_calls frame goes
  in tool_payload, tool rows carry tool_name + parsed arguments +
  tool_call_id, and Conversation#to_transcript rebuilds wire-valid
  OpenAI messages from them — proven live by a resume that used fetched
  content. Stream events became structured hashes
  ({type: delta|tool|citations}); the stream-reader renders tool
  activity as "— fetched/searched" chips. Provenance slot on assistant
  turns shows "n sources" (linked, persisted in citations jsonb) or
  "from own knowledge". The prompt gained "Search only when you lack
  the facts".
- **SearXNG (60470c0 + 662cb8c, phase 4):** bare install at
  `~/dev/searxng` (Homebrew python3.12 venv — system 3.9 is too old;
  full requirements.txt, the server set misses runtime deps),
  `settings-comrade.yml` (loopback:8889, JSON format on, limiter off —
  no Redis), launchd plist `com.rsl.searxng` (KeepAlive), SEARXNG_URL
  in exports.zsh. docs/searxng.md documents it; README links it. Bug
  paid for: web_search built its request from the base URI's
  request_uri ("/" when the URL has no path) so SearXNG's 308 made the
  tool report failure — target /search explicitly. Also: the tools
  need `require 'net/http'` (Reply had it; they didn't). End-to-end
  proof: searched for the latest Ruby, cross-checked with fetch_page,
  answered "4.0.7" with five real citations.
- **UI polish round (de12203, f5e9171, 6f14d79, d3a7532):** the Comrade
  brand header moved into the layout (it disappeared on conversation
  pages); query placeholder is "What do you need, comrade?" (recovered
  from yesterday's session transcript in the opencode DB — sessions from
  `~` don't show in per-project history); content column widened to
  3xl; font sizer added — A−/A+ stepper in the header corner scales the
  ROOT font size in 12.5% steps, all text is rem-based so everything
  scales together, persisted in localStorage, restored before first
  paint by `app/assets/javascripts/font_scale_boot.js` (Herb bans inline
  scripts; the file lives in app/assets so Propshaft serves it —
  creating the directory after boot requires a server restart to pick up
  the load path). Foreman was rejected for process management: two
  process managers (foreman foreground + hand-rolled daemon) is worse
  than one; bin/dev already owns daemon/status/logs.

## The system prompt (6e201bb, 124ee67)

Reworked line by line with rsl. The full current file is short — read
it; the decisions behind it are the inheritance:

- Positive rules over negation: models follow "plain words, short
  sentences" better than a chain of no's; negations kept only where
  they're real bans.
- "Answer at the size of the question" kills the mini-essay failure
  mode and makes the no-trailing-offer rule safe — depth is sequenced
  (the user's next question IS the "want deeper"), never teased.
- Genuine ambiguity earns a clarifying question; everything else gets
  the most likely reading with the assumption surfaced. A confident
  wrong answer is the product's worst outcome.
- Engagement bait got its own line: "Say the answer, then stop" —
  positive frame first, ban list naming the four reflexes (hooks,
  flattery, recaps, trailing offers). rsl's core product concern;
  negation-chains under-weight it.
- Register: "use words the reader asked for; never reach for impressive
  ones, never condescend" — bans costume vocab without banning precise
  technical terms, and kills the dumbing-down failure mode.
- "Never invent sources; own-knowledge answers say so" — added pre-2b
  so confabulated references never exist even before the UI shows
  provenance.
- The trailing-offer question ("let me know if you want deeper?") was
  discussed and REJECTED — models make it every-reply boilerplate, and
  boilerplate closers are engagement bait with a signature.

## Planned, not built

- **Provenance-as-citation UI (2b):** superseded — shipped, then
  redesigned into per-paragraph chips (see Built).
- **Onboarding flow (later phase):** single page, one-question-at-a-time
  (mirroring how rsl thinks — single questions revealing as each is
  answered), captures name + tone/jargon-level preference, writes the
  tone section of `comrade_prompt.custom.md` (the file is the store; no
  DB, no config vars). The shipped prompt stays generic with a neutral
  register line; onboarding specializes it. Small by explicit request.
  NOT yet in the roadmap (rsl said not yet).
- **Streaming-time marker flicker:** inline [n] markers show as literal
  text during the stream and get consumed at [DONE]. If the flicker
  bothers rsl live, the fix is a split-marker buffer that strips deltas
  as they arrive. Not requested yet.
- **Citation markdown:** the model writes **bold** that renders as
  literal asterisks. Full markdown rendering is a can of worms; leave
  unless rsl asks.

## Phase plan

Order 1 → 2a → 3a → 2b → 4 → 5. Phases 1, 2a, 3a, 2b, 4 are built.
Next is 5 (polish for OSS): specs (loop + tools, VCR/WebMock against
SearXNG/oMLX shapes — shapes are now settled, per the testing law), CI
reek + herb steps, Dependabot re-enable, README setup verified from a
fresh clone. Note for specs: the reply loop gained tool rounds,
steering, retry, and the citation footer parser — test the seam
contracts, not prose rendering.

## rsl's review checklist

- Push + PR the branch when ready (thirty-five commits; rsl has
  explicitly held pushing so far — ask, don't push).
- Archive flow: archive a conversation from its header, find it under
  "archived conversations" (link at the bottom of recents), unarchive
  it, or destroy it after the confirm. Reply to an archived thread and
  watch it resurrect.
- Steering: send a long question, interrupt mid-stream with "stop —
  answer this instead", and watch the partial persist + the fresh
  answer follow the steer.
- Citations: ask something current; paragraphs carry quiet "sources:"
  chips; the model's own footer never shows.
- Retry: hard to trigger honestly (a bin/dev restart mid-submit does
  it) — the failed turn offers "reply failed — retry?".
- Thinking state: visible between submit and first delta, and after
  each tool chip.
- iPad: `http://comrade.local:1917` over Bonjour still works.

## Open items → registries

- Phase plan: 2b and 4 done; next is 5 (registry: roadmap.md phases).
- Onboarding: deliberately NOT promoted — rsl said "not yet"; it lives
  in this handoff's Planned section. Next session: if rsl hasn't
  promoted it, ask once.
- Provenance UI: shipped and since redesigned (chips); roadmap needs no
  entry — the work is committed with shas.
- No open bugs. The one transient ("The reply failed" after a mid-session
  server restart) became the retry feature.

## Session-end notes

- Working tree at close-out: only this handoff uncommitted (the
  boundary). Test conversations were cleaned as they were created; conv
  34 (Ruby version, three cited turns) left in the DB deliberately as a
  live demo of citation chips.
- Dev state: bin/dev running (web + jobs + tailwind), SearXNG on 8889
  under launchd, oMLX answering on 8888.