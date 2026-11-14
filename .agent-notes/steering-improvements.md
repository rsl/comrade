---
title: Steering & interrupt — improvement ideas
status: parked
summary: Ideas for improving mid-stream steering — a real stop control, cooperative cancellation of zombie tool rounds, keeping citations/stats on steered partials, and unmasking fetch failures.
---

# Steering & interrupt — improvement ideas

The baseline this note improves on:

- Client (`app/javascript/controllers/stream_reader_controller.js`, the ask/steer path): only an in-flight stream can be steered; the partial answer is finalized on the page, the fetch aborted, and the partial text rides the next POST as `interrupted`.
- Server (`app/services/comrade/reply.rb`, `persist_lead_in`): the partial persists as an assistant lead-in row before the new user message, so the next answer is conditioned on its own cut-off sentence.
- The dead stream dies lazily: the turn keeps running until its next write to the abandoned socket, then unwinds before `persist_answer`.

Nothing here is settled — ideas with their tradeoffs, to be argued about in a build conversation.

## A stop control that isn't steering

Today the only way to end a stream early is to type something new, which always means steering: the partial persists as a lead-in and a new turn starts generating. There is no "just stop". A stop button would abort and keep the partial as a finished answer — but the server has no mechanism for that: the dead stream's `persist_answer` never runs, so nothing writes the assistant row. Options: a stop request that reuses the lead-in path with no new user message (steer-to-nothing), or cooperative cancel (below) letting the turn end itself with the partial as its answer. The steer-to-nothing shape needs care around `retry_case`, which reads assistant-rows-after-last-user to decide if a turn is answered.

## Zombie tool rounds

The abort only takes effect at the next yielder write. A `fetch_page` or search mid-flight when the user steers runs to completion, its tool row persists via `append_message` (a DB write, not a socket write), and the model never sees the result — wasted fetch quota, a busy thread on a dead turn, and tool rows dangling in the transcript behind an answer that never comes. Cooperative cancellation would fix the waste: an in-process per-conversation (or per-turn) flag the new request sets before starting, checked at phase boundaries and between tool dispatches, ending the turn early. Tradeoff: shared mutable state across requests; the simplest version checks only between tools, which caps the waste at one in-flight tool call instead of eliminating it.

## Steered partials lose citations and stats

`persist_answer` never runs for a steered stream, so the lead-in row has content but no citations and no stats. The live page looks right (the client finalizes chips from what streamed), but the reload twin renders a bare answer with no citation chips and no foreman footer. The client could send its finalized citations alongside `interrupted` and the server could persist them on the lead-in row. Stats can't be honestly reconstructed — either omit them or record a `steered: true` marker so the footer line can say the turn was cut short.

## Unmasking fetch failures (adjacent, found 2026-11-13)

`Reply#fetch_content` collapses every failure — missing key, HTTP error, empty extraction — into the same model-facing "No content could be extracted" sentence. The missing-`COMRADE_FETCH_API_KEY` incident was only diagnosable by timing the tool rows (a 12 ms gap means the short-circuit, not a network call). Keep the stable model message, but record the real failure — in the tool row's content or `tool_payload` — so the transcript itself carries the diagnosis. This one is a small, self-contained fix worth doing regardless of the steering work.