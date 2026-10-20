# Raccoon Bets

[![CI](https://github.com/RISCfuture/raccoonbets-backend/actions/workflows/ci.yml/badge.svg)](https://github.com/RISCfuture/raccoonbets-backend/actions/workflows/ci.yml)
[![Deploy](https://github.com/RISCfuture/raccoonbets-backend/actions/workflows/deploy.yml/badge.svg)](https://github.com/RISCfuture/raccoonbets-backend/actions/workflows/deploy.yml)
[![Ruby](https://img.shields.io/badge/Ruby-4.0.7-red.svg)](https://www.ruby-lang.org)
[![Rails](https://img.shields.io/badge/Rails-8.1.3-red.svg)](https://rubyonrails.org)

Raccoon Bets is a private prediction market for friend groups. Members create
markets like "Will Wenting finish her marathon in under 4:30?", put a dollar or
two into a parimutuel pool, and settle up over Venmo when the dust settles. Each
friend group lives on its own subdomain of
[raccoonbets.org](https://raccoonbets.org).

No real money is held: positions move an internal ledger, and members settle
net balances out-of-band via payment deep links.

This repository contains the Rails API. The Vue 3 front-end lives in a separate
repository at <https://github.com/RISCfuture/raccoonbets-frontend>.

## Development

### Installation and Running

The back-end requires Ruby 4.0.7, PostgreSQL, and Redis. Install the system
dependencies with Homebrew:

```sh
brew bundle
```

After cloning the repository, run `bundle install` to install gems, then
`bin/rails db:prepare` to create and seed the development database.

The Rails back-end is paired with a Vue 3 front-end whose repository is hosted
at <https://github.com/RISCfuture/raccoonbets-frontend>. Clone both repositories
as siblings. To run the whole stack in development, create a `Procfile` in the
parent directory such as:

```procfile
backend: cd Backend && PORT=5000 ANYCABLE_HTTP_RPC=true rvm 4.0.7@raccoonbets do rails server
frontend: cd Frontend && pnpm dev
ws: cd Backend && rvm 4.0.7@raccoonbets do bin/anycable-go --port=8080 --rpc_host=http://localhost:5000/_anycable
```

`PORT=5000` matches `config/urls.yml` and the front-end's `.env` files; Puma
would otherwise default to 3000. `ANYCABLE_HTTP_RPC` mounts AnyCable's RPC
endpoint at `/_anycable` inside the Rails server, the way production runs it, so
no separate RPC process is needed. Pass `--port` to `anycable-go` explicitly: it
also reads `$PORT`, which overmind sets per-process. Sidekiq runs embedded in
Puma (see `config/puma.rb`), so it needs no process of its own either.

Postgres and Redis are expected to be running already, e.g. as brew services
(`brew services start postgresql@18 redis`).

Install `overmind` to run the Procfile with `overmind start`.

Local hosts use `lvh.me`, which resolves any subdomain to 127.0.0.1:

- Apex: <http://lvh.me:5173>
- A group: <http://your-group.lvh.me:5173>
- API: <http://api.lvh.me:5000>

Outgoing email is not delivered in development;
[letter_opener](https://github.com/ryanb/letter_opener) opens each message in
your browser and saves a copy under `tmp/letter_opener`. Signup and login use
Cloudflare Turnstile's always-pass test keys, so no Turnstile or Resend
credentials are needed.

#### Testing

Run the full back-end suite (RSpec, RuboCop, Brakeman) with `bin/ci`, or run the
unit and request specs alone with `rspec spec`.

End-to-end testing is documented in the readme for the front-end.

#### Deployment

The back-end is deployed on Fly.io as `raccoonbets-backend`. A GitHub Action,
defined in the `deploy.yml` workflow, runs after CI completes.

## Architecture

Raccoon Bets is a Ruby on Rails API paired with an independent Vue 3 front-end.
An nginx proxy (the `raccoonbets-proxy` app) is the public front door at
`api.raccoonbets.org`: it routes `/cable` to the AnyCable WebSocket server
(`raccoonbets-anycable`) and everything else to this Rails app.

### Authentication

Authentication is handled by Rodauth, including passkey support.

### Money

No real money changes hands. Each group has its own currency, and every market
is a parimutuel pool: positions move balances on an internal ledger, and members
settle net balances out-of-band through payment deep links.

## Assistant connections (MCP)

Members can connect an OAuth-capable assistant to
`https://api.raccoonbets.org/mcp`. In ChatGPT or Claude, add this URL as a
custom MCP connector and select automatic OAuth client registration. The browser
opens the existing Raccoon Bets login, then asks which groups to share and whether
to allow actions. No groups are selected initially; access defaults to read-only.

Read access includes group settings and members, markets and positions,
discussions, balances, settlement suggestions, and recorded settlements. Write
access adds market creation/editing, the member's own bets, comments, eligible
market resolution/voiding, and settlement recording/voiding. Existing creator,
oracle, admin, and payment-party permissions still apply. The connection does
not expose group administration, account management, market deletion, resolution
correction, or other members' bet cancellation. Recording a settlement does not
initiate a payment.

Connections expire after 30 days. **Account → Connected Apps → Revoke access**
invalidates the connection immediately. To change groups or permissions, revoke
and reconnect from the assistant. Newly joined groups are not added automatically;
leaving a group or its suspension removes access immediately.

### Deployment

Run `bin/rails db:migrate` and deploy both the backend and frontend before setting
`MCP_ENABLED=true` on the backend. The feature is disabled by default outside the
`cypress` browser-test environment. Setting it to `false` disables MCP and new
OAuth requests while keeping account-side revocation available. No additional
process, sticky sessions, or third-party identity provider is required.

OAuth uses authorization codes with S256 PKCE, hashed access and refresh tokens,
15-minute access tokens, single-use refresh rotation, and a fixed 30-day consent
lifetime. Tokens are bound to the configured API origin plus `/mcp`; website JWTs
and assistant tokens are not interchangeable. Configure the public origin in
`config/urls.yml`; discovery never trusts the incoming Host header.

The endpoint uses stateless Streamable HTTP and advertises these tools:

| Capability | Tools |
| --- | --- |
| Groups | `list_groups`, `get_group`, `list_members` |
| Markets | `list_markets`, `get_market`, `create_market`, `update_market` |
| Positions | `set_position`, `cancel_position` |
| Discussion | `post_comment`, `delete_comment` |
| Resolution | `resolve_market`, `void_market` |
| Settlement | `get_balances`, `get_settlement_suggestions`, `list_settlements`, `record_settlement`, `void_settlement` |

`group_id` is the group's subdomain slug. Monetary inputs are integers in the
group currency's minor units. `list_markets` accepts `limit` (maximum 100) and
`offset`; `list_settlements` returns the most recent 100 records. Tool results
include structured JSON and an equivalent text representation. Business failures
return MCP tool errors without exposing internal exceptions.

### Verification

Run `RAILS_ENV=test bin/ci` for backend checks and `bin/rails zeitwerk:check` for
an eager-load check. The frontend's `pnpm test:e2e` includes `e2e/mcp.spec.ts`,
which exercises login, selected-group consent, code exchange, an MCP read, and
revocation against the cypress backend. `E2E_API_URL` overrides its API address;
`CYPRESS_BACKEND_URL`, `CYPRESS_FRONTEND_URL`, and `POSTGRES_DB` allow an isolated
backend when running the browser test on alternate ports.

Before enabling production, connect both ChatGPT and Claude against a test group
and verify discovery, a read, an explicitly authorized write, and revocation.
Local protocol and browser tests do not establish hosted-client compatibility.
