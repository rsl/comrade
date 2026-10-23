# Session handoff — 2026-10-22 (evening), Soviet UI mock + stream-chip rework + env repair

**State: branch `rsl-ui-sidebar-mock` (cut from `rsl-schema-models` at
`18cd16e`) carries this session's work UNCOMMITTED — 14 modified files
plus vendored `vendor/javascript/marked.js` and the importmap pin.
`rsl-schema-models` holds ~35 unpushed commits awaiting rsl's push/PR
call. Gates NOT run this session. Prior handoff
(`2026-10-22-chat-ui-prompt-handoff.md`) archived; its items were built
over or promoted.**

## Built (all uncommitted, on the mock branch)

- **Right sidebar** (`layouts/application.html.erb`): persistent 240px
  panel on the right — gold wordmark + "+ New" chip, Recent Conversations
  (active highlighted `bg-soviet/30`), Archived link, font-sizer footer.
  No top chrome on desktop. Phone/narrow arrangement NOT built (see
  Planned).
- **Palette** (`app/assets/tailwind/application.css`): `--color-ground:
  #170505`, `--color-ground-raised: #230a0a` (soviet red sunk to
  ~8%/14% over black — surfaces "hum the same hue", rsl loved it);
  `--color-soviet: #cc0000` (renamed from "blood"); `--color-gold:
  #c9a227`; `--color-ground-bright` = color-mix(ground 90%, white) for
  hairlines; `--color-cream`/`-bright` DEFINED BUT UNUSED (cream composer
  tried, reverted to white/gray). Decisions: bright red beats dark blood
  (#8b1a1a "read almost purple"); borders died everywhere except the
  knowledge divider; buttons are borderless `soviet/20` → `soviet/50`
  hover.

- **Composer**: input + Ask flush (`rounded-l-lg`/`rounded-r-lg`, no
  gap). Input `neutral-300` → `neutral-100` on focus; `cursor-pointer`
  on all buttons (Tailwind v4 dropped it). Ask `soviet/50` → pure soviet
  hover; textarea focus lifts button via `peer-focus:bg-soviet/80`.
- **Markdown**: `commonmarker` gem (2.x API: `Commonmarker.to_html`, raw
  HTML omitted by default) server-side in `cited_paragraphs`; `marked`
  (vendored, importmap pin) client-side in `renderCitations` — text
  escaped BEFORE parse so model output can't smuggle live HTML. Two
  render paths (server `_message.html.erb` / client `renderCitations`);
  keep in sync.

- **Stream/chip lifecycle** (`stream_reader_controller.js`): each tool
  event finalizes the current text div (un-faints), appends the chip,
  opens a FRESH div — `contentEl` tracks the live target and
  `renderCitations` formats `this.contentEl` (NOT
  `answer.querySelector("div")` — that was the double-render bug).
  `partial` resets at each tool event (finalization/steering carry only
  the answering pass). `needsBreak` gone. Server groups consecutive tool
  rows into the FOLLOWING message (`tool_notes:` local in `_chat`, chips
  under the COMRADE label in `_message`); blank tool_calls frames don't
  flush pending chips. Chip classes identical live vs server (`mb-1 …
  last:mb-3`), only color differs: live `neutral-700` → `neutral-500`
  at completion via `.tool-chip` swap.

- **Thinking indicator**: pinned first in the turn (under the label),
  never drifts; visible the ENTIRE stream ("still working" heartbeat per
  rsl); hidden only at [DONE]/failure/retry. In-flight answer text is
  `neutral-800` faint, snapping to full color at finalization. Up-arrow
  in the textarea recalls sent messages (shell-style, draft preserved;
  ArrowDown walks forward).
- **Scroll**: stick-to-bottom — scrolling up during a stream pauses it
  and raises a floating "↓ latest" chip (`.jump-latest`, fixed
  bottom-right); clicking it or scrolling home re-pins. Sending always
  re-pins.
- **Alignment/landing**: empty index centers the greeting; first submit
  drops `justify-center` and removes `.greeting` — the only shift is
  user-caused. Fresh pages render an invisible spacer matching the show
  page's title/archive line so the post-reply Turbo visit doesn't shove
  content down.
- **RecordNotFound rescue** (`ApplicationController`): redirects home
  with alert; verified 302 on a bad id.
- **max_tokens: 8192** in `Reply.payload` (endpoint default 1024 was the
  truncated-answer root cause); prompt gained a "finish what you start"
  line.

## The env-repair story (bit twice, will bite again)

`bin/dev` MUST be started from a shell that sourced
`~/.oh-my-zsh/custom/exports.zsh` — it carries `SEARXNG_URL`,
`COMRADE_LLM_*`, `COMRADE_PORT`. This session killed the rsl-started
server and restarted from the agent shell: search silently returned
"(no results)" (tool content came back empty) until the restart was
redone as `zsh -c 'source ~/.oh-my-zsh/custom/exports.zsh; nohup bin/dev
> tmp/dev-server.log 2>&1 &'`. Current server (puma pid on 1917) HAS
the env — verified via `ps eww`. Candidate AGENTS.md gotcha.

## rsl's review checklist

- iPad Safari: sidebar, palette, composer unit, chips tightness,
  streaming faint→color, thinking heartbeat, up-arrow recall, ↓ latest
  chip (scroll up mid-stream).
- Reload a tool-heavy conversation: chips grouped under COMRADE, no
  whitespace surprises, markers consumed, no duplication.
- Run gates before any commit: `rubocop`, `reek`, `herb` (new views and
  the `_chat` grouping logic will need passes).

## Open items → registry (promoted to `.agent-notes/roadmap.md`)

- Phone/narrow drawer arrangement (design agreed in session).
- Commit sort + PR for both branches (rsl's call).
- Stale `tailwindcss:watch` processes accumulate — cleanup sometime.
- Cream tokens kept though unused — revisit or delete later.

## Planned, not built

- Phone/narrow: same sidebar goes off-canvas from the right below ~768px,
  thin top bar (wordmark + menu), scrim, edge-swipe; the sidebar is one
  component in both arrangements. Discussed and agreed this session;
  nothing built.