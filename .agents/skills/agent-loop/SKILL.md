---
name: agent-loop
description: Use when editing Comrade::Reply, the tools (WebSearch, FetchPage), or the system prompt file — anything touching the streaming agent loop. Covers the loop contract, where tone lives, and what must never move into code.
---

# The agent loop

`Comrade::Reply` is a streaming loop, not a pipeline: it streams from the
model, pauses on tool calls, executes them (SearXNG `web_search`, Tavily
`fetch_page`), appends results to the transcript, and resumes. The model —
not an if-statement — decides when to search. Never add "does this turn need
a search?" heuristics to Ruby.

## The laws

- **The system prompt file owns tone and search judgment.** "Answer, cite,
  never ask follow-ups" and "search only when you lack the facts" live in
  the prompt file, not in code. Iterate there; it's the tuning surface.
- **Model/endpoint are config, not code.** `LLM_BASE_URL`, `LLM_API_KEY`,
  `LLM_MODEL` from ENV. Any OpenAI-compatible endpoint must work. No
  provider names in the Ruby.
- **No Redis. Ever.** Streaming goes to the HTTP response; background work
  is GoodJob. Cable broadcasts (Solid Cable) if a page needs live updates.
- **Transcripts are the spine.** Tool call/result rows persist as messages
  (role `tool`, `tool_name`, `tool_payload` jsonb) so the next request can
  rebuild context. Don't invent side channels.