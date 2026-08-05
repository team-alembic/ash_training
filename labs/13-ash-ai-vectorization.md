# Lab 13 - Vectorization & RAG with Actions

> **Note**: This lab has been updated to reflect the correct setup process based
> on official documentation and testing. Key changes:
>
> - Added required Postgrex.Types.define setup (Steps 1-3)
> - Clarified that Ash auto-generates the vector extension migration (no manual
>   migration needed)
> - **Changed to `:ash_oban` strategy** instead of `:after_action` for
>   production-ready async processing
> - Embedding model uses `AshAi.EmbeddingModel` behavior with `generate/2`
>   callback
> - Extension is `AshAi` (not `AshAi.Resource`)
> - Policy check uses `AshOban.Checks.AshObanInteraction`
> - Includes Oban trigger configuration with proper module names

## Relevant Documentation

- [AshAi Vectorization Guide](https://hexdocs.pm/ash_ai/vectorization.html)
- [PostgreSQL pgvector Extension](https://github.com/pgvector/pgvector)
- [AshPostgres Vector Support](https://hexdocs.pm/ash_postgres/AshPostgres.Extensions.Vector.html)
- [Prompt-backed Actions](https://hexdocs.pm/ash_ai/prompt-backed-actions.html)
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

### 4. Create an Embedding Model Module

We need to configure how text gets converted to embeddings. Create a new file
`lib/twitter/ai/openai_embedding_model.ex`:

**CRITICAL**: The embedding model must implement the `AshAi.EmbeddingModel`
behavior with `dimensions/1` and `generate/2` callbacks.

```elixir
defmodule Twitter.Ai.OpenAiEmbeddingModel do
  @moduledoc """
  OpenAI embedding model for vectorizing text.
  Uses the text-embedding-3-small model (1536 dimensions).
  """
  use AshAi.EmbeddingModel

  @impl true
  def dimensions(_opts), do: 1536

  @impl true
  def generate(texts, _opts) do
    api_key = Application.get_env(:langchain, :openai_key)

    if is_nil(api_key) do
      raise "OPENAI_API_KEY not configured"
    end

    # Support both static keys and function-based keys
    api_key =
      if is_function(api_key, 0) do
        api_key.()
      else
        api_key
      end

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    body = %{
      "input" => texts,
      "model" => "text-embedding-3-small"
    }

    case Req.post("https://api.openai.com/v1/embeddings",
           json: body,
           headers: headers
         ) do
      {:ok, %{status: 200, body: response_body}} ->
        embeddings =
          response_body["data"]
          |> Enum.sort_by(& &1["index"])
          |> Enum.map(& &1["embedding"])

        {:ok, embeddings}

      {:ok, response} ->
        {:error, "OpenAI API error: #{inspect(response)}"}

      {:error, error} ->
        {:error, "Request failed: #{inspect(error)}"}
    end
  end
end
```

Add `req` to your dependencies in `mix.exs`:

```elixir
{:req, "~> 0.4"}
```

Then run:

```bash
mix deps.get
```

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

    # Store embeddings in this attribute (maps :text to :full_text_vector)
    attributes text: :full_text_vector

    # Use our OpenAI embedding model
    embedding_model Twitter.Ai.OpenAiEmbeddingModel

    # Use ash_oban strategy for async updates
    strategy :ash_oban
  end

  # Configure Oban trigger for vectorization
  oban do
    triggers do
      trigger :ash_ai_update_embeddings do
        action :ash_ai_update_embeddings
        queue :tweet_vectorizer
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
user = Twitter.Accounts.User |> Ash.Query.first!() |> Ash.read_one!()

# Create a tweet
tweet = Twitter.Tweets.Tweet
|> Ash.Changeset.for_create(:create, %{text: "Elixir is an amazing functional programming language"})
|> Ash.create!(actor: user)

# The vector won't be there immediately - it's being processed in the background
tweet.full_text_vector  # Will be nil at first

# Wait a moment for the Oban job to process, then reload

# Reload the tweet to see the vector
tweet = Twitter.Tweets.Tweet |> Ash.get!(tweet.id)
tweet.full_text_vector  # Now you'll see a long array of floats (1536 dimensions)
```

### 8. Create a Semantic Search Action

Add a read action that can search tweets by semantic similarity. In
`lib/twitter/tweets/tweet.ex`:

```elixir
actions do
  # ... existing actions ...

  read :semantic_search do
    argument :query, :string, allow_nil?: false

    prepare fn query, _context ->
      search_text = Ash.Query.get_argument(query, :query)

      # Get embedding for the search query using generate/2 (not embed/1)
      case Twitter.Ai.OpenAiEmbeddingModel.generate([search_text], []) do
        {:ok, [search_vector]} ->
          query
          |> Ash.Query.sort(
            {calc(vector_cosine_distance(full_text_vector, ^search_vector), type: :float),
             :asc}
          )
          |> Ash.Query.limit(10)

        {:error, error} ->
          Ash.Query.add_error(query, error)
      end
    end
  end
end
```

Add the vector distance function support to the postgres config:

```elixir
postgres do
  repo Twitter.Repo
  table "tweets"

  custom_indexes do
    # Add a vector index for faster similarity searches
    index [:full_text_vector],
      using: "hnsw",
      with: "m = 16, ef_construction = 64",
      concurrently: false
  end
end
```

Generate and run migrations:

```bash
mix ash.codegen add_vector_index
mix ash.migrate
```

### 9. Test Semantic Search

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

  prepare fn input, _context ->
    question = input.arguments.question
    limit = input.arguments.limit

    # Retrieve relevant tweets using semantic search
    context_tweets =
      Twitter.Tweets.Tweet
      |> Ash.Query.for_read(:semantic_search, %{query: question})
      |> Ash.Query.limit(limit)
      |> Ash.read!()
      |> Enum.map(fn tweet ->
        "- \"#{tweet.text}\""
      end)

    Ash.ActionInput.set_argument(input, :context, Enum.join(context_tweets, "\n"))
  end

  run prompt(
        LangChain.ChatModels.ChatOpenAI.new!(%{model: "gpt-4o-mini"}),
        prompt: """
        You are a helpful assistant answering questions about tweets.

        Here are some relevant tweets from our database:

        <%= @input.arguments.context %>

        User's question: <%= @input.arguments.question %>

        Please provide a helpful, concise answer based on the tweets above.
        If the tweets don't contain relevant information, acknowledge that
        and provide a general response.
        """,
        verbose?: true
      )
end
```

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
  and compare performance

- Create a `regenerate_embeddings` action to re-vectorize all existing tweets

- Add more sophisticated context retrieval (e.g., filter by date, user, or like
  count)

- Combine vector search with traditional filters (e.g., semantic search within
  tweets from the last week)

- Experiment with different embedding models (e.g., `text-embedding-3-large` for
  higher quality)

- Add a `relevance_score` to show how similar each context tweet is to the query

- Implement a chat interface that uses RAG to answer questions about tweets
