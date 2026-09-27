# Cheat Sheet

## Run IEx

```elixir
iex -S mix
```

## Run IEx with the phoenix server

This gives you a running phoenix server and an IEx prompt.

```elixir
iex -S mix phx.server
```

## Run just the phoenix server

```elixir
mix phx.server
```

## Generate Migrations

```
mix ash.codegen <what_changed_here>
```

While iterating, you can skip naming your changes:

```
mix ash.codegen --dev
```

When you're happy, run `mix ash.codegen <what_changed_here>` to squash the dev
migrations into a properly named one.

## Run Migrations

```
mix ash.migrate
```

## Reset the database

```
mix ash.reset
```

## Code Interface

Defined in the domain, inside the block for a resource:

```elixir
resource Twitter.Tweets.Tweet do
  define :feed
  define :get_tweet, action: :read, get_by: [:id]
  define :like, args: [:tweet_id]
end
```

Each `define` generates a `{:ok, _}`/`{:error, _}` returning function
(`Twitter.Tweets.feed()`), a raising `!` variant (`Twitter.Tweets.feed!()`), and
`can_*`/`can_*?` helpers that check your policies without running the action.
Names ending in `?` instead generate a single predicate function that returns a
plain boolean.

### Forms via the Code Interface (`AshPhoenix`)

Add the `AshPhoenix` extension to the domain to also get a `form_to_*` function
for each `define`:

```elixir
use Ash.Domain,
  extensions: [AshPhoenix]
```

```elixir
# define :create_tweet, action: :create   ->
form = Twitter.Tweets.form_to_create_tweet(actor: user)

# define :update_tweet, action: :update   ->
form = Twitter.Tweets.form_to_update_tweet(tweet, actor: user)
```

These return an `AshPhoenix.Form` (built via `AshPhoenix.Form.for_action/3`),
ready for `to_form/1`, `AshPhoenix.Form.validate/2`, and
`AshPhoenix.Form.submit/2`.

## AshJsonApi

Only fields marked `public? true` (attributes, calculations, aggregates) are
exposed. Resource-level config lives in the `json_api` block:

```elixir
json_api do
  type "tweet"

  # Serialize (and accept in filters/sorts/fieldsets) fields as camelCase
  field_names :camelize

  # Hide an already-public field from this JSON:API interface only
  hide_fields [:updated_at]

  routes do
    base "/tweets"

    index :feed                # GET /tweets
    get :read, primary?: true  # GET /tweets/:id (primary? -> used for self links)
    post :create               # POST /tweets
    patch :update              # PATCH /tweets/:id
    delete :destroy            # DELETE /tweets/:id
  end
end
```

## Switching lab branches

Each lab branch is the starting point for that lab. After checking one out:

```
mix setup
```

## AshGraphql

Add the extension with `mix ash.extend Twitter.Tweets.Tweet graphql`. Resource
config lives in the `graphql` block; queries and mutations name an action:

```elixir
# Twitter.Tweets.Tweet
graphql do
  type :tweet
  filterable_fields [:text, like_count: [:eq, :greater_than]]

  queries do
    list :feed, :feed
  end
end

# Twitter.Tweets.Like
graphql do
  type :like

  mutations do
    create :like_tweet, :like

    destroy :unlike_tweet, :unlike do
      identity false
    end
  end
end
```

Playground: <http://localhost:4000/api/gql/playground>, endpoint `/api/gql`.

## AshAi: exposing actions as tools

Tools are declared in the domain, one per action:

```elixir
tools do
  tool :read_feed, Twitter.Tweets.Tweet, :feed do
    description "Retrieve the feed of tweets, sorted by most recent first"
  end

  tool :unlike_tweet, Twitter.Tweets.Like, :unlike do
    description "Unlike a tweet"
    identity false
  end
end
```

A `tool` whose action doesn't exist still compiles; the mistake only shows up
when `tools/list` fails with a 500. If that happens, check each tool's action
name.

The MCP server is mounted at `/api/mcp` and needs an API key. Create one in
`iex -S mix` (the plaintext is only available right after creation):

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

Talk to it by hand:

```bash
# initialize (note the mcp-session-id response header)
curl -isS http://localhost:4000/api/mcp \
  -H "authorization: Bearer <your api key>" \
  -H "content-type: application/json" \
  -H "accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"0.0.0"}}}'

# list tools
curl -sS http://localhost:4000/api/mcp \
  -H "authorization: Bearer <your api key>" \
  -H "content-type: application/json" \
  -H "accept: application/json, text/event-stream" \
  -H "mcp-session-id: <value from the initialize response>" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
```

Register both servers with Claude Code (the dev server needs no key):

```bash
claude mcp add --transport http ash_ai http://localhost:4000/ash_ai/mcp
claude mcp add --transport http twitter http://localhost:4000/api/mcp \
  --header "Authorization: Bearer <your api key>"
```

