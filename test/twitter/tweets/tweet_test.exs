defmodule Twitter.Tweets.TweetTest do
  use Twitter.DataCase, async: true

  alias Twitter.Tweets.Like
  alias Twitter.Tweets.Tweet

  setup do
    %{user: seed_user()}
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
    tweet = Ash.create!(Tweet, %{text: "first"}, action: :create, actor: user)
    assert tweet.text == "first"

    tweet = Ash.update!(tweet, %{text: "updated"}, action: :update)
    assert tweet.text == "updated"

    assert :ok = Ash.destroy!(tweet)
    assert {:ok, nil} = Ash.get(Tweet, tweet.id, not_found_error?: false)
  end

  test "relates the actor as the required author", %{user: user} do
    tweet = Ash.create!(Tweet, %{text: "owned"}, action: :create, actor: user)
    tweet = Ash.load!(tweet, :user)

    assert tweet.user.id == user.id
  end

  test "liking is idempotent and unlike only removes the actor's like", %{user: user} do
    other_user = seed_user()
    tweet = Ash.create!(Tweet, %{text: "popular"}, action: :create, actor: user)

    like = Ash.create!(Like, %{tweet_id: tweet.id}, action: :like, actor: user)
    duplicate = Ash.create!(Like, %{tweet_id: tweet.id}, action: :like, actor: user)
    Ash.create!(Like, %{tweet_id: tweet.id}, action: :like, actor: other_user)

    assert duplicate.id == like.id
    assert length(Ash.read!(Like)) == 2

    Ash.bulk_destroy!(Like, :unlike, %{tweet_id: tweet.id}, actor: user)

    assert [remaining] = Ash.read!(Like)
    assert remaining.user_id == other_user.id
  end

  test "destroying a tweet cascades to its likes", %{user: user} do
    tweet = Ash.create!(Tweet, %{text: "temporary"}, action: :create, actor: user)
    Ash.create!(Like, %{tweet_id: tweet.id}, action: :like, actor: user)

    Ash.destroy!(tweet)

    assert Ash.read!(Like) == []
  end

  test "validates tweet length", %{user: user} do
    assert {:error, error} =
             Ash.create(Tweet, %{text: String.duplicate("x", 256)}, action: :create, actor: user)

    assert Exception.message(error) =~ "no more than 255"
  end

  defp seed_user do
    Ash.Seed.seed!(Twitter.Accounts.User, %{
      email: "user-#{System.unique_integer([:positive])}@example.com",
      hashed_password: "not-used-in-tests"
    })
  end
end
