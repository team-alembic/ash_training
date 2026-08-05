defmodule Twitter.Tweets.TweetTest do
  use ExUnit.Case, async: true

  alias Twitter.Tweets.Tweet

  test "defines the generated resource in the Tweets domain" do
    assert Tweet in Ash.Domain.Info.resources(Twitter.Tweets)

    action_names = MapSet.new(Ash.Resource.Info.actions(Tweet), & &1.name)
    assert MapSet.subset?(MapSet.new([:read, :destroy]), action_names)

    assert Enum.any?(Ash.Resource.Info.attributes(Tweet), &(&1.name == :id and &1.primary_key?))

    assert AshPostgres.DataLayer.Info.repo(Tweet) == Twitter.Repo
    assert AshPostgres.DataLayer.Info.table(Tweet) == "tweets"
  end
end
