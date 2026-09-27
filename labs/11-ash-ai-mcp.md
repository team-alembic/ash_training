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
   tools like reading the tweet feed, and only to callers with an API key

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

- Add `ash_ai` and `req_llm` (the LLM client we'll use from Lab 12 on) to
  `mix.exs`
- Add `:ash_ai` to the `import_deps` list in `.formatter.exs`
- **Automatically configure the development MCP server** at
  `http://localhost:4000/ash_ai/mcp`

That's all the installer touches — `mix.exs`, `.formatter.exs`, and
`endpoint.ex`. Wiring up domains and tools is our job in the steps below.

The installer adds `req_llm` to `mix.exs` but doesn't fetch it, so run this
next:

```bash
mix deps.get
```

The installer adds the development MCP server to `lib/twitter_web/endpoint.ex`,
inside the `if code_reloading? do` block:

```elixir
if code_reloading? do
  plug AshAi.Mcp.Dev,
    otp_app: :twitter,
    path: "/ash_ai/mcp"

  # ...
end
```

If the installer also added a `protocol_version_statement` option to the plug
(with a comment about older protocol versions), delete it and the comment. AshAi
negotiates the MCP protocol version with each client by itself.

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

#### Claude Desktop

Claude Desktop starts MCP servers as local commands, so it reaches an HTTP
server through the `mcp-remote` bridge (this needs Node.js for `npx`). Open
Settings → Developer → Edit Config and add the server to
`claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "ash_ai": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "http://localhost:4000/ash_ai/mcp"]
    }
  }
}
```

Then quit Claude Desktop completely and reopen it; it only reads the config on
startup.

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
    tool :read_feed, Twitter.Tweets.Tweet, :feed
  end
end
```

A tool takes its description from its action, and the description is what tells
the model what a tool is for. So describe the `:feed` action in
`lib/twitter/tweets/tweet.ex`:

```elixir
read :feed do
  description "All tweets, newest first."
  prepare build(sort: [inserted_at: :desc])
end
```

Note that the snippet also adds `otp_app: :twitter` to the `use Ash.Domain`
options — that's new here. We'll rely on it in step 8, where ash_lua looks up
domains by OTP app, so add it now while you're editing the file.

Each tool definition:

- Has a unique name (`:read_feed`)
- Points to a resource (`Twitter.Tweets.Tweet`)
- Specifies an action (`:feed`)
- Uses the action's description, unless you pass `description "..."` to the tool
  to override it. Describing the action is usually better: the Lua docs in step
  8 show the same descriptions.

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
fine-grained control over what's available, and who may use it: every tool call
should run with a user as the actor, so your policies apply to the AI just as
they do to people.

We'll identify callers with API keys, using AshAuthentication's API key
strategy:

```bash
mix ash_authentication.add_strategy api_key
mix ash.migrate
```

The installer:

- creates `Twitter.Accounts.ApiKey`, which stores the user a key belongs to, its
  `expires_at`, and only a hash of the key itself
- adds the `api_key` strategy, a `sign_in_with_api_key` action and a
  `has_many :valid_api_keys` relationship (keys that haven't expired) to
  `Twitter.Accounts.User`
- registers `Twitter.Accounts.ApiKey` in the `Twitter.Accounts` domain
- generates the migration for the `api_keys` table. The installer warns that it
  "includes destructive operations"; that refers to the migration's `down`,
  which drops the table again. `up` only creates it.
- adds `plug AshAuthentication.Strategy.ApiKey.Plug` with `required?: false` to
  the `:api` pipeline in `lib/twitter_web/router.ex`

Remove that plug from the `:api` pipeline again: the plug reads keys from the
`Authorization: Bearer ...` header, where the `:api` pipeline expects the tokens
from Lab 9, and it would reject those. Give the MCP server its own pipeline
instead:

```elixir
pipeline :mcp do
  plug AshAuthentication.Strategy.ApiKey.Plug, resource: Twitter.Accounts.User
end
```

The plug looks up the key's user and sets it as the actor, which AshAi's MCP
server passes on to every action it runs. We leave out `required?: false`, so
the plug uses its default, `required?: true`: a request without a valid key gets
a `401`.

Then add a **new, separate** `scope "/api"` block for the MCP server — don't
nest it inside the existing `scope "/api"` that does `pipe_through :api`:

```elixir
scope "/api" do
  pipe_through :mcp

  scope "/mcp" do
    forward "/", AshAi.Mcp.Router,
      tools: [:read_feed],
      otp_app: :twitter
  end
end
```

This makes the production MCP server available at `/api/mcp` and exposes only
the `read_feed` tool. The tool is referenced using the tool name from the
`tools` block we just defined.

**Note:** The development MCP server gives your coding agent a fixed set of
development tools (`list_ash_resources`, `list_generators`, `get_usage_rules`).
The production server only exposes the tools you explicitly list in the `tools:`
option, which gives you precise control over what external AI assistants can
access. Limiting the tool list is not authentication, though; that's what the
API key is for.

An API key works for clients you configure yourself. In Lab 15 we'll add OAuth
2.1, which remote clients like claude.ai's custom connectors need. Before
deploying either, also add rate limiting.

### 6. Test the Production MCP Server

Restart your Phoenix server so it picks up the new strategy and routes. This
time start it with IEx, since we'll need a console:

```bash
iex -S mix phx.server
```

Create an API key for your user in the IEx console. Use the email you signed up
with:

```elixir
require Ash.Query

query = Ash.Query.filter(Twitter.Accounts.User, email == "you@example.com")
user = Ash.read_one!(query, authorize?: false)
expires_at = DateTime.add(DateTime.utc_now(), 30, :day)

api_key =
  Ash.create!(Twitter.Accounts.ApiKey, %{user_id: user.id, expires_at: expires_at},
    authorize?: false
  )

api_key.__metadata__.plaintext_api_key
```

Copy the key (it starts with `twitter_`). It's only available right after
creation: the database stores just its hash. (`authorize?: false` is needed
because `ApiKey`'s policies only let AshAuthentication itself in; that's fine in
a console, where you're the admin.)

Smoke-test the server with curl. First initialize a session — note that the
`accept` header must offer both content types:

```bash
curl -isS http://localhost:4000/api/mcp \
  -H "authorization: Bearer <your api key>" \
  -H "content-type: application/json" \
  -H "accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"0.0.0"}}}'
```

The response carries an `mcp-session-id` header. Pass it back on subsequent
requests:

```bash
curl -sS http://localhost:4000/api/mcp \
  -H "authorization: Bearer <your api key>" \
  -H "content-type: application/json" \
  -H "accept: application/json, text/event-stream" \
  -H "mcp-session-id: <value from the initialize response>" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
```

You should see exactly one tool: `read_feed`. Leave out the `authorization`
header and you get a `401` instead. The same two commands work against the
development server if you swap the URL for `http://localhost:4000/ash_ai/mcp`;
it doesn't need a key.

Now connect Claude to it.

#### Claude Code

```bash
claude mcp add --transport http twitter http://localhost:4000/api/mcp \
  --header "Authorization: Bearer <your api key>"
```

Run `/mcp` inside Claude Code to check that `twitter` is connected.

#### Claude Desktop

Add a second entry next to `ash_ai` in `claude_desktop_config.json` (Settings →
Developer → Edit Config):

```json
{
  "mcpServers": {
    "twitter": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote",
        "http://localhost:4000/api/mcp",
        "--header",
        "Authorization:${TWITTER_AUTH}"
      ],
      "env": {
        "TWITTER_AUTH": "Bearer <your api key>"
      }
    }
  }
}
```

The header value comes from `env` so that the arguments contain no spaces;
Claude Desktop on Windows doesn't pass arguments with spaces through correctly.
Quit Claude Desktop completely and reopen it. If the server doesn't show up, its
log is at `~/Library/Logs/Claude/mcp-server-twitter.log` (macOS) or
`%APPDATA%\Claude\logs\mcp-server-twitter.log` (Windows).

Ask Claude what's in the tweet feed. It calls `read_feed`, as your user.

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

The Lua runtime is pure BEAM (the `lua` package) — no system Lua install
required. The installer adds `ash_lua` to `mix.exs` and to the `import_deps`
list in `.formatter.exs`.

### 8. Declare the Lua Surface

With ash_lua, you declare on each domain which actions Lua scripts may call, as
named Lua functions grouped into namespaces.

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

Then add a `lua` block to `Twitter.Tweets`:

```elixir
lua do
  namespace "tweets" do
    action :feed, Twitter.Tweets.Tweet, :feed, labels: [:agent, :read_only]
    action :list, Twitter.Tweets.Tweet, :read, labels: [:agent, :read_only]
    action :create, Twitter.Tweets.Tweet, :create, labels: [:agent]
  end

  namespace "likes" do
    action :list, Twitter.Tweets.Like, :read, labels: [:agent, :read_only]
    action :like, Twitter.Tweets.Like, :like, labels: [:agent]
    action :unlike, Twitter.Tweets.Like, :unlike, labels: [:agent]
  end
end
```

and one to `Twitter.Accounts`:

```elixir
lua do
  namespace "users" do
    action :list, Twitter.Accounts.User, :read, labels: [:agent, :read_only]
  end
end
```

Each `action` maps a Lua function to an Ash action:
`action :feed, Twitter.Tweets.Tweet, :feed` inside `namespace "tweets"` makes
the `:feed` action callable as `tweets.feed(...)` from Lua. Only the actions you
map exist in Lua, and the resources themselves don't need an extension for this.

The `labels` tag actions so that each agent surface (next step) can pick the
ones it's allowed to use. We use `:agent` for everything our MCP agent may call,
and `:read_only` for the reads; you'll use that one in "Try on your own".

Lua scripts only see public fields. A like's `tweet_id` and `user_id` aren't
public yet, so `likes.list` couldn't tell you which tweet a like belongs to.
Make them public in `lib/twitter/tweets/like.ex`:

```elixir
belongs_to :tweet, Twitter.Tweets.Tweet do
  allow_nil? false
  attribute_public? true
end

belongs_to :user, Twitter.Accounts.User do
  allow_nil? false
  attribute_public? true
end
```

The model learns what each function does from ash_lua's docs, which show the
resource and action descriptions. `:feed` has one from step 4; describe the rest
of the surface too. In `lib/twitter/tweets/tweet.ex`:

```elixir
resource do
  description "A short post written by a user. Other users can like it."
end
```

```elixir
create :create do
  description "Post a new tweet as the current user."
  # ...
end
```

In `lib/twitter/tweets/like.ex`:

```elixir
resource do
  description "A user's like of a tweet. A user can like each tweet once."
end
```

```elixir
create :like do
  description "Like a tweet as the current user. Liking it again changes nothing."
  # ...
end

destroy :unlike do
  description "Remove the current user's like from a tweet."
  # ...
end
```

And in `lib/twitter/accounts/user.ex`:

```elixir
resource do
  description "A user of the app. A user's email is only visible to that user."
end
```

The three `list` functions map the `:read` actions from `defaults [:read]`,
which can't take a description, so their docs pages have none. Their results
link to the record type's page, which shows the resource description.

### 9. Create the Agent Surface

Now create a dedicated resource for the agent. The `AshLua.EvalActions`
extension synthesizes the two generic actions (`:docs` and `:eval`) on it, and
its `labels` pick which mapped actions scripts may call.

Create `lib/twitter/agents/mcp_actions.ex`:

```elixir
defmodule Twitter.Agents.McpActions do
  use Ash.Resource,
    domain: Twitter.Agents,
    extensions: [AshLua.EvalActions]

  eval_actions do
    labels [:agent]
  end
end
```

An action is included when it has any of the listed labels. Scripts can only
call those actions — everything else doesn't exist as far as the LLM is
concerned. This is the natural place to apply least privilege; you can also run
multiple agent resources side by side, each with its own labels.

(Once you've built the `:semantic_search` action in Lab 13, come back and map it
in the `tweets` namespace, e.g.
`action :search, Twitter.Tweets.Tweet, :semantic_search, labels: [:agent, :read_only]`
— scripts will be able to search semantically too.)

ash_lua builds an agent's Lua surface once, on first use, and code reloading
doesn't refresh it. Whenever you change a `lua` block or an agent's `labels`
later on, restart `mix phx.server` to see the change.

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
    tool :ash_lua_docs, Twitter.Agents.McpActions, :docs do
      description "Read the docs for the Lua API: which tweet, like and user actions a script can call, and how."
    end

    tool :ash_lua_eval, Twitter.Agents.McpActions, :eval do
      description "Run a Lua script against that API. Use it for questions that need several queries, filtering or arithmetic, and get the final answer in one call."
    end
  end
end
```

Without a `description`, the tools show up as "Call the docs tool" and "Call the
eval tool", which gives the model no reason to use them.

Don't forget to register the new domain in `config/config.exs` under
`config :twitter, ash_domains: [...]`.

### 11. Expose via the Production MCP Server

Add the two new tools to the `tools:` list in `lib/twitter_web/router.ex`:

```elixir
forward "/", AshAi.Mcp.Router,
  tools: [:read_feed, :ash_lua_docs, :ash_lua_eval],
  otp_app: :twitter
```

Now restart the server (`iex -S mix phx.server`): the new dependency from step 7
and the `config/config.exs` change from step 10 both need a restart. Run the
step 6 `tools/list` smoke test and you should see all three tools.

Your Claude clients lost the connection when the server stopped. In Claude Code,
run `/mcp` and reconnect `twitter`; quit and reopen Claude Desktop.

### 12. Walkthrough

This is more interesting with some data: if you only have a tweet or two, create
a few more in the app (and like some of them) first.

Connect an MCP client to `/api/mcp` and ask it something compositional, like
"How long are the last three tweets?". The server also exposes `read_feed`, and
for a question this small the model may simply use that. To watch it work with
just the two Lua tools, temporarily take `:read_feed` out of the `tools:` list.

First, it discovers the surface:

```text
LLM → ash_lua_docs({})
←   a compact index of every operation in the scoped surface
    (tweets.feed, tweets.create, likes.like, ...)

LLM → ash_lua_docs({ name = "tweets.feed" })
←   the focused page for that one operation: inputs, fields, examples
```

`ash_lua_docs` also takes `search: "..."` to get a ranked list of matching
operations, types, and topics.

Then it composes the whole task as one script:

```text
LLM → ash_lua_eval({ script = """
  local feed = assert(tweets.feed({ limit = 3, fields = { "text" } }))

  local lengths = {}
  for i, tweet in ipairs(feed) do
    lengths[i] = #tweet.text
  end

  return { feed = feed, lengths = lengths }
""" })
```

Note the single table in `return`. Lua scripts here follow the `value, err`
convention: a second return value is treated as an error, so
`return feed, lengths` would report `lengths` as the error.

(The `tool({ ... })` calls above are shorthand for readability. On the wire,
ash_ai tools put the action's inputs — its arguments and accepted attributes —
under an `input` key in the `inputSchema`. Read options such as `limit`,
`filter` and `sort` on tools like `read_feed` stay at the top level. So the
actual JSON-RPC request looks like this:

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
  result: <the script's first return value; nil if the script raised>,
  error: <nil on success; otherwise an error table: %{class: "lua_error", ...}
          if the script raised, or the script's second return value in the
          same shape>,
  print_output: [<lines printed with print(...); empty if the script raised>]
}
```

One `eval` call replaced what would otherwise be several tool round-trips plus
arithmetic in the model's head — and every Ash call inside the script still
flowed through the session's actor and your policies.

The actor is your API key's user, so scripts can write, too. Ask Claude to "like
every tweet that mentions Ash" and check the result in the app: the likes are
yours. A few things to know about the surface:

- `likes.unlike` takes just `{ input = { tweet_id = ... } }`, even though its
  docs page also lists `id`.
- `users.list` returns other users without their `email`: the field policy from
  Lab 6 only shows your own, and fields you may not see are left out. Tweets
  still carry their author's email in `user_email`, because aggregates don't
  apply field policies (see Lab 6) — it's public in the feed on purpose, so the
  model can see it too.

## Try on your own

1. **Define an additional tool** in the `tools` block in
   `lib/twitter/tweets.ex`:
   - Add a `:read_tweet` tool that uses the `:read` action, and expose it via
     the production MCP server's `tools:` list
   - `:read` comes from `defaults [:read, :destroy]`, which has no description,
     so give the tool one:
     `tool :read_tweet, Twitter.Tweets.Tweet, :read do description "Find tweets by filter" end`
   - Note that its results come back as a page (`results`, `has_more`, ...): the
     default `:read` action supports pagination, `:feed` doesn't

2. **Ask a compositional question** through an MCP client connected to
   `/api/mcp` — e.g. "which of the last 10 tweets has the most likes?" — and
   watch whether the model reaches for the per-action tools or composes a single
   `ash_lua_eval` script
   - The read tools only return a tweet's attributes, not aggregates like
     `like_count`, so the model can sort by likes but not see the counts. Load
     them with the `load:` option from step 4, inside the `do` block of both
     read tools: `load [:like_count]` in `:read_feed` and `:read_tweet`. Or take
     the per-action tools out of the `tools:` list again: a Lua script can ask
     for `like_count` in its `fields`

3. **Tighten the surface**: create a second agent surface that only exposes the
   read actions, next to the first one:
   - add `lib/twitter/agents/read_only_mcp_actions.ex` with a
     `Twitter.Agents.ReadOnlyMcpActions` resource (domain `Twitter.Agents`) that
     uses `AshLua.EvalActions` with `labels [:read_only]`
   - add it to the `resources` block in `lib/twitter/agents.ex`, and register
     its `:docs` and `:eval` actions as tools with new tool names (the actions
     can keep their default names; only the tool names must be unique), with
     descriptions like in step 10:

     ```elixir
     tool :ash_lua_read_only_docs, Twitter.Agents.ReadOnlyMcpActions, :docs do
       description "Read the docs for the read-only Lua API: which tweet, like and user reads a script can call, and how."
     end

     tool :ash_lua_read_only_eval, Twitter.Agents.ReadOnlyMcpActions, :eval do
       description "Run a read-only Lua script against that API."
     end
     ```

   - add those two tools to the router's `tools:` list and restart the server
   - check that its docs list only the read operations, and that `tweets.create`
     doesn't exist in its `eval`
