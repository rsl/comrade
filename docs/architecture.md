# Architecture

The names, in one place. When a term is fuzzy, look it up here; when a name
lands differently in code than it reads here, fix this file in the same
commit.

## Stack

- **Rails 8.1, Ruby 4.0, Hotwire** (Turbo + Stimulus), **PostgreSQL**.
- **GoodJob** for background jobs. **No Redis, ever** — GoodJob runs off
  Postgres, and Comrade already needs Postgres, so the stack stays
  one-database deep. Solid Queue was evaluated and removed.
- **Solid Cache + Solid Cable** for caching and WebSockets. In production
  they get their own databases; in development Cache is memory and Cable is
  async.

## Ruby names

- **`Comrade::Reply`** — the agent loop. Takes a conversation, streams the
  model's answer, handles tool calls mid-stream (pause, execute, append the
  tool result, resume).
- **`Comrade::Tools::WebSearch`** — searches via SearXNG.
- **`Comrade::Tools::FetchPage`** — fetches a page's full text via Tavily.
- Tools are plain Ruby objects with `name`, `schema`, and `call(args)`. No
  base class, no registry magic.

## Schema

A `Conversation` has many `Message`s. A message has:

- `role` — a string, not an enum, no STI
- `content` — text
- `citations` — jsonb
- `tool_name` — string, set when the message records a tool call
- `tool_payload` — jsonb, the tool's arguments and result

Structured data goes in jsonb columns, not new tables. There is no `User`
model and no auth: Comrade is single-user and localhost-bound by design.

## Configuration

Five runtime environment variables, nothing else:

- `COMRADE_LLM_BASE_URL` — any OpenAI-compatible chat-completions endpoint
- `COMRADE_LLM_API_KEY`
- `COMRADE_LLM_MODEL`
- `TAVILY_API_KEY` — page extraction
- `SEARXNG_URL` — search

Plus two dev-only conveniences, both env-driven and unread in production:

- `COMRADE_PORT` — the port `bin/dev` serves on (maps to `PORT` before
  exec; unset, `PORT`, then Rails' 3000 apply). Exists so a fleet of apps
  can each own a named port variable without contesting the generic one.
- `COMRADE_HOST` — a named dev host (e.g. `comrade.local`), safelisted in
  the development config so HostAuthorization accepts it. Named hosts
  isolate cookies between the fleet's apps, which all share the localhost
  jar; point the name at 127.0.0.1 in /etc/hosts.

Nothing in the code knows a provider's name. The model endpoint is
interchangeable by construction.

## Files that matter

- **`config/comrade_prompt.md`** — the system prompt. Owns the answer's tone
  ("answer, cite, never ask follow-ups") and the search judgment ("search
  only when you lack the facts"). This file is the tuning surface; iterate
  there, not in code.
- **`docs/searxng.md`** — SearXNG bare-install setup (launchd plist,
  `127.0.0.1:8889`, JSON format enabled).

## Streaming

Answers stream through a Stimulus controller reading a stream reader off a
normal `fetch` — not `ActionController::Live` + Turbo SSE. AC::Live's
threading model is a known source of gotchas, and the plain-fetch approach
keeps the loop in one place.

### The planned move to Action Cable (not built yet)

The current transport holds an HTTP request open for the whole generation,
and that coupling is the root of its failure class: the client aborting
kills the generator (steering depends on this — but so does a Safari
connection dying mid-stream, which loses the whole answer, tool rows and
all); and a busy model server queues requests without sending a byte, so
the socket's idle timeout reads "queued" as "dead" (2026-10-24's reply
failure; patched with a 300s read timeout, which is patience, not a cure).
The plan, when the pain earns the build:

**Shape.** POST /messages persists the user turn and starts the generation
server-side (a GoodJob job — the worker daemon already runs), returning
immediately. The generator broadcasts deltas over an Action Cable channel;
Solid Cable carries them over Postgres pub/sub. The server owns
persistence: tool rows, the partial, the answer — written as generation
proceeds, so a dead client loses nothing.

**The event contract survives.** The channel carries the same vocabulary
the SSE transport uses today (delta / tool / citations / error / done) —
the client's stream reader changes its input pipe, not its logic.

**The hard parts, designed before building:**

- **Cancellation.** Steering aborts the request today; over Cable, abort
  means nothing. The generator needs a cancel flag it polls between deltas
  plus a kill of its upstream model connection, and the steer POST must
  name the generation to cancel. Orphaned generations need cleanup.
- **Batching.** Solid Cable is pub/sub over Postgres — built for
  occasional broadcasts, not a thousand NOTIFYs per reply. Deltas flush on
  a ~100–200ms timer; the liveness dot covers the gap.
- **Job patience without retries.** GoodJob's retry is wrong for
  generation: a retry re-runs searches and duplicates turns. Generation
  jobs discard on failure, broadcasting the error to the channel — the
  retry link stays the reader's re-run, exactly as today.
- **Reconnect.** On resubscribe, the client rebuilds the in-flight turn
  from the persisted partial and continues from the live feed — cheap
  precisely because the server persists partials.

**What it buys when built.** Connection-death stops losing answers; a busy
model queue becomes a wait instead of a failure; every fleet device
watching a conversation sees it grow live; and "model busy" can be shown
honestly instead of guessed at.

**What triggers the build.** Lost partials annoying in real use, multi
-device live transcripts wanted, or the busy-model wait visibly hurting.
One of those, not curiosity alone — the SSE transport works today.

## Search and fetch

- **SearXNG** aggregates search results, installed bare (no Docker) and run
  under launchd on `127.0.0.1:8889`.
- **Tavily** (`/extract`) pulls full page text, so citations point at what
  pages actually say rather than snippets. Its English-first index is why it
  extracts pages instead of driving search.