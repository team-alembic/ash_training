# Lab 13 - Vectorization & RAG with Actions

## Relevant Documentation

- [AshAi Vectorization](https://hexdocs.pm/ash_ai/readme.html#vectorization)
- [PostgreSQL pgvector Extension](https://github.com/pgvector/pgvector)
- [AshPostgres Vector Support](https://hexdocs.pm/ash_postgres/AshPostgres.Extensions.Vector.html)
- [Prompt-backed Actions](https://hexdocs.pm/ash_ai/AshAi.Actions.Prompt.html)
- [LangChain to ReqLLM Migration](https://hexdocs.pm/ash_ai/langchain-to-reqllm-migration.html)
- [Action Hooks](https://hexdocs.pm/ash/actions.html#module-action-hooks)

## Context

Retrieval-Augmented Generation (RAG) is a technique that enhances LLM responses
by providing relevant context from your data. The process involves:

1. **Vectorization** - Converting text into numerical embeddings that capture
   semantic meaning
2. **Storage** - Saving these embeddings alongside your data using pgvector
3. **Retrieval** - Finding semantically similar content using vector distance
   calculations
4. **Augmentation** - Injecting retrieved context into LLM prompts for better
   responses

In this lab, we'll implement RAG using AshAi's vectorization features and action
hooks. We'll make tweets searchable by semantic meaning, not just keywords, and
create an AI action that uses relevant tweets as context.

## Steps

### 1. Create Postgrex Types Definition File

**CRITICAL**: Before anything else, we need to define custom Postgrex types to
support the vector extension. This is required by AshPostgres.Extensions.Vector.

Create `lib/twitter/postgrex_types.ex` (note: this must be at the **file
level**, NOT inside a module):

```elixir
Postgrex.Types.define(Twitter.PostgrexTypes,
  [AshPostgres.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(),
  []
)
```

### 2. Configure Repo to Use Custom Types

Add to `config/config.exs`:

```elixir
config :twitter, Twitter.Repo,
  types: Twitter.PostgrexTypes
```

### 3. Add Vector to Installed Extensions

Update `lib/twitter/repo.ex` to include `"vector"` in the installed extensions:

```elixir
def installed_extensions do
  ["citext", "ash-functions", "vector"]
end
```

**Note**: Unlike the old approach, you do NOT need to manually create a
migration for the vector extension. Ash will auto-generate the
`CREATE EXTENSION IF NOT EXISTS vector` migration when you run `mix ash.codegen`
in a later step!

### 4. Configure the Embedding Model

We need to configure how text gets converted to embeddings. AshAi ships with a
built-in embedding model, `AshAi.EmbeddingModels.ReqLLM`, which uses the ReqLLM
library under the hood to talk to any supported provider (OpenAI, Google,
Cohere, Voyage, ...). You point it at a provider with a model spec string like
`"openai:text-embedding-3-small"` — no HTTP client code required.

The only setup needed is telling ReqLLM about your API key — we already did this
in Lab 12, in `config/runtime.exs`:

```elixir
config :req_llm, openai_api_key: openai_api_key
```

Make sure `OPENAI_API_KEY` is set in your shell environment before starting the
app.

We'll wire the embedding model into the Tweet resource in the next step, as a
tuple of module and options:

```elixir
{AshAi.EmbeddingModels.ReqLLM,
 model: "openai:text-embedding-3-small",
 dimensions: 1536}
```

> **Aside — bring your own provider**: Under the hood, an embedding model is any
> module implementing the `AshAi.EmbeddingModel` behavior, which has just two
> callbacks: `dimensions/1` (the vector size) and `generate/2` (texts in,
> `{:ok, vectors}` out). If you ever need a provider ReqLLM doesn't support — or
> a local model — you can write your own module with `use AshAi.EmbeddingModel`
> and pass it in place of the built-in one.

### 5. Add Vectorization to Tweet Resource

Now we'll configure the Tweet resource to automatically vectorize its content
using async background jobs.

**IMPORTANT**:

- The extension is `AshAi` (not `AshAi.Resource`)
- We use `:ash_oban` strategy for async processing (not `:after_action`)
- Must add `AshOban` extension
- Must configure Oban trigger with module names

Open `lib/twitter/tweets/tweet.ex` and make these changes:

```elixir
defmodule Twitter.Tweets.Tweet do
  use Ash.Resource,
    otp_app: :twitter,
    domain: Twitter.Tweets,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [
      AshGraphql.Resource,
      AshJsonApi.Resource,
      AshAi,      # Add this extension (not AshAi.Resource!)
      AshOban     # Required for async vectorization
    ]

  # Add this vectorize block BEFORE actions
  vectorize do
    # Vectorize the full content of the tweet
    full_text do
      text fn tweet ->
        """
        Tweet: #{tweet.text}
        """
      end

      used_attributes [:text]
    end

    # Use the builtin ReqLLM-backed OpenAI embedding model
    embedding_model {AshAi.EmbeddingModels.ReqLLM,
                     model: "openai:text-embedding-3-small", dimensions: 1536}

    # Use ash_oban strategy for async updates
    strategy :ash_oban
  end

  # Configure Oban trigger for vectorization
  oban do
    triggers do
      trigger :ash_ai_update_embeddings do
        action :ash_ai_update_embeddings
        queue :tweet_vectorizer
        # The trigger runs when vectorizable fields change; it is not a cron job.
        scheduler_cron false
        worker_read_action :read
        worker_module_name Twitter.Tweets.Tweet.AshOban.Worker.AshAiUpdateEmbeddings
        scheduler_module_name Twitter.Tweets.Tweet.AshOban.Scheduler.AshAiUpdateEmbeddings
      end
    end
  end

  # ... existing actions ...

  policies do
    # Allow AshOban to update embeddings
    bypass action(:ash_ai_update_embeddings) do
      authorize_if AshOban.Checks.AshObanInteraction
    end

    # ... rest of existing policies ...
  end

  # ... rest of existing code ...
end
```

Add the `tweet_vectorizer` queue to your Oban configuration in
`config/config.exs`:

```elixir
config :twitter, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [
    default: 10,
    chat_responses: [limit: 10],
    conversations: [limit: 10],
    tweet_vectorizer: [limit: 20]  # Add this queue
  ],
  repo: Twitter.Repo,
  plugins: [{Oban.Plugins.Cron, []}]
```

### 6. Generate and Run Migrations

The vectorization configuration needs to add a vector column to the tweets
table:

```bash
mix ash.codegen add_tweet_vectors
mix ash.migrate
```

This creates a new column `full_text_vector` of type `vector(1536)` (the
dimension of OpenAI's text-embedding-3-small model).

### 7. Test Vectorization

Start an IEx session and create a tweet to see vectorization in action:

```bash
iex -S mix phx.server
```

**Note**: Since we're using the `:ash_oban` strategy, vectorization happens
asynchronously in a background job. The vector won't be immediately available
after creating the tweet.

```elixir
# Get or create a user first
user = Ash.read_first!(Twitter.Accounts.User)

# Create a tweet
tweet = Twitter.Tweets.Tweet
|> Ash.Changeset.for_create(:create, %{text: "Elixir is an amazing functional programming language"}, actor: user)
|> Ash.create!()

# The vector won't be there immediately - it's being processed in the background
tweet.full_text_vector  # Will be %Ash.NotLoaded{} (nil in the database) at first

# Wait a moment for the Oban job to process, then reload

# Reload the tweet to see the vector.
# Note: vector attributes are NOT selected by default (they're large!),
# so we have to select the vector explicitly.
require Ash.Query

tweet =
  Twitter.Tweets.Tweet
  |> Ash.Query.select([:full_text_vector])
  |> Ash.Query.filter(id == ^tweet.id)
  |> Ash.read_one!()

tweet.full_text_vector  # Now you'll see a long array of floats (1536 dimensions)
```

**Note**: In the test environment Oban is configured with `testing: :manual`, so
vectorization jobs are never run automatically. In tests, drain the queue
explicitly with `Oban.drain_queue(queue: :tweet_vectorizer)`.

### 8. Create a Semantic Search Action

Add a read action that can search tweets by semantic similarity. In
`lib/twitter/tweets/tweet.ex`:

```elixir
actions do
  # ... existing actions ...

  read :semantic_search do
    argument :query, :string, allow_nil?: false
    argument :limit, :integer,
      allow_nil?: false,
      default: 10,
      constraints: [min: 1, max: 100]

    prepare fn query, _context ->
      search_text = Ash.Query.get_argument(query, :query)
      limit = Ash.Query.get_argument(query, :limit)

      # Generate an embedding for the search query. When calling the
      # embedding model directly, we pass the same options we gave it
      # in the vectorize block.
      case AshAi.EmbeddingModels.ReqLLM.generate([search_text],
             model: "openai:text-embedding-3-small",
             dimensions: 1536
           ) do
        {:ok, [search_vector]} ->
          query
          |> Ash.Query.sort(
            {calc(vector_cosine_distance(full_text_vector, ^search_vector), type: :float),
             :asc}
          )
          |> Ash.Query.limit(limit)

        {:error, error} ->
          Ash.Query.add_error(query, error)
      end
    end
  end
end
```

Add a vector index for faster similarity searches to the postgres config. Note
that we have to spell out the operator class (`vector_cosine_ops`) as part of
the field, since `hnsw` has no default operator class:

```elixir
postgres do
  repo Twitter.Repo
  table "tweets"

  custom_indexes do
    index ["full_text_vector vector_cosine_ops"],
      name: "tweets_full_text_vector_index",
      using: "hnsw",
      concurrently: true
  end
end
```

(`hnsw` indexes also accept tuning parameters via the `with:` option, e.g.
`with: "m = 16, ef_construction = 64"` — the defaults are fine for this lab.)

Generate and run migrations:

```bash
mix ash.codegen add_vector_index
mix ash.migrate
```

Finally, expose the new action as a tool so the AI can search semantically. In
`lib/twitter/tweets.ex`, add it to the existing `tools` block:

```elixir
tool :semantic_search_tweets, Twitter.Tweets.Tweet, :semantic_search do
  description "Perform a semantic search over tweets based on a query string"
end
```

(We leave the chat agent's explicit `tools:` list in `respond.ex` alone for now
— wiring RAG into the chat is one of the "Try on your own" exercises. This is
also a good moment to revisit the `lua` block from Lab 11 if you want Lua
scripts to search semantically too: add
`action :search, Twitter.Tweets.Tweet, :semantic_search, labels: [:agent, :read_only]`
to the `tweets` namespace in `lib/twitter/tweets.ex`.)

### 9. Test Semantic Search

Before searching, seed a handful of tweets on different topics (3-5 is plenty —
say cooking, sports, and programming) so there's something for the ranking to be
observable against.

In IEx, try searching:

```elixir
# Search for tweets about programming
Twitter.Tweets.Tweet
|> Ash.Query.for_read(:semantic_search, %{query: "functional programming languages"})
|> Ash.read!()
```

This should return tweets semantically similar to the query, not just keyword
matches.

### 10. Create a RAG-Enabled Prompt Action

Now we'll create a generic action on the Tweet resource that uses vectorization
to retrieve relevant tweets and uses them as context for an LLM.

Open `lib/twitter/tweets/tweet.ex` and add this action after `:semantic_search`:

```elixir
action :ask, :string do
  argument :question, :string do
    allow_nil? false
    description "The question to ask about tweets"
  end

  argument :limit, :integer do
    default 3
    description "Number of context tweets to retrieve"
  end

  argument :context, :string do
    public? false
    allow_nil? true
  end

  prepare fn input, context ->
    question = input.arguments.question
    limit = input.arguments.limit

    # Retrieve relevant tweets using semantic search
    context_tweets =
      Twitter.Tweets.Tweet
      |> Ash.Query.for_read(:semantic_search, %{query: question, limit: limit})
      |> Ash.read!(scope: context)
      |> Enum.map(fn tweet ->
        "- \"#{tweet.text}\""
      end)

    Ash.ActionInput.set_argument(input, :context, Enum.join(context_tweets, "\n"))
  end

  run prompt(
        "openai:gpt-4o-mini",
        prompt: """
        You are a helpful assistant answering questions about tweets.

        Here are some relevant tweets from our database:

        <%= @input.arguments.context %>

        User's question: <%= @input.arguments.question %>

        Please provide a helpful, concise answer based on the tweets above.
        If the tweets don't contain relevant information, acknowledge that
        and provide a general response.
        """
      )
end
```

Note that the first argument to `prompt/2` is a ReqLLM model spec string —
`"provider:model-name"`. Swapping to another provider (say,
`"anthropic:claude-sonnet-4-5"`) is just a matter of changing the string and
configuring that provider's API key. The prompt itself is an EEx template with
access to `@input`, so arguments set in the `prepare` hook (like our retrieved
`:context`) flow straight into it.

Don't forget to add the `:ask` action to the policy block:

```elixir
policy action([:create, :ask]) do
  authorize_if always()
end
```

### 11. Test RAG Query

Test the new `:ask` action in IEx:

```elixir
# Ask a question and get an AI-generated answer based on relevant tweets
result = Twitter.Tweets.Tweet
|> Ash.ActionInput.for_action(:ask, %{question: "What are people saying about Elixir?"})
|> Ash.run_action!()

IO.puts(result)
# Output: "The tweets provided do not contain any information about Elixir..."

# Try with custom limit for more context
result = Twitter.Tweets.Tweet
|> Ash.ActionInput.for_action(:ask, %{
  question: "Tell me about programming",
  limit: 5
})
|> Ash.run_action!()

IO.puts(result)
```

The `:ask` action will:

1. Use `:semantic_search` to find the most relevant tweets
2. Build a prompt with those tweets as context
3. Call the LLM to generate an answer
4. Return the answer as a string

### 12. Add Code Interface (Optional)

You can add a code interface to make asking questions easier. In
`lib/twitter/tweets.ex`:

```elixir
resources do
  resource Twitter.Tweets.Tweet do
    # ... existing defines ...
    define :ask, action: :ask, args: [:question]
  end
end
```

Now you can use:

```elixir
Twitter.Tweets.ask("What are people tweeting about Elixir?")
```

## Try on your own

- Add vectorization to user bios and search users by semantic similarity

- Implement multiple vectorization strategies (`:after_action` vs `:ash_oban`)
  and compare performance (hint: with `:after_action` the embedding update is no
  longer run by AshOban, so the policy bypass needs a different check:
  `bypass action(:ash_ai_update_embeddings) do authorize_if AshAi.Checks.ActorIsAshAi end`)

- Create a `regenerate_embeddings` action to re-vectorize all existing tweets

- Add more sophisticated context retrieval (e.g., filter by date, user, or like
  count)

- Combine vector search with traditional filters (e.g., semantic search within
  tweets from the last week)

- Experiment with different embedding models — with the built-in ReqLLM model
  this is just a different model string (e.g., `"openai:text-embedding-3-large"`
  for higher quality, or even another provider entirely — just remember to
  update `dimensions` to match)

- Add a `relevance_score` to show how similar each context tweet is to the query

- Implement a chat interface that uses RAG to answer questions about tweets
