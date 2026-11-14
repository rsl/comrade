---
status: active
summary: Deferred asks and permission boundaries from the Ledger slice-1 build session (2026-11-14) — decisions taken on the conservative branch.
---

# Deferred asks — Ledger slice 1 (2026-11-14)

- **iPad autofocus hunt.** The real landing on iPad Firefox will not
  autofocus (bare pages and a faithful replica do); the hunt is
  mid-flight with the differential isolated to the real landing's body.
  Full state, ruled-out theories, and the next diagnostic live in
  `handoff-rsl-image-attachments.md` (2026-11-14 session).

- **Turn-label timestamps.** The frame shows "You · 14:02" on turn labels; timestamps can't be twin-safe (client stamps at send, server stamps row created_at — the post-first-reply swap would shift them). Options: (a) keep them out (taken — conservative, preserves the byte-twin law), (b) accept visible drift and add them. Taken: (a). If you want them, slice 2 or a review pass can add server-authoritative times that the client reads back from the wire.
- **Orphaned sidebar files.** `rm` is permission-denied in this agent: `app/javascript/controllers/sidebar_resize_controller.js` and `app/assets/javascripts/sidebar_width_boot.js` are dead (unreferenced — the divider, its boot include, and the drag-resize controller wiring are gone from the layout) but still on disk. Delete them at review.
- **Spec suite unverified.** `bundle exec rspec` was permission-denied this session. The redesign retires methods the first spec-wave tests (`source_chips`, `paragraph_sources`, `footer_fallback`, `fallback_due?`, `markers_resolve?`, `double_check_id`, old `grouped_turns`, old `tool_note` text) and changes chip/stats markup, so the suite almost certainly red. Per the plan, specs land when review settles the shape — the next spec pass rewrites them against the exchange/note-card shape. RESOLVED 2026-11-14: the suite was red exactly as predicted (5 sources_helper + 3 identity failures); rewritten against the note-card/turn_sources contract and the `.c-chip-name` chip locator — 28 examples green, `bin/quality` green.
- **"all" link in the sub-band.** The frame's sub-band shows only "+ new / archived"; I added "all" beside them so the all-conversations page stays reachable (the listing's back-link alone shouldn't be the only path). Cut it if you'd rather lose the link.
- **Empty-note copy.** The frame's "none — from model knowledge" line is also used for a sources answer whose markers resolve to nothing (rare) — the alternative was inventing a second string. One line, both twins agree.
- **Failed-turn quirk carried over.** After a failed turn retries, the failed (empty, labeled) assistant article stays in the answer stack — pre-existing behavior, now visible as a bare "Comrade" label. Server twin never renders it (nothing persisted), so a reload differs slightly. Pre-existing; flagged, not fixed.
