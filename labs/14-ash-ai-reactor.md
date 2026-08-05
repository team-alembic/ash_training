# Lab 14 - RAG with Reactor

## Relevant Documentation

- [Reactor Documentation](https://hexdocs.pm/reactor)
- [Ash Reactor Extension](https://hexdocs.pm/ash/reactor.html)
- [Reactor in the Elixir Ecosystem](https://hexdocs.pm/reactor/ecosystem.html)
- [Generic Actions](https://hexdocs.pm/ash/generic-actions.html)
- [Ash Reactor Steps](https://hexdocs.pm/ash/Ash.Reactor.html)

## Context

In Lab 13, we implemented RAG using a `before_action` hook to fetch context and
inject it into a prompt. This approach works well for simple workflows, but has
limitations:

- **Sequential Execution** - Each step waits for the previous one
- **Limited Error Handling** - No automatic rollback or compensation
- **No Concurrency** - Can't parallelize independent operations
- **Difficult Testing** - Hard to test individual steps in isolation

**Reactor** is Elixir's solution for orchestrating complex workflows with:

- **Concurrent Execution** - Run independent steps in parallel
- **Automatic Rollbacks** - Saga pattern with compensating actions
- **Error Recovery** - Retry logic and graceful degradation
- **Composability** - Reactors can call other reactors

In this lab, we'll rebuild our RAG implementation using Reactor to gain these
benefits and demonstrate more sophisticated workflow orchestration.

## Steps

### 1. Add Reactor Dependencies

Reactor should already be installed as a dependency of Ash, but let's ensure we
have the Ash.Reactor extension available. In `mix.exs`, verify you have:

```elixir
{:ash, "~> 3.0"}
{:reactor, "~> 0.9"}  # Usually included via ash
```

Run `mix deps.get` if needed.

### 2. Create Prompt Actions for RAG Pipeline

We'll create two prompt-backed actions that our Reactor will orchestrate:

1. **Query reformulation** - Converts user question into optimal search query
2. **Answer generation** - Generates answer using retrieved context

Add these actions to `lib/twitter/tweets/tweet.ex`:

```elixir
# Step 1: Reformulate user question into optimal search query
action :reformulate_query, :string do
  argument :question, :string do
    allow_nil? false
    description "The original user question"
  end

  run prompt(
    LangChain.ChatModels.ChatOpenAI.new!(%{model: "gpt-4o-mini"}),
    prompt: """
    You are an expert at reformulating questions into effective search queries.

    User's question: <%= @input.arguments.question %>

    Generate a concise search query (2-5 keywords) that will find the most
    relevant tweets to answer this question. Return ONLY the search query,
    nothing else.

    Examples:
    Question: "What are people saying about Elixir's performance?"
    Query: "Elixir performance speed fast"

    Question: "How does Phoenix compare to Rails?"
    Query: "Phoenix Rails comparison framework"
    """
  )
end

# Step 2: Generate answer using retrieved context
action :answer_with_context, :string do
  argument :question, :string do
    allow_nil? false
    description "The question to answer"
  end

  argument :context, :string do
    allow_nil? false
    description "Pre-built context from semantic search"
  end

  run prompt(
    LangChain.ChatModels.ChatOpenAI.new!(%{model: "gpt-4o-mini"}),
    prompt: """
    You are a helpful assistant answering questions about tweets.

    Here are some relevant tweets from our database:

    <%= @input.arguments.context %>

    User's question: <%= @input.arguments.question %>

    Please provide a helpful, concise answer based on the tweets above.
    """
  )
end
```

Update the policy to allow both actions:

```elixir
policy action([:create, :ask, :reformulate_query, :answer_with_context]) do
  authorize_if always()
end
```

### 3. Create a Reactor Module for RAG

Now create a Reactor that orchestrates the workflow by calling Ash actions.
Create `lib/twitter/ai/rag_reactor.ex`:

```elixir
defmodule Twitter.Ai.RagReactor do
  @moduledoc """
  Reactor for multi-LLM RAG workflow using Ash actions.

  Workflow:
  1. LLM reformulates user question into optimal search query
  2. Semantic search retrieves relevant tweets using reformulated query
  3. LLM generates answer using retrieved context

  All LLM calls go through Ash prompt actions, not manual API calls.
  """

  use Reactor, extensions: [Ash.Reactor]

  input :question
  input :limit

  # Step 1: Use LLM to reformulate question into optimal search query
  action :reformulate_query, Twitter.Tweets.Tweet, :reformulate_query do
    inputs %{
      question: input(:question)
    }
  end

  # Step 2: Fetch relevant tweets using the reformulated query
  read :fetch_context_tweets, Twitter.Tweets.Tweet, :semantic_search do
    inputs %{
      query: result(:reformulate_query)  # Use the reformulated query!
    }
  end

  # Step 3: Build context string from tweets
  step :build_context do
    argument :tweets, result(:fetch_context_tweets)

    run fn %{tweets: tweets}, _context ->
      context =
        tweets
        |> Enum.map(fn tweet -> "- \"#{tweet.text}\"" end)
        |> Enum.join("\n")

      {:ok, context}
    end
  end

  # Step 4: Use LLM to generate answer with context
  action :generate_answer, Twitter.Tweets.Tweet, :answer_with_context do
    inputs %{
      question: input(:question),
      context: result(:build_context)
    }
  end

  # Step 5: Format the final response
  step :format_response do
    argument :answer, result(:generate_answer)
    argument :tweets, result(:fetch_context_tweets)
    argument :question, input(:question)
    argument :search_query, result(:reformulate_query)

    run fn args, _context ->
      response = %{
        question: args.question,
        search_query: args.search_query,
        answer: args.answer,
        context_tweets: Enum.map(args.tweets, & &1.text),
        context_count: length(args.tweets)
      }

      {:ok, response}
    end
  end

  # Return the formatted response
  return :format_response
end
```

Key improvements:

- **Multi-LLM workflow**: Query reformulation → Retrieval → Answer generation
- Uses `action` step for prompt-backed actions (reformulate_query,
  answer_with_context)
- Uses `read` step for semantic search
- No manual API calls - everything goes through Ash actions
- Shows how one LLM's output (`reformulate_query`) feeds into retrieval step
- Response includes the reformulated query for transparency

### 4. Add a Reactor-Based Action to Tweet

Add a generic action to Tweet that uses the Reactor directly. Ash automatically
handles running the Reactor when you pass the module to `run`.

Add to `lib/twitter/tweets/tweet.ex`:

```elixir
action :ask_with_reactor, :map do
  argument :question, :string, allow_nil?: false
  argument :limit, :integer, default: 5

  # Pass the Reactor module directly - Ash handles execution automatically
  run Twitter.Ai.RagReactor
end
```

Update the policy:

```elixir
policy action([:create, :ask, :reformulate_query, :answer_with_context, :ask_with_reactor]) do
  authorize_if always()
end
```

**Key insight**: You don't need to manually call `Reactor.run/4`. Just pass the
Reactor module to `run` and Ash:

- Automatically maps action arguments to Reactor inputs
- Passes the action context into the Reactor's context
- Handles the Reactor execution lifecycle

### 5. Add Code Interface for the New Action

To make the action easier to call, add it to the code interface in
`lib/twitter/tweets.ex`:

```elixir
resources do
  resource Twitter.Tweets.Tweet do
    define :feed
    define :get_tweet, action: :read, get_by: [:id]
    define :delete_tweet, action: :destroy
    define :ask_tweet_question, action: :ask, args: [:question]
    define :ask_tweet_reactor_question, action: :ask_with_reactor, args: [:question]  # Add this line
  end

  # ... rest of resources
end
```

Now you can call the action directly:
`Twitter.Tweets.ask_tweet_reactor_question("What are people saying about Elixir?")`

### 6. Test the Reactor-Based RAG

Test the new Reactor-based action in IEx:

```elixir
# Compare with the simple action from Lab 13
simple_result = Twitter.Tweets.Tweet
|> Ash.ActionInput.for_action(:ask, %{question: "What are people saying about Elixir?"})
|> Ash.run_action!()

IO.puts("Simple action result:")
IO.puts(simple_result)

# Now try the Reactor-based approach with query reformulation
reactor_result = Twitter.Tweets.Tweet
|> Ash.ActionInput.for_action(:ask_with_reactor, %{
  question: "What are people saying about Elixir?",
  limit: 5
})
|> Ash.run_action!()

IO.puts("\nReactor-based result:")
IO.inspect(reactor_result)

# Output will include the reformulated search query:
# %{
#   question: "What are people saying about Elixir?",
#   search_query: "Elixir programming language features benefits",
#   answer: "Based on the tweets...",
#   context_tweets: [...],
#   context_count: 5
# }
```

Notice how the Reactor result includes `:search_query` showing how the LLM
reformulated the question for better semantic search results.

## Try on your own

- Implement a "critique and refine" pattern where one LLM critiques another's
  response
