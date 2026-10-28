# SearXNG on macOS, bare

Comrade talks to SearXNG over HTTP; SearXNG talks to the real search
engines. This is the launchd setup this household runs — no containers,
no Redis, one local service on a port.

## Install

```bash
git clone https://github.com/searxng/searxng ~/dev/searxng
cd ~/dev/searxng
python3.12 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

The full `requirements.txt` (not `requirements-server.txt`) carries the
runtime dependencies the webapp actually imports.

## Settings

`settings-comrade.yml` in the repo root overrides upstream defaults:

```yaml
use_default_settings: true

server:
  bind_address: "127.0.0.1"
  port: 8889
  limiter: false
  image_proxy: false
  secret_key: "change-me-comrade-local"

search:
  formats:
    - html
    - json
```

The `json` format is what makes Comrade possible — it's disabled by
default upstream. `limiter: false` is what keeps Redis out of the
picture entirely: the limiter is the only thing SearXNG needs Redis
for, and a single-user instance on loopback doesn't need rate limiting.

Set a real `secret_key` — any long random string works.

## Keep it running

`~/Library/LaunchAgents/com.rsl.searxng.plist` starts it at login and
restarts it if it dies:

```bash
launchctl load ~/Library/LaunchAgents/com.rsl.searxng.plist
```

Then point Comrade at it:

```bash
export COMRADE_SEARCH_URL="http://127.0.0.1:8889"
```

Check it with one curl:

```bash
curl 'http://127.0.0.1:8889/search?q=test&format=json'
```

JSON comes back, you're done.

## Notes from the install

- macOS system Python (3.9) is too old — SearXNG wants 3.10 or newer.
  Homebrew's python3.12 works fine.
- Some engines fail on first run (DuckDuckGo hands out CAPTCHAs to
  datacenter-looking traffic). SearXNG aggregates; the remaining
  engines carry the query.