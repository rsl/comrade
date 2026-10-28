---
name: schema
description: Use when writing or editing migrations, models, or anything database-shaped in this repo. Covers the persistence laws agreed for comrade: jsonb over extra tables, no STI, no User model, authless identity via comrades.
---

# Schema laws

Decided 2026-10-21, in design sessions — don't relitigate casually,
but do push back with reasons.

- **`Conversation` has_many `Message`.** Never `Session` (collides with
  Rack/Rails session concepts), never `Chat` (under-specified), never
  `Thread` (Ruby core).
- **`Message(role, content, citations:jsonb, tool_name, tool_payload:jsonb)`.**
  Role is a plain string column — `user` / `assistant` / `tool` — no STI,
  no polymorphism. Tool activity persists as `tool`-role messages.
- **jsonb over extra tables.** No `tool_calls` or `search_queries` tables
  until a feature actually queries them. Postgres jsonb makes extraction
  (`tool_payload->>'query'`) a one-liner and the later migration cheap.
- **No `User` model. No auth.** Superseded in part 2026-10-24: identity
  lands as the `comrades` table behind `Comrade::Enlistee` — authless
  token, unique permanent names as the claim, the commune as
  `conversations.comrade_id: nil`. Single-user until it lands;
  localhost-bound throughout, and still no auth.
- **No database in the correctness path for retrieval decisions** — search
  judgment lives in the system prompt, not in stored heuristics.