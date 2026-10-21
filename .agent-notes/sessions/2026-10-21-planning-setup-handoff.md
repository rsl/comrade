# Session handoff — 2026-10-21, planning & setup

## What this session did

Took comrade from empty directory to pushed repo. All commits on `main`
are pushed to `origin` (git@github.com:rsl/comrade.git) — work shas:

- `496d68d` initial commit (Rails 8.1 scaffold, lint-cleaned)
- `e7ea26a` Wire up good_job
- `e3f24cc` Add linting configuration
- `ccea983` Add README
- `96db81c` Add AGPL-3.0 license
- `c51a4d9` Drop lint ruleset attribution from Gemfile comment

Key events, in order: stack decided through conversation (Rails 8 / PG /
GoodJob / Solid suite / no Redis / provider-agnostic LLM / SearXNG bare /
Tavily fetch / AGPL); scaffold + lint setup (shared ruleset vendored,
custom cop written project-local); check-in skill
ran — all unasked decisions ratified; README written with politics + On AI
sections; agent workflow scaffolding (AGENTS.md, .agent-notes, 3 skills)
modeled on langafile's pattern; this handoff.

## Uncommitted working tree (the session boundary)

- `.agent-notes/roadmap.md` — NEW, durable design contract; commit it
- `.agent-notes/sessions/2026-10-21-planning-setup-handoff.md` — this file;
  the NEXT session commits it after reading, then `git mv` to archive
- `AGENTS.md` — NEW, repo rules + working agreement
- `.agents/skills/{agent-loop,schema,repo-voice}/SKILL.md` — NEW
- `.agent-notes/sessions/README.md`, `archive/.gitkeep` — NEW
- `README.md` — modified since push: On AI section added, voice tweaks
  ("empower", "reclamation", Oxford comma), contributing section
- Suggested commit split: (1) "Add agent workflow scaffolding" — AGENTS.md,
  .agents, .agent-notes minus roadmap; (2) "Expand README with politics
  and contributing sections" — README.md; (3) "Add roadmap" — roadmap.md;
  then the handoff per lifecycle.

## Next session's opening act

1. Read `.agent-notes/roadmap.md` — it is the design contract; all
   decisions there are settled, don't relitigate.
2. Commit the uncommitted docs per the split above.
3. Archive this handoff (`git mv` to `.agent-notes/archive/`).
4. Begin **Phase 1 — schema & models** per the roadmap. State the plan
   before editing; approval gate applies; never commit without asking.

## Gotchas hit this session

- oMLX serves OpenAI-compatible API on 127.0.0.1:8888, requires bearer
  key from `~/.omlx/settings.json`. Port 1234 is "Bionic" (a different
  app) — don't confuse them.
- The custom cop is project-local:
  `lib/rubocop/cop/layout/multiline_method_argument_line_breaks_except_lambdas.rb`
  — a variant of the stock `Layout/MultilineMethodArgumentLineBreaks` that
  exempts calls with lambda/block arguments.
- gitnexus: rsl said never speak of it again. This is the last mention.
- Sessions in Zed/opencode: this handoff exists because rsl is switching
  editors — context does NOT carry over; the docs are the memory.