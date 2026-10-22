# Comrade — agent rules

## What this is

A self-hosted web-search chat: your local model (any OpenAI-compatible
endpoint), SearXNG results, Tavily page fetches, streamed answers with
citations. AGPL-3.0. Personal tool, built public-first.

## Stack facts

- Rails 8.1, Ruby 4.0, PostgreSQL. No Redis anywhere, ever — GoodJob for
  jobs, Solid Cache + Solid Cable for the rest.
- Model endpoint: `COMRADE_LLM_BASE_URL` / `COMRADE_LLM_API_KEY` / `COMRADE_LLM_MODEL` from ENV.
  Local dev uses oMLX on 127.0.0.1:8888 (OpenAI-compatible). Never hardcode
  provider names in Ruby.
- Search: SearXNG (bare install, planned localhost:8889), page fetch via
  Tavily (`TAVILY_API_KEY` from ENV).
- Linting: RuboCop (`.rubocop.yml`, with a project-local custom cop in
  `lib/rubocop/cop/`), Reek, Herb, lefthook pre-commit. All four must stay
  clean; run them before saying done.
- Dev server: `bin/dev` serves on `COMRADE_PORT` (1917 on this machine,
  exported in `~/.oh-my-zsh/custom/exports.zsh`). Precedence: `-p` flag >
  `COMRADE_PORT` > ambient `PORT` > Rails' 3000. The mapping lives only in
  `bin/dev`, so production's Kamal-set `PORT` is untouchable by it.
  Dev binds 0.0.0.0 so fleet devices reach it; `comrade.local` is
  advertised over Bonjour via launchd (`com.rsl.comrade-mdns`) and
  resolves locally via `/etc/hosts`.
- Dev host: `COMRADE_HOST` (comrade.local here) is safelisted in
  `config/environments/development.rb` — named hosts isolate cookies
  between the fleet's apps, which all share the localhost jar. Unset,
  localhost and IP access work as Rails defaults.
  Browse at `http://comrade.local:1917`.

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
  --hide-scrollbars "http://comrade.local:1917/<path>"
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

- Non-Latin text (Devanagari etc.) renders badly in the terminal when
  inline with English — always put it on its own line(s), never
  mid-sentence.
- Scratch files and scripts go in the app's `tmp/` (gitignored), not
  `/tmp`.
- (grows as they're hit — add on discovery, with the date)

## Working agreement

- **Approval gate.** Instructions are proposals. Before editing files,
  running migrations, or committing — state what you intend and wait for
  explicit approval. Read-only work (exploring, reading, running tests)
  needs none.
- **Never commit without asking.** Commit style: active sentences
  ("Add …", "Fix …", "Wire up …"); a repo's first commit is "initial
  commit" with a body that tells the story. Granular commits — one logical
  unit each. When a follow-up change belongs to the unpushed commit just
  made (a fixup of it, or the same decision continuing), `--amend` into
  it instead of adding a new commit; never amend a pushed commit.
- **`main` changes only through pull requests** (branch rules enforce it —
  direct pushes are rejected). Branch from up-to-date `main` with the
  `rsl-` prefix; batch a working session's commits onto one branch and one
  PR — granular commits, few pushes — and merge after rsl has seen it.
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