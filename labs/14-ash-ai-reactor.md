# Lab 14 - RAG with Reactor

## Relevant Documentation

- [Reactor Documentation](https://hexdocs.pm/reactor)
- [Ash Reactor Extension](https://hexdocs.pm/ash/reactor.html)
- [Reactor in the Elixir Ecosystem](https://hexdocs.pm/reactor/ecosystem.html)
- [Generic Actions](https://hexdocs.pm/ash/generic-actions.html)
- [Ash Reactor Steps](https://hexdocs.pm/ash/Ash.Reactor.html)

## Context

In Lab 13, we implemented RAG inside one action preparation. That works for a
small workflow, but it hides retrieval and prompt stages inside one callback.

Reactor makes the dataflow explicit and composable. It can also run independent
steps concurrently and support retries or compensation when those behaviors are
configured. This lab builds a sequential dependency graph and does not add undo,
compensation, or custom retry behavior; its focus is clear orchestration through
Ash actions.

## Steps

### 1. Add Reactor Dependencies

Reactor should already be installed as a dependency of Ash, but let's ensure we
have the Ash.Reactor extension available. In `mix.exs`, verify you have:

```elixir
{:ash, "~> 3.0"}
```

Reactor is included as a dependency of Ash — you can confirm with
`mix deps | grep reactor`. No changes should be needed.

The LLM calls in this lab go through the same ReqLLM setup you configured in Lab
12 (provider API keys under `config :req_llm` in `config/runtime.exs`), so no
additional AI dependencies are needed here.

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

  run prompt("openai:gpt-4o-mini",
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

  run prompt("openai:gpt-4o-mini",
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

As in Lab 13, the first argument to `prompt/2` is a ReqLLM model spec string in
`"provider:model-name"` format. Swapping providers is a one-string change — e.g.
`"anthropic:claude-sonnet-4-5"` — with no other code changes.

Update the policy to allow both actions:

```elixir
policy action([:create, :ask, :reformulate_query, :answer_with_context]) do
  authorize_if always()
end
```

### 3. Create a Reactor Module for RAG

Now create a Reactor that orchestrates the workflow by calling Ash actions.
Create `lib/twitter/ai/rag_reactor.ex` (the `lib/twitter/ai/` directory doesn't
exist yet — create it first):

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
      query: result(:reformulate_query), # Use the reformulated query!
      limit: input(:limit)
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
- Passes the caller's result limit into semantic search
- Response includes the reformulated query for transparency

**Bonus: retries with backoff (the saga pattern in action)**

The Context section mentioned that Reactor supports retries and compensating
actions when configured — here is what that looks like. Generic `step`s carry
Reactor's compensation machinery: a `compensate` callback (return `:retry` to
run the step again), `max_retries` to bound the attempts, and `backoff` to space
them out. LLM APIs are exactly the kind of flaky dependency (rate limits,
timeouts) this exists for. Try swapping the `:generate_answer` action step for a
generic step that calls the same prompt action, but retries on failure:

```elixir
# A retry-capable drop-in for the :generate_answer step
step :generate_answer do
  argument :question, input(:question)
  argument :context, result(:build_context)

  max_retries 2

  run fn args, _context ->
    Twitter.Tweets.Tweet
    |> Ash.ActionInput.for_action(:answer_with_context, %{
      question: args.question,
      context: args.context
    })
    |> Ash.run_action()
  end

  # Returning :retry tells Reactor to run the step again
  compensate fn _error, _args, _context ->
    :retry
  end

  # Exponential backoff between attempts: 1s, 2s, 4s...
  backoff fn _error, _args, context ->
    round(:math.pow(2, Map.get(context, :current_try, 0)) * 1000)
  end
end
```

The rollback half of the saga applies to steps that write data: Ash.Reactor's
`create`, `update`, `destroy`, and `action` steps accept `undo` and
`undo_action` options, and Reactor calls the compensating action automatically
when a later step fails. Our RAG workflow is read-only, so there is nothing to
roll back here — but the same reactor could seed tweets with a `create` step and
have them undone if answer generation blew up.

### 4. Add a Reactor-Based Action to Tweet

Add a generic action to Tweet that uses the Reactor directly. Ash automatically
handles running the Reactor when you pass the module to `run`.

Add to `lib/twitter/tweets/tweet.ex`:

```elixir
action :ask_with_reactor, :map do
  argument :question, :string, allow_nil?: false
  argument :limit, :integer,
    allow_nil?: false,
    default: 5,
    constraints: [min: 1, max: 100]

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
resource Twitter.Tweets.Tweet do
  # ... keep the existing defines as they are ...
  define :ask_tweet_reactor_question, action: :ask_with_reactor, args: [:question]
end
```

Only the last line is new — leave the existing `define`s (including their
`default_options`) untouched.

Now you can call the action directly:
`Twitter.Tweets.ask_tweet_reactor_question!("What are people saying about Elixir?")`

(As with all code interfaces, the non-bang variant returns `{:ok, result}`; the
`!` variant returns the result map directly.)

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
- Swap the LLM provider by changing the model spec string in one of the prompt
  actions — no other code changes needed
- Add retry-with-backoff (from the bonus in Step 3) to the `:reformulate_query`
  step as well
- Give the answer action a custom tool via `extra_tools:` and
  `ReqLLM.Tool.new!/1` (see the prompt-backed actions docs). Two gotchas: the
  tool is built while the resource's DSL is compiled, so an inline anonymous
  `callback:` fails to compile (functions cannot be escaped into the module),
  and an MFA tuple like `{MyModule, :my_fun}` fails `ReqLLM.Tool.new!/1`'s
  `function_exported?` check because the module isn't compiled yet at DSL
  evaluation time. What works: define the callback in a separate module and pass
  a remote capture — `&MyModule.my_fun/1`
- Add a `guard` or `where` clause so `:generate_answer` is skipped when
  `:fetch_context_tweets` returns no tweets
- Build a seeding reactor that uses Ash.Reactor's `bulk_create` step with an
  `undo_action`, then force a later step to fail and watch the saga roll the
  seeded records back
