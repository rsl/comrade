# Session handoff — 2026-10-21, schema, reply loop, dev experience

**State: `rsl-schema-models` carries nine unpushed commits on top of `main`
(`43678d3`) — Phase 1 (schema & models) and Phase 2a (bare reply loop) are
built, live-tested against oMLX, and lint-clean. Not merged: the branch
needs a push + PR per the workflow. The roadmap's phase plan was resliced
this session (1 → 2a → 3a → 2b → 4 → 5) so chat becomes usable before
search.**

## Built

- **Lifecycle change (5f40607):** handoffs are archived when superseded,
  not when read — a handoff is half plan; reading doesn't consume it.
  Applied to langafile and comfyest too; added to unifractured's
  fa-agent-notes skill (fa commit 288a24a, pushed).
- **Linter wiring (954c22d):** `lefthook install` (the repo's .git
  postdated lefthook.yml, so hooks had never run). Reek's exclude_paths
  doesn't apply to explicitly passed files — db/ is excluded via lefthook
  globs instead. RuboCop's vendored config had a second AllCops concealing
  the first; merged, pending cops stay disabled.
- **Phase 1 (b7ba320, cbccd97):** conversations + messages migrations and
  models per the schema decision. Role validated to user/assistant/tool —
  the system prompt is config, never a row.
- **Phase 2a (b3573a2, 20d6069):** Comrade::Reply streams from any
  OpenAI-compatible endpoint (Net::HTTP, SSE buffering isolated), persists
  user message eagerly (422 before streaming) and assistant message on
  clean completion. REST surface: POST /conversations returns 201 with
  Location + X-Conversation-Id and streams the first reply in one
  roundtrip; POST /conversations/:id/messages streams follow-ups.
  Streaming uses a response_body enumerator — no ActionController::Live.
  Prompt is config/comrade_prompt.md with a gitignored
  comrade_prompt.custom.md override for installers.
- **Dev experience (ff596fc, 408922c):** COMRADE_PORT=1917 (October
  Revolution) via bin/dev's dev-only PORT mapping; COMRADE_HOST
  (comrade.local) safelisted in development.rb for cookie isolation —
  named hosts stop the fleet's apps sharing the localhost cookie jar.
  bin/dev grew start/stop/restart/status/logs subcommands: detached
  server, pid+port recorded under tmp/pids, boot-poll, per-invocation
  env independence. Both vars in ~/.oh-my-zsh/custom/exports.zsh — and
  OMLX_BASE_URL there was stale (8111 → 8888 fixed).
- **Dependabot verified:** alerts were NOT flowing; Dependabot alerts and
  automated security fixes are now enabled via the API.

## Decisions this session

- Handoff archiving: when superseded, by the writer of the successor.
- Tailwind via tailwindcss-rails adopts at Phase 3a (roadmap Styling row).
- Wire contract: SSE-shaped lines (`data: "delta"`, `data: [DONE]`);
  typed events arrive with 2b tools.
- Streaming without AC::Live: response_body enumerator, Puma iterates
  lazily, Rails' executor holds until the body is consumed.
- Blank content → 400 (params.require treats blank as missing); the 422
  path is the mechanism for future non-blank validation failures.

## Next session's opening act

1. Read this handoff; verify open items live in the roadmap; archive this
   file (move to .agent-notes/archive/, annotate corrections); commit
   citing this session's shas.
2. GoodJob worker proc (roadmap open item): dev execution_mode :external,
   bin/dev daemon manages web + jobs, fix the broken bin/jobs (still
   Solid Queue) and the puma.rb solid_queue plugin leftover.
3. Then Phase 3a — Tailwind adoption first, minimal chat UI.

Push and merge are rsl's call, made when rsl makes it — the branch stays
local until then.