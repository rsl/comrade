---
title: Fetch Debt — owner-first repayment prompts
status: ideated 2026-11-10
summary: Tally which cited domains carry the most answers, find their support links (cached, polite), and surface one repayment prompt — a coffee for normal debt, monthly recurring for heavy long-running debt. Hard rule: no automated visits for revenue purposes.
---

# Fetch Debt — owner-first repayment prompts

Planned 2026-11-10, brief distilled with rsl. Comrade runs on the free
labor of the sites it cites; when a site has carried a lot of the
operator's research, comrade says so and points at the owner's
support link. Owner-first by design: the value flows to the site
operator, never to an ad network.

## Core data

- Every answer already logs its cited domains (implicit in sources).
- Tally per domain: answers backed, over what timespan.
- On heavy-use domains, fetch/scrape the site's footer/contact page
  for a support link (Ko-fi, Patreon, Liberapay, "donate",
  "support us") — cache it, never re-fetch every time.

## Surfacing

- When a domain crosses a threshold (e.g. 5+ answers), show one line
  in the reply: "This site has carried a lot of your research —
  support link: [URL]."
- One coffee ($3–5) suggested for normal debt; monthly recurring for
  heavy, long-running debt.
- Never suggest sub-$2 tips — fees eat them and the gesture feels
  cheap.

## Hard rules (non-negotiable)

- **No automated headless visits for revenue purposes.** That is
  impression fraud, and the site owner eats the clawback /
  account-ban risk, not the ad networks.
- **Headless rendering only when a page's content genuinely needs JS
  to be readable** — the same condition as today's failed fetches. A
  human consumes the result; incidentals are fine.
- **Politeness layer:** honor robots.txt, cache fetched pages,
  rate-limit repeat fetches to small sites. Protects hobbyist wikis
  from our own traffic.

## Open questions — for the build conversation, not pre-decided

- Where does the prompt live — inline in replies, or a weekly digest?
  (Digest is less naggy; inline is more actionable.)
- Does the tally reset or decay over time?
- How to detect a support link reliably without fetching the whole
  site every time?