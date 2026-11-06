# Comrade — agent rules

## What this is

A self-hosted web-search chat: your local model (any OpenAI-compatible
endpoint), SearXNG results, Tavily page fetches, streamed answers with
citations. AGPL-3.0. Personal tool, built public-first.

## Stack facts

- Rails 8.1, Ruby 4.0, PostgreSQL. No Redis anywhere, ever — GoodJob for
  jobs, Solid Cache + Solid Cable for the rest.
- Model endpoint: `COMRADE_LLM_BASE_URL` / `COMRADE_LLM_API_KEY` / `COMRADE_LLM_MODEL` from ENV,
  any OpenAI-compatible endpoint. Fast and slow lanes extend it per turn:
  `COMRADE_LLM_FAST_*` / `COMRADE_LLM_SLOW_*`. Never hardcode provider names,
  host names, or ports in Ruby.
- Search: SearXNG (`COMRADE_SEARCH_URL`), page fetch via Tavily
  (`COMRADE_FETCH_API_KEY` from ENV).
- Linting: RuboCop (`.rubocop.yml`, with a project-local custom cop in
  `lib/rubocop/cop/`), Reek, Herb, lefthook pre-commit. All four must stay
  clean; run them before saying done.
- Dev server: `bin/dev` serves on the dev port — the port is deployment
  config, set in the operator's env, never in docs. Precedence: `-p` flag >
  ambient `PORT` > Rails' 3000. The mapping lives only in `bin/dev`, so
  production's Kamal-set `PORT` is untouchable by it. Dev binds 0.0.0.0 so
  fleet devices reach it. Lifecycle is daemon-only: start/stop/restart
  through `bin/dev` — killing puma directly orphans the Tailwind watcher
  (stray watchers were the 2026-10-23 leak; bin/dev now kills process
  groups on stop and sweeps strays on start, but the habit is
  `bin/dev restart`, not kill).
- Env inheritance is a snapshot at process launch: shells spawned by an
  opencode session already carry `exports.zsh` vars — re-sourcing is
  only needed when `exports.zsh` gained keys after the parent shell
  launched, or the process starts from a non-login context. Verify with
  `echo $VAR` / `ps eww <pid>` before assuming a silent "(no results)"
  is an env problem (2026-10-23 correction of the 2026-10-22 note).
- Dev host: the operator's `COMRADE_HOSTS` names are safelisted in
  `config/environments/development.rb` — named hosts isolate cookies
  between the fleet's apps, which all share the localhost jar. Unset,
  localhost and IP access work as Rails defaults. Browse at whatever
  name `COMRADE_HOSTS` lists, locally or via the deployment's
  proxy-routed name.

## Session docs

Notes, handoffs, and review guides live in `.agent-notes/sessions/`, named
`YYYY-MM-DD-<slug>.md` — see that directory's README for the lifecycle.
Open items get promoted to the registry before going idle; a session never
archives its own handoff.

## Session docs are public

Everything under `.agent-notes/` except `roadmap.md` is committed.
Handoffs are written for public from birth: nothing you wouldn't sign, no
local paths or key locations that don't matter, and no provenance of
private work software — scrub sensitive mentions before they land in a
handoff, because they get committed and pushed as written. `roadmap.md`
stays untracked by design (governance voice and local details); its
decision content lives in `docs/architecture.md`.

## Code intelligence

- Once a `.codegraph` index exists, codegraph is the primary tool for
  locating and understanding code — `codegraph_explore` before Read/Grep
  for "where is X / how does X work / what calls X".
- grep/rg is the fallback with specific jobs: non-indexed files (docs,
  `.agent-notes/`), exact-string audits, post-edit verification. Never the
  first move for code questions.
- **Read before edit, every time.** The edit tool matches byte-for-byte;
  editing from memory of what a file "says" fails loudly and wastes a
  round trip.

## Seeing the app

The agent can see anything the user sees — no auth barrier. Screenshot any
page headlessly, then Read the png (images render for the agent):

```
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless \
  --disable-gpu --screenshot=tmp/page.png --window-size=1280,2400 \
  --hide-scrollbars "http://<host>:<port>/<path>"
```

The loop for any UI work: change → screenshot → look → fix. Bring rsl in
for verdicts, not progress checks. Screenshots are scratch: `tmp/`, never
committed. Interactions a screenshot can't carry (focus, streaming) drive
via Selenium scripts in `tmp/` — selenium-webdriver is bundled.

## Views: helpers + partials hide complexity

- Views stay thin: DOM structure lives in partials, ergonomics live in
  helpers. A view should read like content, not like Rails plumbing.
- Wrap `render "partial", locals: {...}` incantations in helper methods so
  call sites read like HTML nesting. Helpers derive redundant args
  internally; callers pass only what's context-specific.
- Repeated class strings become constants, not copy-paste. Design
  rationale lives in the component's code comments, where it travels with
  the component.
- No refresh-to-see-it flows: if a server-side change alters what a page
  shows, the page updates live (Stimulus/Turbo).

## Testing

- Specs come after the shape is solid — never during build/design. No
  mirrored specs, no placeholder gates. The build lands first; specs land
  when review has settled the shape.
- Specs test mechanics, not page content: gates, write paths, records —
  never "does the page show the config strings I put in".

## Gotchas

- The app is a fixed `inset`-shell (layout `application.html.erb`): the
  document never scrolls; only the transcript panel scrolls internally.
  Keep it that way — every document-scroll state on iOS Safari becomes a
  bug class of its own (dead scroll, pan-on-focus, scroll carry across
  the post-first-reply Turbo.visit). Consequences that must survive:
  the client turn (stream_reader_controller.js) and the server render
  (`_message.html.erb`) stay pixel-identical across the visit swap (bit
  twice: title spacer 2026-10-23, empty tool-notes wrapper 2026-10-24),
  and all scrolling in the stream reader targets the transcript panel,
  never `window`.