With Claude Desktop, in `claude_desktop_config.json` (Settings → Developer →
Edit Config; quit and reopen Claude Desktop afterwards):

```json
{
  "mcpServers": {
    "ash_ai": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "http://localhost:4000/ash_ai/mcp"]
    },
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

## AshAi: chat

```bash
export OPENAI_API_KEY="your-api-key-here"
mix ash_ai.gen.chat --live
mix ash.migrate
```

The chat UI is at <http://localhost:4000/chat>. Responses run as Oban jobs
(`ash_oban`), so they only appear while the app, and therefore Oban, is running.

## AshAi: prompt actions

A generic action whose implementation is an LLM call:

```elixir
action :reformulate_query, :string do
  argument :question, :string, allow_nil?: false

  run prompt("openai:gpt-4o-mini",
        prompt: """
        Turn this question into a short search query: <%= @input.arguments.question %>
        """
      )
end
```

## AshAi: vectorization

```elixir
vectorize do
  full_text do
    text fn tweet -> "Tweet: #{tweet.text}" end
    used_attributes [:text]
  end

  embedding_model {AshAi.EmbeddingModels.ReqLLM,
                   model: "openai:text-embedding-3-small", dimensions: 1536}

  strategy :ash_oban
end
```

The vector column and its index each need a migration:

```
mix ash.codegen add_tweet_vectors
mix ash.migrate
```

## Ash.Reactor

A reactor chains Ash actions and plain steps; `result/1` wires step outputs into
later inputs:

```elixir
defmodule Twitter.Ai.RagReactor do
  use Reactor, extensions: [Ash.Reactor]

  input(:question)

  action :reformulate_query, Twitter.Tweets.Tweet, :reformulate_query do
    inputs %{question: input(:question)}
  end

  read :fetch_context_tweets, Twitter.Tweets.Tweet, :semantic_search do
    inputs %{query: result(:reformulate_query)}
  end

  step :build_context do
    argument :tweets, result(:fetch_context_tweets)
    run fn %{tweets: tweets}, _ -> {:ok, Enum.map_join(tweets, "\n", & &1.text)} end
  end

  return :build_context
end
```

Run it from a generic action by passing the module to `run`; Ash maps the
action's arguments to the reactor's inputs:

```elixir
action :ask_with_reactor, :map do
  argument :question, :string, allow_nil?: false
  run Twitter.Ai.RagReactor
end
```

## OAuth 2.1 for the MCP server

```bash
mix ash_authentication_oauth2_server.install \
  --accounts Twitter.Accounts --user Twitter.Accounts.User \
  --server-module Twitter.Oauth2Server \
  --secrets-module Twitter.Accounts.Secrets \
  --scope mcp --yes
mix ash.codegen add_oauth2_server
mix ash.migrate
```

Discovery documents clients use to find the server:

```bash
curl http://localhost:4000/.well-known/oauth-authorization-server
curl http://localhost:4000/.well-known/oauth-protected-resource
```

Dynamic client registration:

```bash
curl -X POST http://localhost:4000/oauth/register \
  -H 'content-type: application/json' \
  -d '{"client_name":"Claude","redirect_uris":["https://claude.ai/api/mcp/auth_callback"],"grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"none"}'
```

To test against claude.ai, expose the dev server with `ngrok http 4000`.

## Spark extensions

An extension is a module that declares DSL sections and transformers:

```elixir
defmodule Twitter.Archival do
  @archive %Spark.Dsl.Section{
    name: :archive,
    schema: [
      attribute: [type: :atom, default: :archived_at, doc: "When the record was archived"]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@archive],
    transformers: [Twitter.Archival.Transformers.SetupArchival]
end
```

An info module turns the section into introspection functions
(`Twitter.Archival.Info.archive_attribute!/1`):

```elixir
defmodule Twitter.Archival.Info do
  use Spark.InfoGenerator, extension: Twitter.Archival, sections: [:archive]
end
```

A transformer rewrites the resource at compile time using
`Ash.Resource.Builder`:

```elixir
defmodule Twitter.Archival.Transformers.SetupArchival do
  use Spark.Dsl.Transformer

  # `defaults [:read, :destroy]` only become real actions in this transformer
  def after?(Ash.Resource.Transformers.SetPrimaryActions), do: true
  def after?(_), do: false

  def transform(dsl_state) do
    attribute = Twitter.Archival.Info.archive_attribute!(dsl_state)
    Ash.Resource.Builder.add_new_attribute(dsl_state, attribute, :utc_datetime_usec)
  end
end
```

Use it like any other extension:

```elixir
use Ash.Resource, extensions: [Twitter.Archival]

archive do
  attribute :deleted_at
end
```

## IEx Cheat Sheet

### Recompile after changes

If you are running the browser application, you can refresh the browser.
Otherwise:

```elixir
recompile
```
