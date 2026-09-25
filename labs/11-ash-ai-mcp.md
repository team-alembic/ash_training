# Lab 11 - AshAi MCP Servers

## Relevant Documentation

- [AshAi.Mcp Documentation](https://hexdocs.pm/ash_ai/AshAi.Mcp.html)
- [Model Context Protocol Specification](https://spec.modelcontextprotocol.io/)
- [AshLua Documentation](https://hexdocs.pm/ash_lua)
- [AshLua: Integrate with ash_ai](https://hexdocs.pm/ash_lua/integrate-with-ash-ai.html)

## Context

The Model Context Protocol (MCP) is a standardized way to expose tools and
context to AI assistants like Claude Code, Cursor, Zed, and Windsurf. AshAi
provides built-in MCP server support to expose your application's capabilities
to these tools.

In this lab, we'll set up two MCP servers:

1. **Development MCP Server** - For use with IDEs and development tools
2. **Production MCP Server** - For controlled access, exposing only specific
   tools like reading the tweet feed

Then, as a finale, we'll add **ash_lua** to the production server — instead of
one tool per action, the LLM gets exactly two tools: one to read the exposed API
surface and one to execute a composed Lua script against it.

## Steps

### 1. Install AshAi Dependencies

Install AshAi using igniter:

```bash
mix igniter.install ash_ai
```

This will:

- Add `ash_ai` and its dependencies to `mix.exs`
- Add `:ash_ai` to the `import_deps` list in `.formatter.exs`
- **Automatically configure the development MCP server** at
  `http://localhost:4000/ash_ai/mcp`

That's all the installer touches — `mix.exs`, `.formatter.exs`, and
`endpoint.ex`. Wiring up domains and tools is our job in the steps below.

The installer adds the development MCP server to `lib/twitter_web/endpoint.ex`,
inside the `if code_reloading? do` block:

```elixir
if code_reloading? do
  plug AshAi.Mcp.Dev,
    # For many tools, you will need to set the `protocol_version_statement` to the older version.
    protocol_version_statement: "2024-11-05",
    otp_app: :twitter,
    path: "/ash_ai/mcp"

  # ...
end
```

The `protocol_version_statement` tells clients which MCP protocol version the
server speaks — many AI coding tools still expect the older version, so the
installer states it explicitly.

### 2. Configure Development Tools

Start your server:

```bash
mix phx.server
```

The MCP server is available, but your AI coding tools need to know about it. The
configuration varies by tool:

#### Claude Code

```bash
claude mcp add --transport http ash_ai http://localhost:4000/ash_ai/mcp
```

#### For Zed

Add to your Zed settings (you'll need the mcp-proxy
https://hexdocs.pm/tidewave/mcp_proxy.html):

```json
{
  "ash_ai": {
    "command": "/path/to/mcp-proxy",
    "args": ["http://localhost:4000/ash_ai/mcp"],
    "env": {}
  }
}
```

### 3. Test the Development MCP Server

Try to ask your agent which Ash resources we have in the project.

No MCP client set up? You can also poke an MCP server with plain curl — see the
smoke test in step 6; the same commands work against `/ash_ai/mcp`.

### 4. Define Tools in the Domain

Before we can expose tools via the MCP server, we need to define them in our
domain module. Tools are declarative definitions that map actions on resources
to callable functions.

Open `lib/twitter/tweets.ex` and add the AshAi extension and a `tools` block:

```elixir
defmodule Twitter.Tweets do
  use Ash.Domain,
    otp_app: :twitter,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain, AshAdmin.Domain, AshPhoenix, AshAi]

  # ... existing resources block ...

  tools do
    tool :read_feed, Twitter.Tweets.Tweet, :feed do
      description "Retrieve the feed of tweets, sorted by most recent first"
    end
  end
end
```

Note that the snippet also adds `otp_app: :twitter` to the `use Ash.Domain`
options — that's new here. We'll rely on it in step 8, where ash_lua looks up
domains by OTP app, so add it now while you're editing the file.

Each tool definition:

- Has a unique name (`:read_feed`)
- Points to a resource (`Twitter.Tweets.Tweet`)
- Specifies an action (`:feed`)
- Includes a description for the AI to understand what the tool does, defaults
  to the actions description if not provided.

Other useful options on `tool`:

- `load:` — preload calculations or relationships onto the returned records,
  e.g. `load: [user: [:email]]`
- `get_by: :id` — turn a read tool into a single-record lookup by field
- `identity false` — for update/destroy tools on actions that don't take a
  record identity (like our `:unlike` action)

These tools can now be called by AI assistants and exposed via the MCP server.

### 5. Set Up Production MCP Server

The production MCP server allows you to expose specific tools to external AI
assistants. Unlike the development server, the production server gives you
fine-grained control over what's available.

Add a **new, separate** `scope "/api"` block for it in
`lib/twitter_web/router.ex` — don't nest it inside the existing `scope "/api"`
that does `pipe_through :api`; the MCP endpoint must not go through the JSON API
pipeline. No special pipeline is needed at all, content negotiation is handled
inside `AshAi.Mcp.Router`:

```elixir
scope "/api" do
  scope "/mcp" do
    forward "/", AshAi.Mcp.Router,
      tools: [:read_feed],
      # For many tools, you will need to set the `protocol_version_statement` to the older version.
      protocol_version_statement: "2024-11-05",
      otp_app: :twitter
  end
end
```

This makes the production MCP server available at `/api/mcp` and exposes only
the `read_feed` tool. The tool is referenced using the tool name from the
`tools` block we just defined.

**Note:** Unlike the development MCP server which automatically exposes all Ash
resources and their actions, the production server only exposes the tools you
explicitly list in the `tools:` option. This gives you precise control over what
external AI assistants can access.

This training route is intentionally unauthenticated for local use. Before
deploying it, require authentication supported by your MCP clients (OAuth 2.1 or
an API key), authorize the resulting actor, and add rate limiting. Limiting the
tool list is not an authentication mechanism. In Lab 15 we'll do exactly that:
secure this endpoint with OAuth 2.1 so every tool call runs with a signed-in
user as the actor.

### 6. Test the Production MCP Server

Start your Phoenix server:

```bash
mix phx.server
```

You can test the MCP server by connecting to it from an MCP client. The server
exposes the `read_feed` tool which retrieves the feed of tweets.

You can also smoke-test it with curl. First initialize a session — note that the
`accept` header must offer both content types:

```bash
curl -isS http://localhost:4000/api/mcp \
  -H "content-type: application/json" \
  -H "accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"curl","version":"0.0.0"}}}'
```

The response carries an `mcp-session-id` header. Pass it back on subsequent
requests:

```bash
curl -sS http://localhost:4000/api/mcp \
  -H "content-type: application/json" \
  -H "accept: application/json, text/event-stream" \
  -H "mcp-session-id: <value from the initialize response>" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
```

You should see exactly one tool: `read_feed`. The same two commands work against
the development server if you swap the URL for
`http://localhost:4000/ash_ai/mcp`.

## Two tools instead of many — ash_lua

Defining one MCP tool per action works well for direct, single-action requests
("create this tweet", "look up that user"). It breaks down when the request is
compositional: "how long are the last three tweets?" means N tool round-trips,
intermediate results held in the model's context window, and arithmetic the
model has to do itself.

**ash_lua** flips this around. The LLM gets exactly two tools:

- `ash_lua_docs` — read documentation for the exposed API surface
- `ash_lua_eval` — run a Lua script that calls those actions

The model composes the whole task (query + filter + arithmetic) as one Lua
script and gets back the final value in a single round-trip. And crucially, the
calling actor, tenant, and context are passed straight through to every Ash call
the script performs — there is no way for a script to escalate, switch tenants,
or call actions outside the scoped set. All your policies still apply.

### 7. Install ash_lua

```bash
mix igniter.install ash_lua
```

The Lua runtime is pure BEAM (Luerl) — no system Lua install required.

### 8. Expose Resources to Lua

ash_lua ships two Spark extensions: `AshLua.Domain` for domain modules and
`AshLua.Resource` for each resource you want callable from Lua.

Add `AshLua.Domain` to `lib/twitter/tweets.ex` and `lib/twitter/accounts.ex`
(both domains also need `otp_app: :twitter` so ash_lua can find them):

```elixir
defmodule Twitter.Tweets do
  use Ash.Domain,
    otp_app: :twitter,
    extensions: [
      AshGraphql.Domain,
      AshJsonApi.Domain,
      AshAdmin.Domain,
      AshPhoenix,
      AshAi,
      AshLua.Domain
    ]
```

(Append `AshLua.Domain` to whatever extensions the domain already has — don't
drop any of the existing ones.)

Then add `AshLua.Resource` to `tweet.ex`, `like.ex`, and `user.ex`:

```elixir
defmodule Twitter.Tweets.Tweet do
  use Ash.Resource,
    # ...
    extensions: [AshGraphql.Resource, AshJsonApi.Resource, AshLua.Resource]
```

By default the domain is exposed under a Lua table named after the module's last
segment, and each resource under a similarly derived key — so the `:feed` action
becomes callable as `tweets.tweet.feed(...)` from Lua.

### 9. Create the Agent Surface

Now create a dedicated resource that defines _which_ actions scripts may call.
The `AshLua.EvalActions` extension synthesizes the two generic actions (`:docs`
and `:eval`) on it.

Create `lib/twitter/agents/mcp_actions.ex`:

```elixir
defmodule Twitter.Agents.McpActions do
  use Ash.Resource,
    domain: Twitter.Agents,
    extensions: [AshLua.EvalActions]

  eval_actions do
    resource Twitter.Tweets.Tweet, actions: [:read, :feed, :create]
    resource Twitter.Tweets.Like, actions: [:read, :like, :unlike]
    resource Twitter.Accounts.User, actions: [:read]
  end
end
```

(Once you've built the `:semantic_search` action in Lab 13, come back and add it
to the `Tweet` list — scripts will be able to search semantically too.)

The `eval_actions` block is the source of truth: scripts can only call the
listed `(resource, action)` pairs — everything else doesn't exist as far as the
LLM is concerned. This is the natural place to apply least privilege; you can
also run multiple agent resources side by side, each with its own scope.

### 10. Register the Two Tools

Create the `Twitter.Agents` domain in `lib/twitter/agents.ex` and register both
synthesized actions as ordinary ash_ai tools:

```elixir
defmodule Twitter.Agents do
  use Ash.Domain, otp_app: :twitter, extensions: [AshAi]

  resources do
    resource Twitter.Agents.McpActions
  end

  tools do
    tool :ash_lua_docs, Twitter.Agents.McpActions, :docs
    tool :ash_lua_eval, Twitter.Agents.McpActions, :eval
  end
end
```

Don't forget to register the new domain in `config/config.exs` under
`config :twitter, ash_domains: [...]`.

### 11. Expose via the Production MCP Server

Add the two new tools to the `tools:` list in `lib/twitter_web/router.ex`:

```elixir
forward "/", AshAi.Mcp.Router,
  tools: [:read_feed, :ash_lua_docs, :ash_lua_eval],
  # For many tools, you will need to set the `protocol_version_statement` to the older version.
  protocol_version_statement: "2024-11-05",
  otp_app: :twitter
```

### 12. Walkthrough

Connect an MCP client to `/api/mcp` and watch how the model drives itself with
just the two tools.

First, it discovers the surface:

```text
LLM → ash_lua_docs({})
←   full markdown index of the scoped surface
    (tweets.tweet.feed, tweets.tweet.create, tweets.like.like, ...)

LLM → ash_lua_docs({ name = "tweets.tweet.feed" })
←   the focused page for that one operation: inputs, fields, examples
```

`ash_lua_docs` also takes `search: "..."` to get a ranked list of matching
operations, types, and topics.

Then it composes the whole task as one script:

```text
LLM → ash_lua_eval({ script = """
  local feed = assert(tweets.tweet.feed({ limit = 3, fields = { "text" } }))

  local lengths = {}
  for i, tweet in ipairs(feed) do
    lengths[i] = #tweet.text
  end

  return feed, lengths
""" })
```

(The `tool({ ... })` calls above are shorthand for readability. On the wire,
every tool generated by ash_ai nests its arguments under a required `input` key
in the `inputSchema`, so the actual JSON-RPC request looks like this:

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "ash_lua_eval",
    "arguments": { "input": { "script": "..." } }
  }
}
```

MCP clients handle this automatically — it only matters if you're crafting
requests by hand, e.g. with the curl smoke test from step 6.)

The response is a stable shape:

```elixir
%{
  result: <the script's return value, or nil on error>,
  error: <%{class, errors: [...]} or nil>,
  print_output: [<anything the script printed>, ...]
}
```

One `eval` call replaced what would otherwise be several tool round-trips plus
arithmetic in the model's head — and every Ash call inside the script still
flowed through the session's actor and your policies.

## Try on your own

1. **Define an additional tool** in the `tools` block in
   `lib/twitter/tweets.ex`:
   - Add a `:read_tweet` tool that uses the `:read` action, and expose it via
     the production MCP server's `tools:` list

2. **Ask a compositional question** through an MCP client connected to
   `/api/mcp` — e.g. "which of the last 10 tweets has the most likes?" — and
   watch whether the model reaches for the per-action tools or composes a single
   `ash_lua_eval` script

3. **Tighten the surface**: create a second `AshLua.EvalActions` resource that
   only exposes read actions, register it under different tool names
   (`eval_action_name` / `docs_action_name` avoid collisions), and expose it
   alongside the first
