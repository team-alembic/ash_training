defmodule Twitter.Tweets.TweetTest do
  use Twitter.DataCase, async: true

  alias Twitter.Tweets.Tweet

  setup do
    user =
      Ash.Seed.seed!(Twitter.Accounts.User, %{
        email: "user-#{System.unique_integer([:positive])}@example.com",
        hashed_password: "not-used-in-tests"
      })

    %{user: user}
  end

  test "defines the generated resource in the Tweets domain" do
    assert Tweet in Ash.Domain.Info.resources(Twitter.Tweets)

    action_names = MapSet.new(Ash.Resource.Info.actions(Tweet), & &1.name)
    assert MapSet.subset?(MapSet.new([:read, :destroy]), action_names)

    assert Enum.any?(Ash.Resource.Info.attributes(Tweet), &(&1.name == :id and &1.primary_key?))

    assert AshPostgres.DataLayer.Info.repo(Tweet) == Twitter.Repo
    assert AshPostgres.DataLayer.Info.table(Tweet) == "tweets"
  end

  test "creates, updates, and destroys a tweet", %{user: user} do
    tweet = Ash.create!(Tweet, %{text: "first", user_id: user.id}, action: :create)
    assert tweet.text == "first"

    tweet = Ash.update!(tweet, %{text: "updated"}, action: :update)
    assert tweet.text == "updated"

    assert :ok = Ash.destroy!(tweet)
    assert {:ok, nil} = Ash.get(Tweet, tweet.id, not_found_error?: false)
  end

  test "loads the required author relationship", %{user: user} do
    tweet = Ash.create!(Tweet, %{text: "owned", user_id: user.id}, action: :create)
    tweet = Ash.load!(tweet, :user)

    assert tweet.user.id == user.id
  end
end
