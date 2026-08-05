defmodule Twitter.Ai.RagReactorTest do
  use Twitter.DataCase, async: false

  alias Twitter.Tweets.Tweet

  @moduletag :external

  @tag timeout: 120_000
  test "reformulates a question, retrieves relevant tweets, and answers with their context" do
    user =
      Ash.Seed.seed!(Twitter.Accounts.User, %{
        email: "rag@example.com",
        hashed_password: "not-used-in-tests"
      })

    texts = [
      "Elixir handles concurrency with lightweight processes.",
      "Phoenix LiveView builds interactive real-time applications.",
      "Bananas are an excellent addition to breakfast."
    ]

    {:ok, vectors} =
      AshAi.EmbeddingModels.ReqLLM.generate(
        Enum.map(texts, &"Tweet: #{&1}\n"),
        model: "openai:text-embedding-3-small",
        dimensions: 1536
      )

    Enum.zip(texts, vectors)
    |> Enum.each(fn {text, vector} ->
      Ash.Seed.seed!(Tweet, %{
        text: text,
        user_id: user.id,
        full_text_vector: vector
      })
    end)

    question = "What are people saying about concurrency in Elixir?"

    result =
      Tweet
      |> Ash.ActionInput.for_action(:ask_with_reactor, %{question: question, limit: 2})
      |> Ash.run_action!()

    assert result.question == question
    assert is_binary(result.search_query) and result.search_query != ""
    assert is_binary(result.answer) and result.answer != ""
    assert result.context_count == 2
    assert length(result.context_tweets) == result.context_count
    assert Enum.any?(result.context_tweets, &String.contains?(&1, "Elixir"))
    assert String.contains?(result.answer, "Elixir")
  end
end
