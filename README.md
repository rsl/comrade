# Comrade

**Seize the means of information retrieval.**

*Question authority — then ask it to cite its sources.*

Comrade is a self-hosted web-search chat. Ask a question; it searches the web,
reads what it finds, and answers in plain prose with citations. No ads. No
tracking. No SEO slop. No "Was this helpful? Would you like to know more?"

Just the answer. Then silence.

## How it works

- **Any OpenAI-compatible model endpoint.** Run a local server (oMLX, LM
  Studio, ollama, llama.cpp) or point it at a hosted one if you must. Configure
  it with three environment variables and nothing in the code changes.
- **SearXNG** aggregates search results from the real engines — locally, with
  the ads and tracking links stripped out.
- **Tavily** pulls the full text of pages worth reading, so answers cite what
  pages actually say rather than mashing snippets together.
- **The model decides.** Search is a tool, not a pipeline. Comrade asks the
  model what the conversation needs — sometimes a web search, sometimes a page
  fetch, sometimes just its own knowledge. "Explain that differently" costs
  nothing. "What changed since yesterday" costs one search.

## The politics

Comrade exists because the dominant search engines stopped being tools and
became engagement machines: ad auctions wearing a search box, every answer
wrapped in a funnel. The means of information retrieval have been enclosed.
This is a small attempt at reclamation.

That conviction is in the license, not just the tagline. Comrade is
**AGPL-3.0**: if you run a modified version for other people — even over a
network, even internally — you owe those people the source. You may not take
the commons and close it. Nobody has to give Google an improved search box for
free, either; that's what permissive licenses were for.

Local-first is the ideal, not a requirement: your questions are nobody's
training data if they never leave your machine.

## On AI

Yes, this is an AI project, and yes, it's leftist. These are not in tension.

The leftist critique of AI has never been about the models — it's about the
enclosure: models trained on uncredited collective labor, owned by a handful
of firms, priced as a service, and deployed to replace people rather than
empower them. That's a critique of ownership and application, and it points
toward taking the tools into shared hands, not abandoning them. A local model
running on your own hardware, serving your own questions, inside a project
you can read and fork, is a different relationship to the machine entirely —
the same one this project wants for search.

(And in the spirit of disclosure: Comrade is built with AI assistance under
the direction of an opinionated, socialist, Rails software engineer who decides
what it should be and reads everything that ships. The glue is real; so is
the comrade.)

For thinking that goes deeper than a README section — and for a community
that has already worked through most of these arguments — see
[r/leftistsforai](https://www.reddit.com/r/leftistsforai/).

## Status

Pre-alpha, single-user, built for one household. There is no auth, no
multi-tenancy, and no stability promise. The schema and tool interface will
churn. If that sounds like your kind of project, welcome.

## Setup

```bash
bin/setup
```

Comrade needs three things running nearby:

1. **A model server** — anything speaking the OpenAI chat-completions API:
   ```bash
   export COMRADE_LLM_BASE_URL="http://127.0.0.1:8888/v1"
   export COMRADE_LLM_API_KEY="sk-..."
   export COMRADE_LLM_MODEL="GLM-5.3-Flash-oQ4e-mtp"
   ```
2. **SearXNG** for search — a bare local install is fine (see
   `docs/searxng.md` for a launchd setup).
3. **A Tavily API key** for page extraction:
   ```bash
   export TAVILY_API_KEY="tvly-..."
   ```

Then:

```bash
bin/rails server
```

## Contributing

Contributors are welcomed with open arms — this is a commons, and commons
grow by people showing up. Issues, PRs, and arguments about the politics
section are all legitimate contributions.

Two conventions:

- **Code style lives in** `.agents/skills/ruby-style` — preferences with
  reasons, applied to code contributed here. The gates (rubocop, reek, herb)
  run at commit.
- **No CLA.** You keep your copyright; contributions are licensed to the
  project under AGPL-3.0, same as everything else. (A CLA — Contributor
  License Agreement — is the document some projects make you sign to hand
  them rights to your work, which would let them relicense the commons
  later. We won't ask for one.) Sign your commits with `git commit -s` —
  the Developer Certificate of Origin, a one-line declaration that the code
  is yours to contribute (your own work, or properly licensed) — so the
  provenance trail stays clean:

  ```
  git commit -s -m "Fix search tool timeout"

  Fix search tool timeout

  Signed-off-by: Your Name <you@example.com>
  ```
- **AI-assisted contributions are fine.** Models can hold the glue gun. What
  we ask is what we practice: a human who has actually read the diff stands
  behind it.

## License

[AGPL-3.0](LICENSE) — if you run a modified Comrade for others, you owe them
the source.