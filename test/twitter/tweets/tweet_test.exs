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

    tweet = Ash.update!(tweet, %{text: "updated"}, action: :update, actor: user)
    assert tweet.text == "updated"

    assert :ok = Ash.destroy!(tweet, actor: user)
    assert {:ok, nil} = Ash.get(Tweet, tweet.id, not_found_error?: false)
  end

  test "relates the actor as the required author", %{user: user} do
    tweet = Ash.create!(Tweet, %{text: "owned"}, action: :create, actor: user)
    tweet = Ash.load!(tweet, :user, actor: user)

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

    Ash.destroy!(tweet, actor: user)

    assert Ash.read!(Like) == []
  end

  test "validates tweet length", %{user: user} do
    assert {:error, error} =
             Ash.create(Tweet, %{text: String.duplicate("x", 256)}, action: :create, actor: user)

    assert Exception.message(error) =~ "no more than 255"
  end

  test "loads expression calculations for the current actor", %{user: user} do
    other_user = seed_user()
    tweet = Ash.create!(Tweet, %{text: "calculated"}, action: :create, actor: user)
    Ash.create!(Like, %{tweet_id: tweet.id}, action: :like, actor: user)

    liked = Ash.load!(tweet, [:text_length, :liked_by_me], actor: user)
    not_liked = Ash.load!(tweet, :liked_by_me, actor: other_user)

    assert liked.text_length == 10
    assert liked.liked_by_me
    refute not_liked.liked_by_me
  end

  test "loads like count and author email aggregates", %{user: user} do
    tweet = Ash.create!(Tweet, %{text: "aggregated"}, action: :create, actor: user)
    Ash.create!(Like, %{tweet_id: tweet.id}, action: :like, actor: user)

    tweet = Ash.load!(tweet, [:like_count, :user_email], actor: user)

    assert tweet.like_count == 1
    assert to_string(tweet.user_email) == to_string(user.email)
  end

  test "only the author can update or destroy a tweet", %{user: user} do
    other_user = seed_user()
    tweet = Ash.create!(Tweet, %{text: "private mutation"}, action: :create, actor: user)

    assert Ash.can?({tweet, :update}, user)
    assert Ash.can?({tweet, :destroy}, user)
    refute Ash.can?({tweet, :update}, other_user)
    refute Ash.can?({tweet, :destroy}, other_user)

    assert_raise Ash.Error.Forbidden, fn ->
      Ash.update!(tweet, %{text: "hijacked"}, action: :update, actor: other_user)
    end

    assert_raise Ash.Error.Forbidden, fn ->
      Ash.destroy!(tweet, actor: other_user)
    end
  end

  test "domain code interfaces cover feed, get, delete, like, and unlike", %{user: user} do
    tweet = Ash.create!(Tweet, %{text: "interface"}, action: :create, actor: user)

    assert [fetched] = Twitter.Tweets.feed!(actor: user)
    assert fetched.id == tweet.id
    assert Twitter.Tweets.get_tweet!(tweet.id, actor: user).id == tweet.id

    like = Twitter.Tweets.like!(tweet.id, actor: user)
    assert like.tweet_id == tweet.id

    Twitter.Tweets.unlike!(tweet.id, actor: user)
    assert Ash.read!(Like) == []

    assert :ok = Twitter.Tweets.delete_tweet!(tweet.id, actor: user)
  end

  test "AshPhoenix forms submit actions and retain validation errors", %{user: user} do
    form = AshPhoenix.Form.for_create(Tweet, :create, actor: user)

    invalid_form =
      AshPhoenix.Form.validate(form, %{"text" => String.duplicate("x", 256)}, errors: true)

    refute invalid_form.valid?

    assert {:ok, tweet} = AshPhoenix.Form.submit(form, params: %{"text" => "from a form"})
    assert tweet.text == "from a form"

    update_form = AshPhoenix.Form.for_update(tweet, :update, actor: user)
    assert {:ok, updated} = AshPhoenix.Form.submit(update_form, params: %{"text" => "edited"})
    assert updated.text == "edited"
  end

  test "exposes the tweet feed as a tool" do
    tools = AshAi.Info.tools(Twitter.Tweets)

    assert %AshAi.Tool{resource: Tweet, action: :feed} =
             Enum.find(tools, &(&1.name == :read_feed))
  end

  defp seed_user do
    Ash.Seed.seed!(Twitter.Accounts.User, %{
      email: "user-#{System.unique_integer([:positive])}@example.com",
      hashed_password: "not-used-in-tests"
    })
  end
end
