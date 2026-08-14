# Lab 12 - AshAi Chat Setup & Tools

## Relevant Documentation

- [AshAi Documentation](https://hexdocs.pm/ash_ai)
- [AshAi GitHub](https://github.com/ash-project/ash_ai)
- [Getting Started with AshAi](https://alembic.com.au/blog/ash-ai-comprehensive-llm-toolbox-for-ash-framework)
- [AshOban Documentation](https://hexdocs.pm/ash_oban)
- [Tool Definition Guide](https://hexdocs.pm/ash_ai/AshAi.html#module-tools)
- [ReqLLM Documentation](https://hexdocs.pm/req_llm)
- [LangChain to ReqLLM Migration Guide](https://hexdocs.pm/ash_ai/langchain-to-reqllm-migration.html)

## Context

In this lab, we'll integrate AshAi into our Twitter application to create an
AI-powered chat interface. AshAi provides a declarative approach to AI
integration with the Ash Framework, including chat generation, tool calling,
vectorization, and more.

We'll use `mix ash_ai.gen.chat` to generate a complete chat feature with:

- Streaming responses backed by Phoenix PubSub
- Durable agent responses backed by Oban
- Tool calling to interact with our Tweet resources
- Conversation persistence

## Prerequisites

Before starting, you'll need:

- An OpenAI API key (https://platform.openai.com/api-keys)
- AshAi installed (completed in Lab 11)

## Steps

### 1. Configure OpenAI API Key

AshAi's chat feature talks to LLM providers via
[ReqLLM](https://hexdocs.pm/req_llm). The chat generator (next step) adds the
required configuration to `config/runtime.exs` for you:

```elixir
config :req_llm, openai_api_key: System.get_env("OPENAI_API_KEY")
```

For a production release, use `System.fetch_env!/1` so a missing key fails at
startup instead of during a user's request. Keep `System.get_env/1` in local and
test environments where the AI integration may intentionally be disabled.

Other providers use the same pattern, e.g. `anthropic_api_key` or
`google_api_key` — configure only the ones you need.

While you're in `config/runtime.exs`: earlier versions of AshAi used LangChain,
and this app still carries a leftover
`config :langchain, :openai_key, System.get_env("OPENAI_API_KEY")` line at the
bottom of the file. Nothing reads it anymore — delete it.

All you need to do is set the environment variable in your terminal:

```bash
export OPENAI_API_KEY="your-api-key-here"
```

### 2. Generate Chat Resources

Run the chat generator:

```bash
mix ash_ai.gen.chat --live
```

Useful flags: `--provider` (e.g. `anthropic` or `gemini` instead of the OpenAI
default), `--route` (defaults to `/chat`), `--live-component` (an embeddable
LiveComponent instead of a full-page LiveView), and `--user`/`--domain` to
point at existing resources.

The generator will create:

- `Twitter.Chat` domain module
- `Twitter.Chat.Conversation` resource (for storing chat conversations)
- `Twitter.Chat.Message` resource (for storing individual messages)
- LiveView components for the chat interface
- Routes for accessing the chat

It also touches more than the chat resources: it installs `oban` (via
`ash_oban`), `mdex`, and `lumis` as dependencies, configures and supervises
Oban (in `config/config.exs` and `lib/twitter/application.ex`, plus
`config :twitter, Oban, testing: :manual` in `config/test.exs`), generates the
Oban and chat migrations, and adds the `:req_llm` API key config from step 1 to
`config/runtime.exs` if it's missing.

The generated response logic lives in
`lib/twitter/chat/message/changes/respond.ex`. It builds the message history
with `ReqLLM.Context` and runs the agent loop with `AshAi.ToolLoop.stream/2`,
passing a ReqLLM model string like `"openai:gpt-4o"`:

```elixir
prompt_messages
|> AshAi.ToolLoop.stream(
  otp_app: :twitter,
  tools: true,
  model: "openai:gpt-4o",
  actor: context.actor,
  tenant: context.tenant,
  context: Map.new(Ash.Context.to_opts(context))
)
```

### 3. Run Migrations

The generator already created the migration files for Oban and the chat
resources — all that's left is to apply them:

```bash
mix ash.migrate
```

### 4. Secure the Generated Chat Resources

The generator provides the chat mechanics, but your application still owns its
authorization model. Add `authorizers: [Ash.Policy.Authorizer]` to both chat
resources and enforce ownership:

```elixir
# Conversation
policy action(:create) do
  authorize_if actor_present()
end

policy action_type(:read) do
  authorize_if expr(user_id == ^actor(:id))
end

policy action(:destroy) do
  authorize_if expr(user_id == ^actor(:id))
end

# Message
policy action_type(:read) do
  authorize_if expr(conversation.user_id == ^actor(:id))
end
```

Add owner checks for message creation/destroy and explicit bypasses for the
generated internal Oban/AshAi actions. When a private `conversation_id` is
provided to message creation, load it through
`Twitter.Chat.get_conversation!/2` with the current action context before using
it. A private argument is not an authorization check.

Finally, pass `actor: socket.assigns.current_user` to `message_history!` in the
generated LiveView. Every read that relies on actor-scoped policies must receive
the actor.

### 5. Define Tweet Tools

Now we'll expose more Tweet actions as tools that the AI can call. In Lab 11 we
already added the `AshAi` extension to the `Twitter.Tweets` domain along with a
`tools` block containing the `:read_feed` tool — so open
`lib/twitter/tweets.ex` and add two more tools to that existing block:

```elixir
tools do
  tool :read_feed, Twitter.Tweets.Tweet, :feed do
    description "Retrieve the feed of tweets, sorted by most recent first"
  end

  # Add these two:
  tool :read_tweet, Twitter.Tweets.Tweet, :read do
    description "Retrieve a list of tweets, also supports filtering, sorting, and more"
  end

  tool :create_tweet, Twitter.Tweets.Tweet, :create do
    description "Create a new tweet with text content"
  end
end
```

(Tools can also be defined on the resource itself with the two-argument form
`tool :read_feed, :feed` inside a `tools` block on the resource.)

Note: the test `"exposes only the declared tweet feed tool"` in
`test/twitter/tweets/tweet_test.exs` (from Lab 11) asserts the exact list of
tools on the domain, so it will start failing here — update its expected tools
as you add new ones.

Then make the tools available to the chat agent. The generated `respond.ex`
ships with `tools: true`, which exposes every tool in the app to the agent —
including `:chat_list_conversations` and `:chat_message_history`, two starter
tools the generator defined on the `Twitter.Chat` domain. That's convenient,
but implicit: a tool added anywhere in the app silently becomes available to
the chat agent. Replace it with an explicit list in
`lib/twitter/chat/message/changes/respond.ex`:

```elixir
tools: [
  :read_feed,
  :read_tweet,
  :create_tweet
],
```

(If you want the agent to be able to browse the user's earlier conversations,
add the generated `:chat_list_conversations` and `:chat_message_history` tools
to the list as well.)

### 6. Test the Chat Interface

Start your Phoenix server:

```bash
mix phx.server
```

Navigate to the chat interface (the generator will output the route, typically
`http://localhost:4000/chat`).

Try asking the AI:

- "Show me the latest tweets"
- "Create a tweet that says 'Hello from AI!'"
- "What tweets are in the feed?"

Watch the console to see the AI making tool calls to your Tweet actions.

### 7. Configure Tool Calling Behavior

You can customize how tools behave with options in the tool definition. Update
a tool in `lib/twitter/tweets.ex`:

```elixir
tool :read_feed, Twitter.Tweets.Tweet, :feed do
  description "Retrieve the feed of tweets, sorted by most recent first. Returns a list of tweets with their text, user email, and like count."

  # Load calculations/aggregates/relationships into the tool's response
  load [:user_email, :like_count]

  # Run synchronously instead of the default async execution
  async false
end
```

Other useful options: `action_parameters` to limit which action arguments the
LLM can set, and `identity false` on update/destroy tools to stop the LLM from
addressing records by identity. Note that only `public? true` attributes can be
filtered or sorted on — private attributes can still be `load`ed into
responses, but the AI can't query by them.

### 8. Add a Like Tool

Let's add the ability for the AI to like tweets on behalf of the user. Add this
to the `tools` block:

```elixir
tool :like_tweet, Twitter.Tweets.Like, :like do
  description "Like a tweet. The current user will be marked as liking the tweet."
end
```

Remember to add `:like_tweet` to the `tools:` list in `respond.ex` too.

Now you can ask the AI: "Like the tweet with ID [some-uuid]"

### 9. Live-update the Feed When the AI Likes

The AI likes tweets in the background, so the feed doesn't know about it. Let's
broadcast like/unlike events with `Ash.Notifier.PubSub` and refresh the feed
when they arrive. Add the notifier to `Twitter.Tweets.Like`:

```elixir
use Ash.Resource,
  ...,
  notifiers: [Ash.Notifier.PubSub]

pub_sub do
  module TwitterWeb.Endpoint
  prefix "tweet"

  publish_all :create, "liked"

  publish_all :destroy, "unliked"
end
```

Then subscribe in `mount/3` of `TwitterWeb.TweetLive.Index` and reload the feed
when a message arrives:

```elixir
if connected?(socket) do
  TwitterWeb.Endpoint.subscribe("tweet:liked")
  TwitterWeb.Endpoint.subscribe("tweet:unliked")
end
```

```elixir
@impl true
def handle_info(%{topic: "tweet:" <> _liked_or_unliked}, socket) do
  {:noreply,
   socket
   |> stream(
     :tweets,
     Twitter.Tweets.feed!(actor: socket.assigns.current_user)
   )}
end
```

Now when the AI likes a tweet in the chat, the feed updates live in the other tab.

## Try on your own

- Add a tool for unliking tweets using the `:unlike` action
  - you should set `identity` to false
- Mount the Oban Web dashboard so you can watch the chat jobs: add
  `{:oban_web, "~> 2.0"}` to your deps, then `import Oban.Web.Router` and
  `oban_dashboard("/oban")` in your router's authenticated routes
- Test your tools without the UI: run
  `AshAi.iex_chat(otp_app: :twitter, model: "openai:gpt-4o", actor: user)` in
  `iex -S mix` and ask it to show the feed
- Switch the chat to a different provider by changing the model string in
  `respond.ex` (e.g. `"anthropic:claude-sonnet-4-5"`) and configuring the
  matching API key
- Give the agent your Lab 11 ash_lua runner: add `:ash_lua_eval` (already
  defined as a tool on the `Twitter.Agents` domain) to the `tools:` list in
  `respond.ex`, so the agent can compose several Ash actions in one script
  instead of making a separate tool call for each

## Verification

To verify your setup is working:

1. Check that the chat interface loads without errors
2. Send a message and confirm you receive a response
3. Ask the AI to "show me the tweets" and verify it makes a tool call
4. Check the database to see that conversations and messages are being persisted
5. Look at the Oban dashboard (if configured) to see background jobs processing
