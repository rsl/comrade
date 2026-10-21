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

Five environment variables, nothing else:

- `LLM_BASE_URL` — any OpenAI-compatible chat-completions endpoint
- `LLM_API_KEY`
- `LLM_MODEL`
- `TAVILY_API_KEY` — page extraction
- `SEARXNG_URL` — search

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
keeps the loop in one place. The upgrade path to Turbo Streams over Solid
Cable stays open.

## Search and fetch

- **SearXNG** aggregates search results, installed bare (no Docker) and run
  under launchd on `127.0.0.1:8889`.
- **Tavily** (`/extract`) pulls full page text, so citations point at what
  pages actually say rather than snippets. Its English-first index is why it
  extracts pages instead of driving search.