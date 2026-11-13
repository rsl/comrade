# Comrade — agent rules

## What this is

A self-hosted web-search chat: your local model (any OpenAI-compatible
endpoint), SearXNG results, Tavily page fetches, streamed answers with
citations. AGPL-3.0. Personal tool, built public-first.

## Stack facts

- Rails 8.1, Ruby 4.0, PostgreSQL. No Redis anywhere, ever — GoodJob for
  jobs, Solid Cache + Solid Cable for the rest.
- Model endpoint: `COMRADE_LLM_BASE_URL` / `COMRADE_LLM_API_KEY` /
  `COMRADE_LLM_MODEL` from ENV, any OpenAI-compatible endpoint. Fast and
  slow lanes extend it per turn: `COMRADE_LLM_FAST_*` / `COMRADE_LLM_SLOW_*`.
  Never hardcode provider names, host names, or ports in Ruby.
- Search: SearXNG (`COMRADE_SEARCH_URL`), page fetch via Tavily
  (`COMRADE_FETCH_API_KEY` from ENV).
- Linting: RuboCop (`.rubocop.yml`, with a project-local custom cop in
  `lib/rubocop/cop/`), Reek, Herb, lefthook pre-commit. All four must
  stay clean; run them before saying done.
- Dev server: `bin/dev` serves on the dev port — the port is deployment
  config, set in the operator's env, never in docs. Precedence: `-p`
  flag > ambient `PORT` > Rails' 3000. Dev binds 0.0.0.0 so fleet
  devices reach it. Lifecycle is daemon-only: start/stop/restart through
  `bin/dev` — killing puma directly orphans the Tailwind watcher. A
  supervisor process respawns crashed children (web, jobs, tailwind);
  a child that dies five times running is given up on with a log line
  — fix the cause and `bin/dev restart`.
- Env inheritance is a snapshot at process launch: shells spawned by an
  opencode session already carry the operator's exports — re-sourcing is
  only needed when `exports.zsh` gained keys after the parent shell
  launched, or the process starts from a non-login context. Verify with
  `echo $VAR` before blaming env for a silent "(no results)".
- Dev host: the operator's `COMRADE_HOSTS` names are safelisted in
  `config/environments/development.rb` — named hosts isolate cookies
  between the fleet's apps, which share the localhost jar. Unset,
  localhost and IP access work as Rails defaults.

## Session docs

Session handoffs follow the handoff skill; state lives in
`.agent-notes/handoff-<branch>.md` — one gitignored file per in-flight
branch. Registry: `.agent-notes/roadmap.md`. Tracking policy: everything
under `.agent-notes/` except `roadmap.md` and the `handoff-*.md` files
is committed, written for public from birth.

## Seeing the app

The agent can see anything the user sees — no auth barrier. Screenshot
any page headlessly, then Read the png (images render for the agent):

```
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless \
  --disable-gpu --screenshot=tmp/page.png --window-size=1280,2400 \
  --hide-scrollbars "http://<host>:<port>/<path>"
```

The loop for any UI work: change → screenshot → look → fix. Bring rsl
in for verdicts, not progress checks. Screenshots are scratch: `tmp/`,
never committed. Interactions a screenshot can't carry (focus,
streaming) drive via Selenium scripts in `tmp/` — selenium-webdriver is
bundled.

## Views: helpers + partials hide complexity

- Views stay thin: DOM structure lives in partials, ergonomics live in
  helpers. A view should read like content, not like Rails plumbing.
- Wrap `render "partial", locals: {...}` incantations in helper methods
  so call sites read like HTML nesting. Helpers derive redundant args
  internally; callers pass only what's context-specific.
- A class list duplicated across the server render and its client twin
  becomes a `c-` component class in
  `app/assets/tailwind/application.css` — agency's tailwind-components
  skill is the rule.
- No refresh-to-see-it flows: if a server-side change alters what a
  page shows, the page updates live (Stimulus/Turbo).

## Testing

- Specs come after the shape is solid — never during build/design. No
  mirrored specs, no placeholder gates. The build lands first; specs
  land when review has settled the shape.
- Specs test mechanics, not page content: gates, write paths, records —
  never "does the page show the config strings I put in".

## Gotchas

- The app is a fixed `inset`-shell: the document never scrolls; only
  the transcript panel scrolls internally, and all stream-reader
  scrolling targets the panel, never `window`. The full contract —
  visual-viewport sizing, the twin-render rule — is `docs/design.md`.
- Viewport units cannot express "minus keyboard" on iOS: the shell
  sizes from `visualViewport.height`, never `100vh`-family units. Never
  reintroduce document-scroll states or `100vh`-family sizing for
  full-height surfaces.
- Non-Latin text (Devanagari etc.) renders badly in the terminal when
  inline with English — always put it on its own line(s), never
  mid-sentence.
- **Never run `bin/rails tailwindcss:build` by hand in-session** — the
  `bin/dev` watcher is the only build mechanism. Stale CSS means a dead
  watcher: `bin/dev status`, then `bin/dev restart`. The manual build's
  only context is watcher-less (fresh checkout, CI), with
  `BUNDLE_FORCE_RUBY_PLATFORM=false`.
- **The quality gate is `bin/quality`, never bare tool runs** — rubocop,
  reek, and herb together (brakeman separately). A bare `bin/rubocop`
  pass reads clean while the other gates still fail. (2026-11-07)
- `bin/dev`'s Rails process can silently fail to reload service-class
  changes mid-session: if a reply fails without a reason and the log
  shows nothing, `bin/dev restart` before archaeology.
- (grows as they're hit — add on discovery, with the date)

## Working agreement

- **Approval gate.** Instructions are proposals. Before editing files,
  running migrations, or committing — state what you intend and wait
  for explicit approval. Read-only work (exploring, reading, running
  tests) needs none.
- **`main` changes only through pull requests** (branch rules enforce
  it). One branch and one PR per working session, few pushes. Agents
  never merge — merging is the maintainer's alone.
- **Doc updates ride with the work.** Work that changes or contradicts
  what any doc says is incomplete until that doc is updated in the same
  act — never leave the rule in one doc and its contradiction in
  another.
- **Before the first edit of a task, state the plan** — files, order,
  what changes — and wait for a go-ahead.
- **Read before edit.** The edit tool matches byte-for-byte; read the
  target immediately before editing.
- When something breaks, work the fix interactively rather than
  assuming the fix.

## About rsl

- Senior Rails engineer, decades deep. Skip fundamentals; explain only
  project-specific decisions and non-obvious tradeoffs.
- Second-guess his calls and push back — disagreement is welcome; silent
  compliance isn't.
- He types fast and lowercase in chat — not a signal; never mirror it
  in code or docs.
- Opinionated about simplicity and elegance; prefer the smallest thing
  that works, refactor later. Public interfaces and data contracts get
  upfront design.
- The README is the tone contract: read `.agents/skills/repo-voice`
  before writing any user-facing prose.