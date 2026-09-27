# Lab 15 - Securing your MCP Server with OAuth 2.1

## Relevant Documentation

- [AshAuthentication OAuth2 Server](https://hexdocs.pm/ash_authentication_oauth2_server)
- [AshAuthentication.Phoenix.Oauth2Server.BearerPlug](https://hexdocs.pm/ash_authentication_oauth2_server/AshAuthentication.Phoenix.Oauth2Server.BearerPlug.html)
- [MCP Authorization Specification](https://modelcontextprotocol.io/specification/draft/basic/authorization)
- [Claude: Custom Connectors](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)

## Context

In Lab 11 we protected the MCP server at `/api/mcp` with API keys. That works
for clients you configure yourself, but it means creating a key in a console and
pasting it into every client's config. Remote MCP clients like claude.ai's
custom connectors don't take a static key at all.

They use **OAuth 2.1** instead: the client discovers your authorization server,
registers itself (dynamic client registration), sends the user through your
sign-in and consent screens, and then presents an audience-bound token on every
MCP request. The `ash_authentication_oauth2_server` package turns your existing
AshAuthentication setup into exactly such an authorization server — your
existing users, your existing sign-in page, plus a consent screen and the OAuth
protocol endpoints.

In this lab we'll stand up the OAuth server, switch the MCP endpoint from API
keys to it, and connect to it from Claude. Every MCP tool call still runs with a
user as the actor — now the one who signed in and consented — so the policies
you wrote in Lab 6 keep applying to AI agents exactly as they do to humans.

## Steps

### 1. Add the OAuth server package

In `mix.exs`:

```elixir
{:ash_authentication_oauth2_server, "~> 0.3.0"},
```

Then fetch and compile:

```sh
mix deps.get && mix compile
```

### 2. Run the installer

```sh
mix ash_authentication_oauth2_server.install \
  --accounts Twitter.Accounts --user Twitter.Accounts.User \
  --server-module Twitter.Oauth2Server \
  --secrets-module Twitter.Accounts.Secrets \
  --scope mcp --yes
```

The installer prints a notice suggesting you mount the protocol routes through
the `:api` pipeline — ignore that; we'll mount them bare at the site root in
step 4 so the `/.well-known/*` discovery URLs work.

Have a look at what it scaffolded:

- Four new resources in `lib/twitter/accounts/`: `OauthClient`,
  `OauthAuthorizationCode`, `OauthRefreshToken`, `OauthConsent` — regular Ash
  resources, registered in the `Twitter.Accounts` domain.
- `lib/twitter/oauth2_server.ex` — the configuration module tying them together.
  Note `dcr_enabled?: true` (dynamic client registration — required for Claude
  to register itself) and `scopes: ["mcp"]`. It also sets `cimd_enabled?: true`
  — Client ID Metadata Documents, where a client identifies itself with an HTTPS
  URL pointing at its own metadata; that's the registration mechanism the
  current MCP spec recommends, with DCR kept for compatibility.
- Because `cimd_enabled?: true` is set, `OauthClient` must also carry the
  `AshAuthentication.Oauth2Server.ClientResource` extension (no migration
  needed). Without it a client row is stored for every distinct URL `client_id`
  ever resolved at `/authorize` and nothing prunes them — an unbounded-growth
  denial-of-service vector, so the compiler rejects the combination:

  ```elixir
  use Ash.Resource,
    extensions: [AshAuthentication.Oauth2Server.ClientResource],
    ...
  ```

- Three new `secret_for/4` clauses in `Twitter.Accounts.Secrets` for
  `:issuer_url`, `:resource_url` and `:signing_secret`, with localhost defaults
  written to `config/dev.exs`. That config lands **only** in `config/dev.exs` —
  `mix test` never hits the OAuth endpoints so nothing breaks, but if you want
  to poke at the server from a test or `MIX_ENV=test` console, set the same keys
  in `config/test.exs` (or via `Application.put_env/3`) first.
- `{:req, "~> 0.5"}` added to `mix.exs` — the installer makes it a direct
  dependency (the server uses it to fetch client-metadata documents).
- An `AshAuthentication.Oauth2Server.Supervisor` child in `application.ex` (it
  prunes expired codes and tokens).

### 3. Generate and run the migrations

```sh
mix ash.codegen add_oauth2_server
mix ash.migrate
```

### 4. Mount the routes and protect the MCP endpoint

In `lib/twitter_web/router.ex`, add next to the existing
`use AshAuthentication.Phoenix.Router`:

```elixir
use AshAuthentication.Phoenix.Oauth2Server.Router
```

The consent screen needs to know who is consenting, so the `:browser` pipeline
must set the actor. Add this after `plug :load_from_session`:

```elixir
plug :set_actor, :user
```

Replace the API key plug in the `:mcp` pipeline from Lab 11 with one that
verifies OAuth bearer tokens and sets the actor:

```elixir
pipeline :mcp do
  plug AshAuthentication.Phoenix.Oauth2Server.BearerPlug,
    oauth2_server: Twitter.Oauth2Server,
    required?: true
end
```

(The API key strategy can stay on `User`; nothing reads API keys from requests
anymore.)

Mount the two route groups:

```elixir
# Consent screen — browser pipeline (session + CSRF + actor)
scope "/" do
  pipe_through :browser
  oauth2_server_consent_routes oauth2_server: Twitter.Oauth2Server
end

# Protocol endpoints — no CSRF, at the site root so /.well-known/* is
# where clients expect it
scope "/" do
  oauth2_server_protocol_routes oauth2_server: Twitter.Oauth2Server
end
```

The MCP scope from Lab 11 already does `pipe_through :mcp`, so it's now
protected by OAuth:

```elixir
scope "/api" do
  pipe_through :mcp

  scope "/mcp" do
    forward "/", AshAi.Mcp.Router,
      tools: [:read_feed, :ash_lua_docs, :ash_lua_eval],
      otp_app: :twitter
  end
end
```

:warning: Do **not** pass `actor:` in the `forward` options — router options
override the actor the plug extracted from the token.

### 5. Walk the discovery chain yourself

Start the server (`mix phx.server`) and do what Claude will do:

```sh
# An unauthenticated MCP request is rejected with a challenge...
curl -i -X POST http://localhost:4000/api/mcp \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{}}'
# HTTP/1.1 401 Unauthorized
# www-authenticate: Bearer resource_metadata="http://localhost:4000/.well-known/oauth-protected-resource"

# ...which points at the protected-resource metadata...
curl http://localhost:4000/.well-known/oauth-protected-resource

# ...which points at the authorization server metadata:
curl http://localhost:4000/.well-known/oauth-authorization-server
```

Note `"code_challenge_methods_supported": ["S256"]` (PKCE) and the
`registration_endpoint` — that's the whole contract remote MCP clients need.

### 6. Register a client, like Claude would

```sh
curl -X POST http://localhost:4000/oauth/register \
  -H 'content-type: application/json' \
  -d '{"client_name":"Claude","redirect_uris":["https://claude.ai/api/mcp/auth_callback"],"grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"none"}'
```

You get back a `client_id` — but no `client_secret`. With
`token_endpoint_auth_method: "none"` this is a **public client**: the code
exchange is protected by PKCE rather than a secret, which is exactly what remote
MCP clients like Claude use. Check the AshAdmin UI (`/admin`): the client is a
row in the `OauthClient` resource, created through a normal Ash action.

### 7. Connect from Claude

Claude's servers must be able to reach your app, so for a local demo you need a
tunnel:

```sh
ngrok http 4000
```

Update the issuer/resource URLs in `config/dev.exs` to the tunnel URL
(`oauth2_issuer_url`, `oauth2_resource_url`) and restart.

- **claude.ai**: Settings → Connectors → Add custom connector → enter
  `https://<your-tunnel>/api/mcp`. Claude registers itself, opens your sign-in
  page, shows the consent screen, and connects.
- **Claude Code**: remove the API key entry from Lab 11 first, then add the
  server without a header:

  ```sh
  claude mcp remove twitter
  claude mcp add --transport http twitter https://<your-tunnel>/api/mcp
  # then inside Claude Code, run /mcp and complete the sign-in
  ```

- **Claude Desktop**: in the `twitter` entry of `claude_desktop_config.json`,
  drop the `--header` arguments and the `env` block, and point `mcp-remote` at
  `https://<your-tunnel>/api/mcp`. After you restart Claude Desktop,
  `mcp-remote` opens the sign-in page in your browser.

Ask Claude to read the feed — then check your logs: the tool call runs with the
OAuth user as actor, and the policies from Lab 6 apply.

## Try on your own

- Enforce the scope instead of just advertising it: add
  `AshAuthentication.Phoenix.Oauth2Server.RequireScopePlug` to the `:mcp`
  pipeline.
- Turn `dcr_enabled?` off and connect claude.ai using a pre-registered client id
  (custom connector "Advanced settings").
- The protocol endpoints are unauthenticated by design — read the "Rate
  limiting" section of the `AshAuthentication.Oauth2Server` docs and add the
  suggested plug.
- Revoke the connector's token from `/oauth/revoke` (or delete the refresh token
  row in AshAdmin) and watch Claude re-authenticate.
