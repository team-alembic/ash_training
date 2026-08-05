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

  input(:question)
  input(:limit)

  # Step 1: Use LLM to reformulate question into optimal search query
  action :reformulate_query, Twitter.Tweets.Tweet, :reformulate_query do
    inputs %{
      question: input(:question)
    }
  end

  # Step 2: Fetch relevant tweets using the reformulated query
  read :fetch_context_tweets, Twitter.Tweets.Tweet, :semantic_search do
    inputs %{
      # Use the reformulated query!
      query: result(:reformulate_query),
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