- Viewport units cannot express "minus keyboard" on iOS: Safari ships no
  `interactive-widget` (expected 27.1), `vh`/`svh`/`dvh` each lie in a
  different URL-bar/keyboard state, and iOS scrolls the window itself on
  focus even when nothing is scrollable. The app therefore sizes its
  shell from `visualViewport.height` (visual_viewport_boot.js) and pins
  `window.scrollY` to 0 around focus. Don't reintroduce `100vh`-family
  sizing for full-height surfaces. (2026-10-24, learned the hard way —
  the vvdebug probe in the session notes has the numbers.)
- Non-Latin text (Devanagari etc.) renders badly in the terminal when
  inline with English — always put it on its own line(s), never
  mid-sentence.
- Scratch files and scripts go in the app's `tmp/` (gitignored), not
  `/tmp`.
- **Never run `bin/rails tailwindcss:build` by hand in-session — no
  exceptions.** `bin/dev` runs the Tailwind watcher, which boot-builds on
  start and rebuilds on every save; the watcher is the only build
  mechanism a session should ever use. Stale CSS (new classes silently
  not rendering, e.g. an element rendering colorless) means the watcher
  died — check `bin/dev status` for "tailwind stopped" and fix it with
  `bin/dev restart`, which restarts the watcher and boot-builds (~100ms).
  Running the manual build instead papers over the dead watcher and the
  staleness keeps recurring. (2026-11-04: a session hit exactly this —
  the watcher had been dead for days, and a hand-run build masked it.)
  The manual build keeps exactly one job: watcher-less contexts that
  never have a session (fresh checkout, CI). There it fails with
  "Cannot find the tailwindcss executable": the global
  `BUNDLE_FORCE_RUBY_PLATFORM=true` export forces the exe-less
  ruby-platform gem over the binary one (noted in the 2026-10-22
  chat-UI handoff). Override per invocation —
  `BUNDLE_FORCE_RUBY_PLATFORM=false bin/rails tailwindcss:build`.
- `bin/dev`'s Rails process can silently fail to reload service-class
  changes mid-session (2026-10-30: a reply failed with no server-side
  exception logged; a restart picked the code up and the identical turn
  passed). If a reply fails without a reason and the log shows nothing,
  `bin/dev restart` before archaeology.
- (grows as they're hit — add on discovery, with the date)

## Working agreement

- **Approval gate.** Instructions are proposals. Before editing files,
  running migrations, or committing — state what you intend and wait for
  explicit approval. Read-only work (exploring, reading, running tests)
  needs none.
- **Never commit without asking.** Commit style: active sentences
  ("Add …", "Fix …", "Wire up …"); a repo's first commit is "initial
  commit" with a body that tells the story. Granular commits — one logical
  unit each. When a follow-up change belongs to the last commit and it is
  unpushed, amend it: `git commit --amend`, the last commit only. No
  fixup commits, no autosquash, no rebase — if the change belongs to any
  commit that isn't the last, it's just a new commit; never amend a
  pushed commit.
  A commit happens only when rsl says the word — an explicit "commit"
  (or equivalent) addressed at committing. Approval to build, verify, or
  finish a task never licenses one, and a general "do it all" doesn't
  cover commits either: when in doubt, bring the work and stop short of
  the commit. (2026-10-24: a string of copy-tweak commits landed on
  rsl's mid-review word changes that weren't reviewed.) Batch
  the small changes and bring them as one ask; unpushed commits
  accumulate on the branch, which is what it's for. And no prodding:
  the uncommitted state gets named when the work is delivered, once,
  then it stays named — no reminders at the end of every reply. The
  branch is the reminder; rsl knows what's sitting there.
- **`main` changes only through pull requests** (branch rules enforce it —
  direct pushes are rejected). Branch with `git co -b <name>` on a fetched,
  up-to-date `main` — never off `origin/main` (the upstream would target
  `main` and the push gets rejected) — with the `rsl-` prefix; batch a
  working session's commits onto one branch and one
  PR — granular commits, few pushes — and merge after the maintainer has
  seen it. Agents never merge — merging is the maintainer's alone, even
  after approval of everything else.
- **Doc updates ride with the work.** A handoff or PR whose work changes
  or contradicts what any doc says (architecture.md, READMEs, the
  session-doc flow) is incomplete until that doc is updated in the same
  act — including live docs still stating the old rule (e.g. a handoff
  header repeating a superseded lifecycle). Never leave the rule in one
  doc and its contradiction in another.
- **Before the first edit of a task, state the plan** — files, order, what
  changes — and wait for a go-ahead.
- **Read before edit.** The edit tool matches byte-for-byte; read the
  target immediately before editing.
- Direction decisions (approach, scope, dependencies, renames, deletions)
  go through the question tool, batched at natural boundaries — never
  silently, never one per step.
- When something breaks, work the fix interactively rather than assuming
  the fix.

## About rsl

- Senior Rails engineer, decades deep. Skip fundamentals; explain only
  project-specific decisions and non-obvious tradeoffs.
- Second-guess his calls and push back — disagreement is welcome; silent
  compliance isn't.
- He types fast and lowercase in chat — not a signal; never mirror it in
  code or docs.
- Opinionated about simplicity and elegance; prefer the smallest thing
  that works, refactor later. Public interfaces and data contracts get
  upfront design.
- The README is the tone contract: read `.agents/skills/repo-voice` before
  writing any user-facing prose.